@echo off
setlocal
rem ============================================================
rem  CBR / CB7 / CBT / PDF / EPUB / MOBI / AZW / AZW3 -> CBZ  (alles in dieser einen Datei)
rem  Dateien oder Ordner per Drag and Drop auf diese BAT ziehen.
rem  CBR/CB7/CBT brauchen 7-Zip. Der Rest braucht nichts extra (Poppler fuer PDF optional).
rem ============================================================
set "BATDIR=%~dp0"
set "BATFILE=%~f0"
set "RUNPS=%TEMP%\comics_zu_cbz_run_%RANDOM%%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:BATFILE); $i=$t.IndexOf('#'+'#PS-START',[StringComparison]::Ordinal); [IO.File]::WriteAllText($env:RUNPS,$t.Substring($i),[Text.Encoding]::UTF8)"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RUNPS%" %*
del "%RUNPS%" >nul 2>&1
echo.
pause
exit /b
##PS-START
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

$script:ok = 0; $script:skip = 0; $script:fail = 0; $script:skippedImg = 0
$imageExt = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')
# Bildformate, die KOReader nicht anzeigt: werden nicht umgewandelt, aber gezaehlt und gemeldet
$skipImageExt = @('.avif', '.heic', '.heif', '.jxl', '.jp2', '.j2k', '.jpx', '.jpf', '.tif', '.tiff')
$PdfHeight = 1680    # PDF-Seiten werden auf diese Hoehe (Pixel) gerendert, nie hochgerechnet (Kobo Libra Colour: 1680)
$JpgQuality = 90

