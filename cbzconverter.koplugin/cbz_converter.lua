-- Kern-Logik: CBR / EPUB / PDF -> CBZ
local Archiver = require("ffi/archiver")
local lfs = require("libs/libkoreader-lfs")
local T = require("cbz_i18n")
local unpack = table.unpack or unpack

local Converter = {}

-- Wird per error() geworfen, wenn der Fortschritts-Callback false liefert (Abbruch durch den Nutzer)
local CANCEL = {}

local function tick(progress, current, total)
    if progress and progress(current, total) == false then error(CANCEL, 0) end
end

-- Gerenderte PDF-Seiten: Hoehe in Pixel und JPG-Qualitaet.
-- Gemessen wird die HOEHE (Kobo Libra Colour: Bildschirm 1264 x 1680), damit Einzel- und Doppelseiten
-- gleich scharf werden. Bei Speicherproblemen oder zu grossen Dateien hier kleinere Werte eintragen.
Converter.PDF_HEIGHT = 1680
Converter.PDF_QUALITY = 90

local IMG_EXT = { jpg = true, jpeg = true, png = true, gif = true, webp = true, bmp = true }
-- Bildformate, die KOReader nicht anzeigt: werden nicht umgewandelt, aber gezaehlt und am Ende gemeldet
local SKIP_IMG_EXT = { avif = true, heic = true, heif = true, jxl = true, jp2 = true, j2k = true, jpx = true, jpf = true, tif = true, tiff = true }
local TEXT_EXT = { xml = true, xhtml = true, html = true, htm = true, opf = true }
Converter.SUPPORTED = { cbr = true, rar = true, cb7 = true, cbt = true, epub = true, pdf = true, mobi = true, azw = true, azw3 = true }

local function ext_of(path)
    return (path:match("%.([^./]+)$") or ""):lower()
end

-- macOS-Reste: Ordner __MACOSX und AppleDouble-Dateien "._name"
local function is_junk(path)
    return path:find("__MACOSX", 1, true) ~= nil or (path:match("([^/]+)$") or ""):sub(1, 2) == "._"
end

-- Zahlen werden als Zahlen verglichen, auch mit Nachkommastellen (2 < 2.5 < 10):
-- ganzzahliger Teil auf 12 Stellen, Nachkommateil auf 6 Stellen aufgefuellt.
-- Ein Punkt ohne Ziffern dahinter (z. B. "001.jpg") gehoert nicht zur Zahl.
function Converter.natural_key(s)
    return (s:lower():gsub("(%d+)(%.?)(%d*)", function(int, dot, frac)
        local key = string.rep("0", 12 - #int) .. int
        if dot == "" or frac == "" then
            return key .. "000000" .. dot .. frac
        end
        frac = frac:sub(1, 6)
        return key .. frac .. string.rep("0", 6 - #frac)
    end))
end

local function split_path(path)
    local parts = {}
    for p in path:gmatch("[^/\\]+") do parts[#parts + 1] = p end
    return parts
end

-- Sortierschluessel fuer einen Pfad im Archiv. Verglichen wird Ordner fuer Ordner, nicht der ganze
-- Pfad als Text (sonst kaeme "ch.-2.5/" vor "ch.-2/", weil "." vor "/" sortiert).
-- Je Ebene: Dateien vor Ordnern. Auf oberster Ebene kommt ein Bild "cover…" ganz nach vorn.
-- skip = Anzahl gemeinsamer Oberordner, die nicht als Ebene zaehlen.
local function page_key(path, skip)
    local parts = split_path(path)
    local keys = {}
    for i = skip + 1, #parts do
        local p = parts[i]
        local kind
        if i < #parts then
            kind = "2"
        elseif i == skip + 1 and p:lower():sub(1, 5) == "cover" then
            kind = "0"
        else
            kind = "1"
        end
        keys[#keys + 1] = kind .. Converter.natural_key(p)
    end
    -- "\1" trennt die Ebenen und sortiert vor jedem Zeichen
    return table.concat(keys, "\1")
end

-- Sortiert eine Liste in Seitenreihenfolge. get_path liefert zu jedem Eintrag den Pfad im Archiv.
-- Ein gemeinsamer Oberordner (z. B. "Comic/" um alles herum) zaehlt dabei als oberste Ebene.
function Converter.sort_pages(items, get_path)
    get_path = get_path or function(x) return x end
    local common
    for _, it in ipairs(items) do
        local parts = split_path(get_path(it))
        parts[#parts] = nil
        if not common then
            common = parts
        else
            local n = 0
            while n < #common and n < #parts and common[n + 1] == parts[n + 1] do n = n + 1 end
            for k = #common, n + 1, -1 do common[k] = nil end
        end
    end
    local skip = common and #common or 0
    local keys = {}
    for _, it in ipairs(items) do keys[it] = page_key(get_path(it), skip) end
    table.sort(items, function(a, b) return keys[a] < keys[b] end)
    return items
end

-- Zaehlt Bilder in nicht unterstuetzten Formaten. Liefert Anzahl und Endungen (z. B. ".avif, .heic").
local function skipped_images(paths)
    local n, seen, exts = 0, {}, {}
    for _, p in ipairs(paths) do
        local ext = ext_of(p)
        if SKIP_IMG_EXT[ext] and not is_junk(p) then
            n = n + 1
            if not seen[ext] then
                seen[ext] = true
                exts[#exts + 1] = "." .. ext
            end
        end
    end
    table.sort(exts)
    return n, table.concat(exts, ", ")
end
Converter.skipped_images = skipped_images

local function skipped_note(n, exts)
    if n > 0 then return T("note_skipped", n, exts) end
end

-- Zwei Hinweise zu einem zusammenfassen (beide duerfen fehlen)
local function join_notes(a, b)
    if a and b then return a .. "; " .. b end
    return a or b
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function make_tmp(out)
    local dir = out .. ".tmp"
    lfs.mkdir(dir)
    return dir
end

local function remove_dir(dir)
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then os.remove(dir .. "/" .. name) end
    end
    lfs.rmdir(dir)
end

-- files: Liste von { file = <Pfad>, ext = "jpg" } in Seitenreihenfolge
local function pack(files, out, progress)
    if #files == 0 then return nil, T("err_no_images") end
    local width = math.max(4, #tostring(#files))
    local part = out .. ".part"
    local writer = Archiver.Writer:new()
    if not writer:open(part, "zip") then
        return nil, T("err_cbz_create") .. tostring(writer.err)
    end
    writer:setZipCompression("store")
    for i, item in ipairs(files) do
        local ok_tick, tick_err = pcall(tick, progress, i, #files)
        if not ok_tick then
            writer:close()
            os.remove(part)
            error(tick_err, 0)
        end
        local data = read_file(item.file)
        if not data or not writer:addFileFromMemory(string.format("%0" .. width .. "d.%s", i, item.ext), data) then
            writer:close()
            os.remove(part)
            return nil, T("err_write") .. tostring(writer.err)
        end
    end
    writer:close()
    os.remove(out)
    os.rename(part, out)
    return #files
end

-- ---------- CBR / RAR ----------
local function convert_cbr(src, out, progress)
    local reader = Archiver.Reader:new()
    if not reader:open(src) then
        return nil, T("err_archive") .. tostring(reader.err)
    end
    local tmp = make_tmp(out)
    local list, n, all = {}, 0, {}
    for entry in reader:iterate() do
        if entry.mode == "file" then all[#all + 1] = entry.path end
        if entry.mode == "file" and IMG_EXT[ext_of(entry.path)] and not is_junk(entry.path) then
            local data = reader:extractToMemory(entry.path)
            if data and #data > 0 then
                n = n + 1
                local ext = ext_of(entry.path)
                local file = string.format("%s/%06d.%s", tmp, n, ext)
                write_file(file, data)
                list[#list + 1] = { path = entry.path, file = file, ext = ext }
                tick(progress, n)
            end
        end
    end
    reader:close()
    Converter.sort_pages(list, function(item) return item.path end)
    local note = skipped_note(skipped_images(all))
    local count, err = pack(list, out, progress)
    remove_dir(tmp)
    if not count and note then err = err .. " (" .. note .. ")" end
    return count, err, count and note or nil
end

-- ---------- EPUB ----------
local function attr(tag, name)
    -- Attributnamen unabhängig von Groß-/Kleinschreibung suchen
    local pat = name:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
    return tag:match("%f[%w]" .. pat .. '%s*=%s*"([^"]*)"') or tag:match("%f[%w]" .. pat .. "%s*=%s*'([^']*)'")
end

local function url_decode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function Converter.resolve(base_file, ref)
    ref = url_decode(ref:gsub("[#?].*$", ""))
    local dir = base_file:match("^(.*)/[^/]*$") or ""
    local combined = ref:sub(1, 1) == "/" and ref or (dir ~= "" and (dir .. "/" .. ref) or ref)
    local parts = {}
    for p in combined:gmatch("[^/]+") do
        if p == ".." then
            parts[#parts] = nil
        elseif p ~= "." then
            parts[#parts + 1] = p
        end
    end
    return table.concat(parts, "/")
end

local function find_tags(html, pat)
    local res, pos = {}, 1
    while true do
        local s, e = html:find(pat, pos)
        if not s then break end
        res[#res + 1] = { s = s, tag = html:sub(s, e) }
        pos = e + 1
    end
    return res
end

-- Liefert die Bildpfade (wie im Archiv, Originalschreibweise) in Lesereihenfolge
function Converter.epub_image_order(texts, images)
    local ordered, seen = {}, {}
    local container = texts["meta-inf/container.xml"]
    local opf_path = container and container:match('full%-path%s*=%s*"([^"]+)"')
    local opf = opf_path and texts[opf_path:lower()]
    if not opf then return ordered end
    local manifest = {}
    for _, t in ipairs(find_tags(opf, "<[%w:]*item%s[^>]*>")) do
        local id, href = attr(t.tag, "id"), attr(t.tag, "href")
        if id and href then manifest[id] = href end
    end
    for _, t in ipairs(find_tags(opf, "<[%w:]*itemref%s[^>]*>")) do
        local href = manifest[attr(t.tag, "idref") or ""]
        if href then
            local page = Converter.resolve(opf_path, href)
            local html = texts[page:lower()]
            if html then
                local found = find_tags(html, "<[iI][mM][gG]%s[^>]*>")
                for _, t2 in ipairs(find_tags(html, "<[iI][mM][aA][gG][eE]%s[^>]*>")) do
                    found[#found + 1] = t2
                end
                table.sort(found, function(a, b) return a.s < b.s end)
                for _, f in ipairs(found) do
                    local ref = attr(f.tag, "src") or attr(f.tag, "href")
                    if ref then
                        local img = images[Converter.resolve(page, ref):lower()]
                        if img and not seen[img] then
                            seen[img] = true
                            ordered[#ordered + 1] = img
                        end
                    end
                end
            end
        end
    end
    return ordered
end

local function convert_epub(src, out, progress)
    local reader = Archiver.Reader:new()
    if not reader:open(src) then
        return nil, T("err_epub") .. tostring(reader.err)
    end
    local texts, images, all = {}, {}, {}
    for entry in reader:iterate() do
        if entry.mode == "file" then all[#all + 1] = entry.path end
        if entry.mode == "file" and not is_junk(entry.path) then
            local ext = ext_of(entry.path)
            if IMG_EXT[ext] then
                images[entry.path:lower()] = entry.path
            elseif TEXT_EXT[ext] and entry.size < 5 * 1024 * 1024 then
                local data = reader:extractToMemory(entry.path)
                if data then texts[entry.path:lower()] = data end
            end
        end
    end
    local ordered = Converter.epub_image_order(texts, images)
    local note
    if #ordered == 0 then
        for _, p in pairs(images) do ordered[#ordered + 1] = p end
        Converter.sort_pages(ordered)
        note = T("note_order")
    end
    local skip_note = skipped_note(skipped_images(all))
    if #ordered == 0 then
        reader:close()
        local err = T("err_epub_no_images")
        if skip_note then err = err .. " (" .. skip_note .. ")" end
        return nil, err
    end
    note = join_notes(note, skip_note)
    local position = {}
    for i, p in ipairs(ordered) do position[p] = i end
    local tmp = make_tmp(out)
    local list, extracted = {}, 0
    for entry in reader:iterate() do
        local pos = position[entry.path]
        if pos and entry.mode == "file" then
            local data = reader:extractToMemory(entry.path)
            if data and #data > 0 then
                local ext = ext_of(entry.path)
                local file = string.format("%s/%06d.%s", tmp, pos, ext)
                write_file(file, data)
                list[pos] = { file = file, ext = ext }
                extracted = extracted + 1
                tick(progress, extracted, #ordered)
            end
        end
    end
    reader:close()
    local compact = {}
    for i = 1, #ordered do
        if list[i] then compact[#compact + 1] = list[i] end
    end
    local count, err = pack(compact, out, progress)
    remove_dir(tmp)
    return count, err, note
end

-- ---------- MOBI / AZW / AZW3 (Mobipocket und KF8, ohne Kopierschutz) ----------
local function be16(s, o) local a, b = s:byte(o + 1, o + 2) return a * 256 + b end
local function be32(s, o) local a, b, c, d = s:byte(o + 1, o + 4) return ((a * 256 + b) * 256 + c) * 256 + d end

local function image_ext(s)
    local a, b, c, d = s:byte(1, 4)
    if a == 0xFF and b == 0xD8 and c == 0xFF then return "jpg" end
    if a == 0x89 and b == 0x50 and c == 0x4E and d == 0x47 then return "png" end
    if a == 0x47 and b == 0x49 and c == 0x46 then return "gif" end
    if a == 0x42 and b == 0x4D then return "bmp" end
end

local function palmdoc(s)
    local out, n, i, len = {}, 0, 1, #s
    while i <= len do
        local c = s:byte(i)
        i = i + 1
        if c == 0 or (c >= 9 and c <= 0x7F) then
            n = n + 1; out[n] = c
        elseif c >= 1 and c <= 8 then
            for k = 0, c - 1 do
                local b = s:byte(i + k)
                if not b then break end
                n = n + 1; out[n] = b
            end
            i = i + c
        elseif c >= 0xC0 then
            n = n + 1; out[n] = 32
            n = n + 1; out[n] = c - 0x80
        else
            if i > len then break end
            c = c * 256 + s:byte(i)
            i = i + 1
            local dist = math.floor(c / 8) % 2048
            local count = c % 8 + 3
            if dist == 0 or dist > n then break end
            for _ = 1, count do
                n = n + 1; out[n] = out[n - dist]
            end
        end
    end
    local parts = {}
    for k = 1, n, 4096 do
        parts[#parts + 1] = string.char(unpack(out, k, math.min(k + 4095, n)))
    end
    return table.concat(parts)
end

local function convert_mobi(src, out, progress)
    local f = io.open(src, "rb")
    if not f then return nil, T("err_mobi") end
    local ok, a, b, c = pcall(function()
        local head = f:read(78)
        if not head or head:sub(61, 68) ~= "BOOKMOBI" then return nil, T("err_mobi") end
        local n = be16(head, 76)
        local table_data = f:read(8 * n)
        local offs = {}
        for i = 0, n - 1 do offs[i] = be32(table_data, 8 * i) end
        local size = f:seek("end")
        offs[n] = size
        local function rec(i, max)
            f:seek("set", offs[i])
            return f:read(max and math.min(max, offs[i + 1] - offs[i]) or (offs[i + 1] - offs[i])) or ""
        end
        local r0 = rec(0)
        local comp, textrecs, enc = be16(r0, 0), be16(r0, 8), be16(r0, 12)
        if enc ~= 0 then return nil, T("err_mobi_drm") end
        if comp ~= 1 and comp ~= 2 then return nil, T("err_mobi") end
        local mobi = r0:sub(17)
        local kf8 = be32(mobi, 20) >= 8
        for i = textrecs + 1, n - 1 do
            if rec(i, 8) == "BOUNDARY" then return nil, T("err_mobi_kf8") end
        end
        local hlen = be32(mobi, 4)
        -- Zusatzdaten am Ende jedes Textblocks: Flags liegen bei Byte 0xF2 des ersten Datensatzes
        local extra = (16 + hlen >= 0xF4) and be16(r0, 0xF2) or 0
        local function strip(rd)
            local e = #rd
            for bit = 15, 1, -1 do
                if math.floor(extra / 2 ^ bit) % 2 == 1 then
                    local v, shift, p = 0, 0, e
                    while p >= 1 do
                        local byte = rd:byte(p)
                        v = v + (byte % 128) * 2 ^ shift
                        shift = shift + 7
                        if byte >= 128 then break end
                        p = p - 1
                    end
                    e = e - v
                end
            end
            if extra % 2 == 1 then e = e - (rd:byte(e) % 4 + 1) end
            return rd:sub(1, e)
        end
        local parts = {}
        for i = 1, textrecs do
            local rd = rec(i)
            parts[#parts + 1] = comp == 1 and rd or palmdoc(strip(rd))
        end
        local text = table.concat(parts)
        local first = be32(mobi, 0x6C)
        if first == 0 or first >= n or not image_ext(rec(first, 8)) then
            first = nil
            for i = textrecs + 1, n - 1 do
                if image_ext(rec(i, 8)) then first = i; break end
            end
        end
        if not first then return nil, T("err_mobi_no_images") end
        local order, seen = {}, {}
        local pattern = kf8 and "kindle:embed:([0-9A-Va-v]+)" or '<[iI][mM][gG][^>]-recindex="(%d+)"'
        for idx in text:gmatch(pattern) do
            local k = tonumber(idx, kf8 and 32 or 10)
            local r = first + k - 1
            if not seen[k] and r < n and image_ext(rec(r, 8)) then
                seen[k] = true
                order[#order + 1] = r
            end
        end
        local note
        if #order == 0 then
            for i = first, n - 1 do
                if image_ext(rec(i, 8)) then order[#order + 1] = i end
            end
            note = T("note_order")
        end
        local tmp = make_tmp(out)
        local list = {}
        for k, r in ipairs(order) do
            local data = rec(r)
            local ext = image_ext(data)
            local file = string.format("%s/%06d.%s", tmp, k, ext)
            write_file(file, data)
            list[#list + 1] = { file = file, ext = ext }
            tick(progress, k, #order)
        end
        local count, err = pack(list, out, progress)
        remove_dir(tmp)
        return count, err, note
    end)
    f:close()
    if not ok then error(a, 0) end
    return a, b, c
end

-- ---------- PDF (Seiten rendern) ----------

-- Zahl hinter /Key im Bild-Kopf, aber nicht bei indirekten Verweisen wie "/Height 12 0 R"
local function dict_number(dict, key)
    local s, e, n = dict:find("/" .. key .. "%s+(%d+)")
    if not s then return nil end
    if dict:sub(e + 1, e + 16):match("^%s+%d+%s+R") then return nil end
    return tonumber(n)
end

-- Pixelhoehe der eingebetteten Seitenbilder direkt aus der PDF-Datei lesen (Bild-Kopfdaten sind
-- nie komprimiert). Zaehlen nur Bilder, deren Seitenverhaeltnis zu einer Seite passt (ganzseitige
-- Scans), damit kleine Logos die Aufloesung nicht kleinrechnen. 0 = nichts gefunden.
-- Die Datei wird stueckweise gelesen, damit auch grosse PDFs den Speicher nicht fuellen.
local function pdf_scan_height(path, aspects)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local best = 0
    local tail = ""
    while true do
        local block = f:read(4 * 1024 * 1024)
        if not block then break end
        local chunk = tail .. block
        local pos = 1
        while true do
            local s, e = chunk:find("/Subtype%s*/Image", pos)
            if not s then break end
            -- Kopf des Bild-Objekts: vom letzten "obj" davor bis zum naechsten "stream" danach
            local from = math.max(1, s - 2000)
            local obj_start = from
            local p = from
            while true do
                local os_, oe = chunk:find("%d+%s+%d+%s+obj", p)
                if not os_ or os_ > s then break end
                obj_start = os_
                p = oe + 1
            end
            local stream_pos = chunk:find("stream", e, true)
            if stream_pos and stream_pos - e < 2000 then
                local dict = chunk:sub(obj_start, stream_pos)
                local w, h = dict_number(dict, "Width"), dict_number(dict, "Height")
                if w and h and h > 0 then
                    for _, a in ipairs(aspects) do
                        if math.abs((w / h) / a - 1) < 0.03 then
                            if h > best then best = h end
                            break
                        end
                    end
                end
            end
            pos = e + 1
        end
        tail = #chunk > 8192 and chunk:sub(-8192) or chunk
    end
    f:close()
    return best
end

local function convert_pdf(src, out, progress)
    local DocumentRegistry = require("document/documentregistry")
    local Geom = require("ui/geometry")
    local doc = DocumentRegistry:openDocument(src)
    if not doc then return nil, T("err_pdf") end
    if doc.updateColorRendering then doc:updateColorRendering() end
    local tmp = make_tmp(out)
    local list = {}
    local pages = doc:getPageCount()
    -- Nie hochrechnen: Sind die Seitenbilder kleiner als PDF_HEIGHT, wird auf ihre echte Hoehe gerendert
    local target_h = Converter.PDF_HEIGHT
    local note
    local aspects = {}
    for i = 1, pages do
        local d = doc:getPageDimensions(i, 1, 0)
        if d and d.h and d.h > 0 then aspects[#aspects + 1] = d.w / d.h end
    end
    local ok_scan, scan_h = pcall(pdf_scan_height, src, aspects)
    if ok_scan and scan_h and scan_h > 0 and scan_h < target_h then
        target_h = scan_h
        note = T("note_pdf_native", scan_h)
    end
    local ok, err = pcall(function()
        for i = 1, pages do
            tick(progress, i, pages)
            local dim = doc:getPageDimensions(i, 1, 0)
            local zoom = target_h / dim.h
            local rect = Geom:new{ x = 0, y = 0, w = math.floor(dim.w * zoom + 0.5), h = math.floor(dim.h * zoom + 0.5) }
            local tile = doc:renderPage(i, rect, zoom, 0, 1.0, 1.0, false)
            if tile and tile.bb then
                local file = string.format("%s/%06d.jpg", tmp, i)
                local ext = "jpg"
                if not pcall(tile.bb.writeJPG, tile.bb, file, Converter.PDF_QUALITY) then
                    file = string.format("%s/%06d.png", tmp, i)
                    ext = "png"
                    tile.bb:writePNG(file)
                end
                list[#list + 1] = { file = file, ext = ext }
            end
            collectgarbage()
        end
    end)
    doc:close()
    if not ok then
        remove_dir(tmp)
        if err == CANCEL then error(CANCEL, 0) end
        return nil, T("err_render") .. tostring(err)
    end
    local count, perr = pack(list, out, progress)
    remove_dir(tmp)
    return count, perr, count and note or nil
end

-- ---------- Einstieg ----------
-- Gibt Anzahl Seiten zurück, oder nil + Fehlertext. Dritter Rückgabewert: optionaler Hinweis.
function Converter.convert(src, progress)
    local out = src:gsub("%.[^./]+$", "") .. ".cbz"
    if lfs.attributes(out, "mode") then
        return nil, T("skip"), "skip"
    end
    local ext = ext_of(src)
    local ok, a, b, c
    if ext == "epub" then
        ok, a, b, c = pcall(convert_epub, src, out, progress)
    elseif ext == "pdf" then
        ok, a, b, c = pcall(convert_pdf, src, out, progress)
    elseif ext == "mobi" or ext == "azw" or ext == "azw3" then
        ok, a, b, c = pcall(convert_mobi, src, out, progress)
    else
        ok, a, b, c = pcall(convert_cbr, src, out, progress)
    end
    if not ok then
        os.remove(out .. ".part")
        remove_dir(out .. ".tmp")
        if a == CANCEL then return nil, T("cancelled"), "cancel" end
        return nil, tostring(a)
    end
    return a, b, c, out
end

return Converter