# Zahlen als Zahlen vergleichen, auch mit Nachkommastellen (2 < 2.5 < 10):
# ganzzahliger Teil auf 12 Stellen, Nachkommateil auf 6 Stellen aufgefuellt (wie im Plugin)
function Get-NaturalKey([string]$s) {
    return [regex]::Replace($s.ToLowerInvariant(), '(\d+)(?:\.(\d+))?', [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $frac = $m.Groups[2].Value
        if ($frac.Length -gt 6) { $frac = $frac.Substring(0, 6) }
        return $m.Groups[1].Value.PadLeft(12, '0') + $frac.PadRight(6, '0')
    })
}
# macOS-Reste: Ordner __MACOSX und AppleDouble-Dateien ._name
function Test-Junk([string]$path) {
    $p = $path.Replace('\', '/')
    return ($p.Contains('__MACOSX') -or $p.Substring($p.LastIndexOf('/') + 1).StartsWith('._'))
}
# Seitenreihenfolge: Ordner fuer Ordner vergleichen, nicht den ganzen Pfad als Text (sonst kaeme
# "ch.-2.5\" vor "ch.-2\", weil "." vor "\" sortiert). Je Ebene Dateien vor Ordnern, auf oberster Ebene
# ein Bild "cover..." ganz vorn. Ein gemeinsamer Oberordner zaehlt als oberste Ebene.
# $items und $paths (Pfad im Archiv je Eintrag) sind gleich lang; Rueckgabe: $items sortiert.
function Sort-Pages($items, [string[]]$paths) {
    $items = @($items)
    if ($items.Count -lt 2) { return $items }
    $split = @(foreach ($p in $paths) { , ([string[]]$p.Split(@('/', '\'), [StringSplitOptions]::RemoveEmptyEntries)) })
    $common = -1
    foreach ($parts in $split) {
        $nd = $parts.Length - 1
        if ($common -lt 0) { $common = $nd; $first = $parts; continue }
        $n = 0
        while ($n -lt $common -and $n -lt $nd -and $first[$n] -ceq $parts[$n]) { $n++ }
        $common = $n
    }
    $keys = New-Object 'string[]' $items.Count
    for ($k = 0; $k -lt $items.Count; $k++) {
        $parts = $split[$k]
        $ks = New-Object 'System.Collections.Generic.List[string]'
        for ($i = $common; $i -lt $parts.Length; $i++) {
            if ($i -lt $parts.Length - 1) { $kind = '2' }
            elseif ($i -eq $common -and $parts[$i].ToLowerInvariant().StartsWith('cover')) { $kind = '0' }
            else { $kind = '1' }
            $ks.Add($kind + (Get-NaturalKey $parts[$i]))
        }
        # [char]1 trennt die Ebenen, [char]0 haengt die Position an (beide sortieren vor jedem Zeichen)
        $keys[$k] = ($ks -join [char]1) + [char]0 + $k.ToString('D8')
    }
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    foreach ($key in $keys) { $items[[int]$key.Substring($key.Length - 8)] }
}
# Bilder in nicht unterstuetzten Formaten zaehlen und melden
function Write-SkippedImages([string[]]$paths) {
    $hits = @($paths | Where-Object { $skipImageExt -contains [System.IO.Path]::GetExtension($_).ToLower() -and -not (Test-Junk $_) })
    if ($hits.Count -gt 0) {
        $script:skippedImg += $hits.Count
        $exts = (@($hits | ForEach-Object { [System.IO.Path]::GetExtension($_).ToLower() } | Sort-Object -Unique)) -join ', '
        Write-Host "  Hinweis: $($hits.Count) Bild(er) in nicht unterstuetzten Formaten uebersprungen (z. B. $exts)."
    }
}
function Read-EntryText($entry) {
    $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}
function Resolve-ZipPath([string]$baseEntry, [string]$ref) {
    $ref = ($ref -split '[#?]')[0]
    $ref = [System.Uri]::UnescapeDataString($ref)
    $baseDir = ''
    $idx = $baseEntry.LastIndexOf('/')
    if ($idx -ge 0) { $baseDir = $baseEntry.Substring(0, $idx + 1) }
    if ($ref.StartsWith('/')) { $combined = $ref.TrimStart('/') } else { $combined = $baseDir + $ref }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $combined.Split('/')) {
        if ($p -eq '' -or $p -eq '.') { continue }
        if ($p -eq '..') { if ($parts.Count -gt 0) { $parts.RemoveAt($parts.Count - 1) }; continue }
        $parts.Add($p)
    }
    return ($parts -join '/')
}
function New-TempDir {
    $d = Join-Path $env:TEMP ('komic_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $d | Out-Null
    return $d
}
function Write-CbzFromDir([string]$dir, [string]$outPath) {
    [System.IO.Compression.ZipFile]::CreateFromDirectory($dir, $outPath, [System.IO.Compression.CompressionLevel]::NoCompression, $false)
}
function Invoke-Native([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $exe @arguments 2>$null
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    } finally { $ErrorActionPreference = $old }
}
function Find-Tool([string]$exe) {
    $dir = $env:BATDIR
    if ($dir) {
        $local = Join-Path $dir $exe
        if (Test-Path -LiteralPath $local) { return $local }
    }
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($dir) {
        $hit = Get-ChildItem -LiteralPath $dir -Recurse -Depth 5 -File -Filter $exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
function Find-7Zip {
    foreach ($p in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Find-Tool '7z.exe')
}

# ---------- CBR ----------
function Convert-Cbr([string]$cbr, [string]$outPath) {
    $7z = Find-7Zip
    if (-not $7z) { throw '7-Zip nicht gefunden. Bitte installieren: https://www.7-zip.org/' }
    $src = New-TempDir
    $dst = New-TempDir
    try {
        $r = Invoke-Native $7z @('x', '-y', "-o$src", $cbr)
        if ($r.Code -ge 2) { throw "7-Zip Fehler (Code $($r.Code))." }
        $prefix = $src.TrimEnd('\').Length
        $all = @(Get-ChildItem -LiteralPath $src -Recurse -File)
        Write-SkippedImages @($all | ForEach-Object { $_.FullName.Substring($prefix) })
        $imgs = @($all | Where-Object { $imageExt -contains $_.Extension.ToLower() -and -not (Test-Junk $_.FullName.Substring($prefix)) })
        if ($imgs.Count -eq 0) { throw 'Keine Bilder im CBR gefunden.' }
        $sorted = @(Sort-Pages $imgs @($imgs | ForEach-Object { $_.FullName.Substring($prefix) }))
        $w = [Math]::Max(4, ([string]$sorted.Count).Length)
        $i = 0
        foreach ($f in $sorted) {
            $i++
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dst ($i.ToString().PadLeft($w, '0') + $f.Extension.ToLower()))
        }
        Write-CbzFromDir $dst $outPath
        return $sorted.Count
    } finally {
        foreach ($d in @($src, $dst)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
    }
}

# ---------- EPUB ----------
function Convert-Epub([string]$epub, [string]$outPath) {
    $tmp = New-TempDir
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($epub)
        $map = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($e in $zip.Entries) { if ($e.FullName -and -not $e.FullName.EndsWith('/')) { $map[$e.FullName] = $e } }
        Write-SkippedImages @($map.Keys)
        $ordered = New-Object 'System.Collections.Generic.List[string]'
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        try {
            if (-not $map.ContainsKey('META-INF/container.xml')) { throw 'container.xml fehlt' }
            $cdoc = New-Object System.Xml.XmlDocument
            $cdoc.XmlResolver = $null
            $cdoc.LoadXml((Read-EntryText $map['META-INF/container.xml']))
            $opfPath = $cdoc.SelectSingleNode("//*[local-name()='rootfile']").GetAttribute('full-path')
            if (-not $map.ContainsKey($opfPath)) { throw 'OPF fehlt' }
            $odoc = New-Object System.Xml.XmlDocument
            $odoc.XmlResolver = $null
            $odoc.LoadXml((Read-EntryText $map[$opfPath]))
            $manifest = @{}
            foreach ($it in $odoc.SelectNodes("//*[local-name()='item']")) { $manifest[$it.GetAttribute('id')] = $it.GetAttribute('href') }
            foreach ($ir in $odoc.SelectNodes("//*[local-name()='itemref']")) {
                $href = $manifest[$ir.GetAttribute('idref')]
                if (-not $href) { continue }
                $pagePath = Resolve-ZipPath $opfPath $href
                if (-not $map.ContainsKey($pagePath)) { continue }
                $html = Read-EntryText $map[$pagePath]
                $found = New-Object 'System.Collections.Generic.List[object]'
                foreach ($m in [regex]::Matches($html, '(?is)<img\b[^>]*?\bsrc\s*=\s*["'']([^"'']+)["'']')) {
                    $found.Add([pscustomobject]@{ Index = $m.Index; Ref = $m.Groups[1].Value })
                }
                foreach ($m in [regex]::Matches($html, '(?is)<image\b[^>]*?\bhref\s*=\s*["'']([^"'']+)["'']')) {
                    $found.Add([pscustomobject]@{ Index = $m.Index; Ref = $m.Groups[1].Value })
                }
                foreach ($f in @($found | Sort-Object Index)) {
                    $imgPath = Resolve-ZipPath $pagePath $f.Ref
                    $ext = [System.IO.Path]::GetExtension($imgPath).ToLower()
                    if ($imageExt -notcontains $ext) { continue }
                    if (-not $map.ContainsKey($imgPath)) { Write-Host "  Warnung: Bild fehlt im EPUB: $imgPath"; continue }
                    if ($seen.Add($imgPath)) { $ordered.Add($imgPath) }
                }
            }
        } catch {
            Write-Host "  Hinweis: Lesereihenfolge nicht lesbar ($($_.Exception.Message)), nutze Dateinamen."
            $ordered.Clear(); $seen.Clear()
        }
        if ($ordered.Count -eq 0) {
            $all = @($map.Keys | Where-Object { $imageExt -contains [System.IO.Path]::GetExtension($_).ToLower() -and -not (Test-Junk $_) })
            foreach ($n in @(Sort-Pages $all $all)) { $ordered.Add($n) }
            if ($ordered.Count -gt 0) { Write-Host '  Hinweis: Reihenfolge nach Dateinamen sortiert, bitte Ergebnis pruefen.' }
        }
        if ($ordered.Count -eq 0) { throw 'Keine Bilder im EPUB gefunden (evtl. kopiergeschuetzt oder reiner Text).' }
        $w = [Math]::Max(4, ([string]$ordered.Count).Length)
        $i = 0
        foreach ($name in $ordered) {
            $i++
            $ext = [System.IO.Path]::GetExtension($name).ToLower()
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($map[$name], (Join-Path $tmp ($i.ToString().PadLeft($w, '0') + $ext)), $true)
        }
        $zip.Dispose(); $zip = $null
        Write-CbzFromDir $tmp $outPath
        return $ordered.Count
    } finally {
        if ($zip) { $zip.Dispose() }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- MOBI / AZW / AZW3 (Mobipocket und KF8, ohne Kopierschutz) ----------
function Get-BE16([byte[]]$b, [int]$o) { return ([int]$b[$o] * 256) + [int]$b[$o + 1] }
function Get-BE32([byte[]]$b, [int]$o) { return ([long]$b[$o] * 16777216) + ([long]$b[$o + 1] * 65536) + ([long]$b[$o + 2] * 256) + [long]$b[$o + 3] }

function Get-ImageExt([byte[]]$b, [int]$o) {
    if (($o + 4) -gt $b.Length) { return $null }
    if ($b[$o] -eq 0xFF -and $b[$o + 1] -eq 0xD8 -and $b[$o + 2] -eq 0xFF) { return '.jpg' }
    if ($b[$o] -eq 0x89 -and $b[$o + 1] -eq 0x50 -and $b[$o + 2] -eq 0x4E -and $b[$o + 3] -eq 0x47) { return '.png' }
    if ($b[$o] -eq 0x47 -and $b[$o + 1] -eq 0x49 -and $b[$o + 2] -eq 0x46) { return '.gif' }
    if ($b[$o] -eq 0x42 -and $b[$o + 1] -eq 0x4D) { return '.bmp' }
    return $null
}

function Expand-PalmDoc([byte[]]$b) {
    $out = New-Object 'System.Collections.Generic.List[byte]'
    $i = 0
    while ($i -lt $b.Length) {
        $c = [int]$b[$i]; $i++
        if ($c -eq 0 -or ($c -ge 9 -and $c -le 0x7F)) { $out.Add([byte]$c) }
        elseif ($c -ge 1 -and $c -le 8) {
            for ($k = 0; $k -lt $c -and $i -lt $b.Length; $k++) { $out.Add($b[$i]); $i++ }
        }
        elseif ($c -ge 0xC0) { $out.Add([byte]32); $out.Add([byte]($c - 0x80)) }
        else {
            if ($i -ge $b.Length) { break }
            $c = ($c * 256) + [int]$b[$i]; $i++
            $dist = [int]([Math]::Floor($c / 8)) % 2048
            $count = ($c % 8) + 3
            if ($dist -eq 0 -or $dist -gt $out.Count) { break }
            for ($k = 0; $k -lt $count; $k++) { $out.Add($out[$out.Count - $dist]) }
        }
    }
    return , $out.ToArray()
}

function Convert-Base32([string]$s) {
    $v = 0
    foreach ($ch in $s.ToUpper().ToCharArray()) {
        $digit = '0123456789ABCDEFGHIJKLMNOPQRSTUV'.IndexOf($ch)
        $v = ($v * 32) + $digit
    }
    return [int]$v
}

function Convert-Mobi([string]$src, [string]$outPath) {
    $d = [System.IO.File]::ReadAllBytes($src)
    if ($d.Length -lt 80 -or [System.Text.Encoding]::ASCII.GetString($d, 60, 8) -ne 'BOOKMOBI') { throw 'Keine MOBI-Datei.' }
    $n = Get-BE16 $d 76
    $offs = New-Object 'long[]' ($n + 1)
    for ($i = 0; $i -lt $n; $i++) { $offs[$i] = Get-BE32 $d (78 + 8 * $i) }
    $offs[$n] = $d.Length
    $r0 = $offs[0]
    $comp = Get-BE16 $d $r0
    $textrecs = Get-BE16 $d ($r0 + 8)
    $enc = Get-BE16 $d ($r0 + 12)
    if ($enc -ne 0) { throw 'Datei ist kopiergeschuetzt (DRM) und wird nicht unterstuetzt.' }
    if ($comp -ne 1 -and $comp -ne 2) { throw "Kompressionsart $comp wird nicht unterstuetzt." }
    $ms = $r0 + 16
    $kf8 = ((Get-BE32 $d ($ms + 20)) -ge 8)
    for ($i = $textrecs + 1; $i -lt $n; $i++) {
        if (($offs[$i] + 8) -le $d.Length -and [System.Text.Encoding]::ASCII.GetString($d, [int]$offs[$i], 8) -eq 'BOUNDARY') { throw 'MOBI/KF8-Mischformat wird noch nicht unterstuetzt.' }
    }
    $hlen = Get-BE32 $d ($ms + 4)
    # Zusatzdaten am Ende jedes Textblocks: Flags liegen bei Byte 0xF2 des ersten Datensatzes
    $extra = 0
    if (($hlen + 16) -ge 0xF4) { $extra = Get-BE16 $d ($r0 + 0xF2) }

    $all = New-Object 'System.Collections.Generic.List[byte]'
    for ($i = 1; $i -le $textrecs; $i++) {
        $len = [int]($offs[$i + 1] - $offs[$i])
        $end = $len
        for ($bit = 15; $bit -ge 1; $bit--) {
            if ((([int]([Math]::Floor($extra / [Math]::Pow(2, $bit)))) % 2) -eq 1) {
                $v = 0; $shift = 0; $p = $end - 1
                while ($p -ge 0) {
                    $byte = [int]$d[$offs[$i] + $p]
                    $v += ($byte % 128) * [Math]::Pow(2, $shift)
                    $shift += 7
                    if ($byte -ge 128) { break }
                    $p--
                }
                $end -= [int]$v
            }
        }
        if (($extra % 2) -eq 1) { $end -= (([int]$d[$offs[$i] + $end - 1]) % 4) + 1 }
        $rd = New-Object 'byte[]' $end
        [Array]::Copy($d, [int]$offs[$i], $rd, 0, $end)
        if ($comp -eq 1) { $all.AddRange($rd) } else { $all.AddRange([byte[]](Expand-PalmDoc $rd)) }
    }
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($all.ToArray())

    $first = Get-BE32 $d ($ms + 0x6C)
    if ($first -eq 0 -or $first -ge $n -or -not (Get-ImageExt $d ([int]$offs[$first]))) {
        $first = -1
        for ($i = $textrecs + 1; $i -lt $n; $i++) { if (Get-ImageExt $d ([int]$offs[$i])) { $first = $i; break } }
    }
    if ($first -lt 0) { throw 'Keine Bilder in der MOBI-Datei gefunden.' }

    $order = New-Object 'System.Collections.Generic.List[int]'
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    if ($kf8) { $pattern = '(?i)kindle:embed:([0-9A-V]+)' } else { $pattern = '(?is)<img\b[^>]*?recindex="(\d+)"' }
    foreach ($m in [regex]::Matches($text, $pattern)) {
        if ($kf8) { $idx = Convert-Base32 $m.Groups[1].Value } else { $idx = [int]$m.Groups[1].Value }
        $r = $first + $idx - 1
        if ($r -lt $n -and -not $seen.Contains($idx) -and (Get-ImageExt $d ([int]$offs[$r]))) {
            [void]$seen.Add($idx); $order.Add($r)
        }
    }
    if ($order.Count -eq 0) {
        for ($i = $first; $i -lt $n; $i++) { if (Get-ImageExt $d ([int]$offs[$i])) { $order.Add($i) } }
        Write-Host '  Hinweis: Reihenfolge nach Datensaetzen (nicht aus dem Text lesbar), bitte pruefen.'
    }
    $tmp = New-TempDir
    try {
        $w = [Math]::Max(4, ([string]$order.Count).Length)
        $k = 0
        foreach ($r in $order) {
            $k++
            $ext = Get-ImageExt $d ([int]$offs[$r])
            $len = [int]($offs[$r + 1] - $offs[$r])
            $buf = New-Object 'byte[]' $len
            [Array]::Copy($d, [int]$offs[$r], $buf, 0, $len)
            [System.IO.File]::WriteAllBytes((Join-Path $tmp ($k.ToString().PadLeft($w, '0') + $ext)), $buf)
        }
        Write-CbzFromDir $tmp $outPath
        return $order.Count
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- PDF ----------
# Variante A (bevorzugt, verlustfrei): pdfimages.exe aus Poppler, falls neben der BAT vorhanden.
function Convert-PdfExtract([string]$pdfimages, [string]$pdf, [string]$outPath) {
    $pdfinfo = Find-Tool 'pdfinfo.exe'
    $pages = 0
    $pageH = 0
    if ($pdfinfo) {
        $r = Invoke-Native $pdfinfo @($pdf)
        foreach ($line in @($r.Out)) {
            if ($line -match '^Pages:\s+(\d+)') { $pages = [int]$Matches[1] }
            if ($line -match '^Page size:\s+[\d.]+\s+x\s+([\d.]+)') { $pageH = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
        }
    }
    $skipNums = New-Object 'System.Collections.Generic.HashSet[int]'
    $lr = Invoke-Native $pdfimages @('-list', $pdf)
    foreach ($l in @($lr.Out)) { if ($l -match '^\s*\d+\s+(\d+)\s+(smask|mask)\s') { [void]$skipNums.Add([int]$Matches[1]) } }
    # CMYK-JPEGs aus PDFs sind meist invertiert (Decode-Array geht beim Extrahieren verloren) -> lieber rendern
    foreach ($l in @($lr.Out)) { if ($l -match '^\s*\d+\s+\d+\s+image\s+\d+\s+\d+\s+cmyk\s') { return -2 } }
    # Originalbilder nur uebernehmen, wenn jede Seite genau ein ganzseitiges JPG/PNG ist (Comic-Scan).
    # Sonst (Text mit Logo, mehrere Bilder pro Seite, JPEG2000/JBIG2/CCITT) gingen Inhalte verloren -> rendern.
    if ($pdfinfo -and $pages -gt 0) {
        $pageSize = @{}
        $ir = Invoke-Native $pdfinfo @('-f', '1', '-l', [string]$pages, $pdf)
        foreach ($line in @($ir.Out)) {
            if ($line -match '^Page\s+(\d+)\s+size:\s+([\d.]+)\s+x\s+([\d.]+)') {
                $pageSize[[int]$Matches[1]] = @([double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture), [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture))
            }
        }
        $perPage = @{}
        foreach ($l in @($lr.Out)) {
            if ($l -match '^\s*(\d+)\s+\d+\s+image\s+(\d+)\s+(\d+)\s+\S+\s+\d+\s+\d+\s+(\S+)\s+\S+\s+\d+\s+\d+\s+(\d+)\s+(\d+)\s') {
                $pg = [int]$Matches[1]
                if ($Matches[4] -ne 'jpeg' -and $Matches[4] -ne 'image') { return -4 }
                $perPage[$pg] = 1 + [int]$perPage[$pg]
                $sz = $pageSize[$pg]
                if ($sz -and [int]$Matches[5] -gt 0 -and [int]$Matches[6] -gt 0) {
                    $shownW = [int]$Matches[2] * 72.0 / [int]$Matches[5]
                    $shownH = [int]$Matches[3] * 72.0 / [int]$Matches[6]
                    if ($shownW -lt $sz[0] * 0.9 -or $shownH -lt $sz[1] * 0.9) { return -4 }
                }
            }
        }
        for ($pg = 1; $pg -le $pages; $pg++) { if ([int]$perPage[$pg] -ne 1) { return -4 } }
    }
    # Echte Aufloesung der Bilder ermitteln, damit niedrig aufgeloeste PDFs nicht hochgerechnet werden
    $maxPpi = 0
    foreach ($l in @($lr.Out)) { if ($l -match '^\s*\d+\s+\d+\s+image\s+\d+\s+\d+\s+\S+\s+\d+\s+\d+\s+\S+\s+\S+\s+\d+\s+\d+\s+(\d+)\s+\d+\s') { $maxPpi = [Math]::Max($maxPpi, [int]$Matches[1]) } }
    if ($maxPpi -gt 0 -and $pageH -gt 0) {
        $srcH = [int]($pageH * $maxPpi / 72)
        if ($srcH -lt $PdfHeight) { $script:RenderHeight = $srcH }
        if ($srcH -gt ($PdfHeight * 1.1)) { return -3 }   # Quellbilder groesser als noetig -> verkleinert rendern
    }
    $src = New-TempDir
    $dst = New-TempDir
    try {
        $xr = Invoke-Native $pdfimages @('-all', '-p', $pdf, (Join-Path $src 'img'))
        if ($xr.Code -ne 0) { throw 'pdfimages ist fehlgeschlagen (PDF beschaedigt oder passwortgeschuetzt?).' }
        $files = New-Object 'System.Collections.Generic.List[object]'
        foreach ($f in @(Get-ChildItem -LiteralPath $src -File)) {
            if ($f.Name -match '^img-(\d+)-(\d+)\.(\w+)$') {
                $num = [int]$Matches[2]
                if ($skipNums.Contains($num)) { continue }
                $files.Add([pscustomobject]@{ Page = [int]$Matches[1]; Num = $num; Ext = ('.' + $Matches[3].ToLower()); Path = $f.FullName })
            }
        }
        if ($files.Count -eq 0) { return -1 }   # keine Bilder -> Fallback auf Rendern
        $sorted = @($files | Sort-Object Page, Num)
        $w = [Math]::Max(4, ([string]$sorted.Count).Length)
        $i = 0
        foreach ($f in $sorted) {
            $i++
            Move-Item -LiteralPath $f.Path -Destination (Join-Path $dst ($i.ToString().PadLeft($w, '0') + $f.Ext))
        }
        if ($pages -gt 0 -and $pages -ne $sorted.Count) {
            Write-Host "  Warnung: PDF hat $pages Seiten, aber $($sorted.Count) Bilder wurden extrahiert. Bitte Ergebnis pruefen."
        }
        Write-CbzFromDir $dst $outPath
        return $sorted.Count
    } finally {
        foreach ($d in @($src, $dst)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
    }
}

# Variante B (ohne Zusatzprogramm): Seiten mit dem in Windows eingebauten PDF-Renderer als JPG zeichnen.
$script:WinRtReady = $false
function Initialize-WinRt {
    if ($script:WinRtReady) { return }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $methods = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
    $script:AsTaskOp = $methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
    $script:AsTaskAct = $methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
    $script:WinRtReady = $true
}
function Await-Op($op, $type) {
    $t = $script:AsTaskOp.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    $t.Result
}
function Await-Act($act) {
    $t = $script:AsTaskAct.Invoke($null, @($act))
    $t.Wait(-1) | Out-Null
}
# Ohne Poppler: Pixelhoehe der eingebetteten Seitenbilder direkt aus der PDF lesen (Bild-Kopfdaten sind
# nie komprimiert). Zaehlen nur Bilder, deren Seitenverhaeltnis zu einer Seite passt (ganzseitige Scans),
# damit kleine Logos o. ae. die Aufloesung nicht kleinrechnen. 0 = nichts gefunden.
function Get-PdfScanHeight([string]$pdf, $doc) {
    $aspects = New-Object 'System.Collections.Generic.List[double]'
    for ($i = 0; $i -lt [int]$doc.PageCount; $i++) {
        $p = $doc.GetPage($i)
        if ($p.Size.Height -gt 0) { $aspects.Add($p.Size.Width / $p.Size.Height) }
        $p.Dispose()
    }
    $latin = [System.Text.Encoding]::GetEncoding(28591)
    $rx = New-Object System.Text.RegularExpressions.Regex('(?s)<<((?:(?!<<|stream).|<<(?:(?!>>).)*>>){0,2000}?)>>\s*stream')
    $best = 0
    $fs = [System.IO.File]::OpenRead($pdf)
    try {
        $buf = New-Object 'byte[]' 4194304
        $tail = ''
        while (($r = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
            $chunk = $tail + $latin.GetString($buf, 0, $r)
            foreach ($m in $rx.Matches($chunk)) {
                $h = $m.Groups[1].Value
                if ($h -notmatch '/Subtype\s*/Image') { continue }
                $wm = [regex]::Match($h, '/Width\s+(\d+)(?!\s+\d+\s+R)')
                $hm = [regex]::Match($h, '/Height\s+(\d+)(?!\s+\d+\s+R)')
                if (-not $wm.Success -or -not $hm.Success) { continue }
                $iw = [double]$wm.Groups[1].Value; $ih = [int]$hm.Groups[1].Value
                if ($ih -le 0) { continue }
                foreach ($a in $aspects) {
                    if ([Math]::Abs(($iw / $ih) / $a - 1) -lt 0.03) { $best = [Math]::Max($best, $ih); break }
                }
            }
            $tail = if ($chunk.Length -gt 8192) { $chunk.Substring($chunk.Length - 8192) } else { $chunk }
        }
    } finally { $fs.Dispose() }
    return $best
}

function Convert-PdfRender([string]$pdf, [string]$outPath) {
    Initialize-WinRt
    $dst = New-TempDir
    try {
        $file = Await-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($pdf)) ([Windows.Storage.StorageFile])
        $doc = Await-Op ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
        if ($script:RenderHeight -eq $PdfHeight) {
            $scanH = Get-PdfScanHeight $pdf $doc
            if ($scanH -gt 0 -and $scanH -lt $PdfHeight) {
                $script:RenderHeight = $scanH
                Write-Host "  Hinweis: PDF-Bilder sind nur $scanH px hoch, Seiten werden nicht hochgerechnet."
            }
        }
        $jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $enc = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpgQuality)
        $n = [int]$doc.PageCount
        for ($i = 0; $i -lt $n; $i++) {
            Write-Host ("  Seite {0}/{1}" -f ($i + 1), $n)
            $page = $doc.GetPage($i)
            $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
            $opts.DestinationHeight = [uint32]$script:RenderHeight
            $ras = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
            Await-Act ($page.RenderToStreamAsync($ras, $opts))
            $ras.Seek(0)
            $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ras)
            $img = [System.Drawing.Image]::FromStream($stream)
            $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::White)
            $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
            $g.Dispose()
            $bmp.Save((Join-Path $dst ('{0:D5}.jpg' -f ($i + 1))), $jpg, $enc)
            $bmp.Dispose(); $img.Dispose(); $stream.Dispose(); $ras.Dispose(); $page.Dispose()
        }
        if ($n -eq 0) { throw 'PDF hat keine Seiten.' }
        Write-CbzFromDir $dst $outPath
        return $n
    } finally {
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Convert-Pdf([string]$pdf, [string]$outPath) {
    $script:RenderHeight = $PdfHeight
    $pdfimages = Find-Tool 'pdfimages.exe'
    if ($pdfimages) {
        $n = Convert-PdfExtract $pdfimages $pdf $outPath
        if ($n -ge 0) { return $n }
        if ($n -eq -3) { Write-Host "  Hinweis: Bilder im PDF sind gross, Seiten werden auf $PdfHeight px Hoehe verkleinert." }
        elseif ($n -eq -2) { Write-Host '  Hinweis: CMYK-Bilder im PDF (Farben waeren falsch), rendere Seiten stattdessen.' }
        elseif ($n -eq -4) { Write-Host '  Hinweis: Seiten sind keine reinen Bildseiten, rendere Seiten stattdessen.' }
        else { Write-Host '  Keine eingebetteten Bilder, rendere Seiten stattdessen.' }
    } else {
        Write-Host '  Hinweis: Kein pdfimages.exe gefunden, Seiten werden gerendert (JPG).'
    }
    return (Convert-PdfRender $pdf $outPath)
}

# ---------- Ablauf ----------
$supported = @('.cbr', '.rar', '.cb7', '.cbt', '.epub', '.pdf', '.mobi', '.azw', '.azw3')

function Convert-One([string]$file) {
    $out = [System.IO.Path]::ChangeExtension($file, '.cbz')
    if (Test-Path -LiteralPath $out) {
        Write-Host "Uebersprungen, CBZ existiert schon: $out"
        $script:skip++
        return
    }
    Write-Host "Bearbeite: $file"
    try {
        switch ([System.IO.Path]::GetExtension($file).ToLower()) {
            '.epub' { $n = Convert-Epub $file $out }
            '.pdf'  { $n = Convert-Pdf $file $out }
            { $_ -in '.mobi', '.azw', '.azw3' } { $n = Convert-Mobi $file $out }
            default { $n = Convert-Cbr $file $out }
        }
        Write-Host "  Fertig ($n Seiten): $out"
        $script:ok++
    } catch {
        Write-Host "  FEHLER: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
        $script:fail++
    }
}

function Convert-Paths($paths) {
    foreach ($a in $paths) {
        if (Test-Path -LiteralPath $a -PathType Container) {
            $list = @(Get-ChildItem -LiteralPath $a -Recurse -File | Where-Object { $supported -contains $_.Extension.ToLower() -and -not (Test-Junk $_.FullName) })
            foreach ($f in $list) { Convert-One $f.FullName }
        } elseif (Test-Path -LiteralPath $a -PathType Leaf) {
            if ($supported -contains [System.IO.Path]::GetExtension($a).ToLower()) { Convert-One (Resolve-Path -LiteralPath $a).Path }
            else { Write-Host "Uebersprungen (Format nicht unterstuetzt): $a" }
        }
    }
    Write-Host ''
    Write-Host '==== Zusammenfassung ===='
    Write-Host "Umgewandelt:   $script:ok"
    Write-Host "Uebersprungen: $script:skip"
    Write-Host "Fehler:        $script:fail"
    if ($script:skippedImg -gt 0) { Write-Host "Bilder in nicht unterstuetzten Formaten uebersprungen: $script:skippedImg" }
    $script:ok = 0; $script:skip = 0; $script:fail = 0; $script:skippedImg = 0
}

if ($args.Count -gt 0) {
    Convert-Paths $args
    return
}

# Kein Drag-and-Drop auf die BAT: Fenster zum Hineinziehen anzeigen
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Comics zu CBZ'
$form.Size = New-Object System.Drawing.Size(520, 300)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.AllowDrop = $true
$lbl = New-Object System.Windows.Forms.Label
$lbl.Dock = 'Fill'
$lbl.TextAlign = 'MiddleCenter'
$lbl.Font = New-Object System.Drawing.Font('Segoe UI', 14)
$lbl.Text = "CBR / CB7 / CBT / PDF / EPUB / MOBI / AZW`noder ganze Ordner hier hineinziehen"
$lbl.AllowDrop = $true
$form.Controls.Add($lbl)
$enter = { if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } }
$drop = {
    $files = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    $lbl.Text = "Arbeite ... (Details im schwarzen Fenster)"
    $form.Refresh()
    Convert-Paths $files
    $lbl.Text = "Fertig.`nWeitere Dateien hineinziehen oder Fenster schliessen."
}
$form.Add_DragEnter($enter); $lbl.Add_DragEnter($enter)
$form.Add_DragDrop($drop);   $lbl.Add_DragDrop($drop)
[void]$form.ShowDialog()
