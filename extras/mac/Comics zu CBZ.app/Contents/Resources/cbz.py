#!/usr/bin/env python3
"""CBR / PDF / EPUB -> CBZ (Bilder bleiben unveraendert, ausser beim PDF-Rendern)."""
import os, re, shutil, struct, subprocess, sys, tempfile, time, zipfile, posixpath, urllib.parse
from xml.dom import minidom

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}
SUPPORTED = {'.cbr', '.rar', '.cb7', '.cbt', '.epub', '.pdf', '.mobi', '.azw', '.azw3'}
# PDFs: Seiten werden auf diese Hoehe in Pixel gerendert (Kobo Libra Colour: 1680). Gemessen wird die HOEHE,
# damit Einzel- und Doppelseiten gleich hoch (und gleich scharf) werden. Nie hochgerechnet.
PDF_HEIGHT = 1680
JPG_QUALITY = 90
ENV = dict(os.environ, PATH=os.environ.get('PATH', '') + ':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin')

# Bildformate, die KOReader nicht anzeigt: werden nicht umgewandelt, aber gezaehlt und gemeldet
SKIP_IMG = {'.avif', '.heic', '.heif', '.jxl', '.jp2', '.j2k', '.jpx', '.jpf', '.tif', '.tiff'}
skipped_total = 0

def nat(s):
    """Zahlen als Zahlen vergleichen, auch mit Nachkommastellen (2 < 2.5 < 10):
    ganzzahliger Teil auf 12 Stellen, Nachkommateil auf 6 Stellen aufgefuellt (wie im Plugin)."""
    return re.sub(r'(\d+)(?:\.(\d+))?',
                  lambda m: m.group(1).zfill(12) + (m.group(2) or '')[:6].ljust(6, '0'), s.lower())

def is_junk(path):
    """macOS-Reste: Ordner __MACOSX und AppleDouble-Dateien ._name"""
    return '__MACOSX' in path or os.path.basename(path.replace('\\', '/')).startswith('._')

def _parts(path):
    return [p for p in re.split(r'[/\\]', path) if p]

def sort_pages(items, rel=lambda x: x):
    """Seitenreihenfolge: Ordner fuer Ordner vergleichen, nicht den ganzen Pfad als Text
    (sonst kaeme "ch.-2.5/" vor "ch.-2/", weil "." vor "/" sortiert). Je Ebene Dateien vor Ordnern,
    auf oberster Ebene ein Bild "cover..." ganz vorn. Ein gemeinsamer Oberordner zaehlt als oberste Ebene."""
    common = None
    for it in items:
        dirs = _parts(rel(it))[:-1]
        if common is None:
            common = dirs
        else:
            n = 0
            while n < len(common) and n < len(dirs) and common[n] == dirs[n]: n += 1
            common = common[:n]
    skip = len(common or [])
    def key(it):
        parts = _parts(rel(it))
        keys = []
        for i in range(skip, len(parts)):
            p = parts[i]
            if i < len(parts) - 1: kind = '2'
            elif i == skip and p.lower().startswith('cover'): kind = '0'
            else: kind = '1'
            keys.append(kind + nat(p))
        return '\x01'.join(keys)
    return sorted(items, key=key)

def report_skipped(paths):
    """Bilder in nicht unterstuetzten Formaten zaehlen und melden."""
    global skipped_total
    hits = [p for p in paths if os.path.splitext(p)[1].lower() in SKIP_IMG and not is_junk(p)]
    if hits:
        skipped_total += len(hits)
        exts = ', '.join(sorted({os.path.splitext(p)[1].lower() for p in hits}))
        print('  Hinweis: %d Bild(er) in nicht unterstuetzten Formaten uebersprungen (z. B. %s).' % (len(hits), exts))

def which(*names):
    for n in names:
        p = shutil.which(n, path=ENV['PATH'])
        if p: return p

def pack(files, out):
    """files: Liste von (Quellpfad, Endung) in Seitenreihenfolge."""
    if not files: raise RuntimeError('Keine Bilder gefunden.')
    w = max(4, len(str(len(files))))
    tmp = out + '.part'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_STORED) as z:
        for i, (src, ext) in enumerate(files, 1):
            # Zeitstempel vor 1980 (z. B. 1970 in TAR-Archiven) kann ZIP nicht speichern
            mtime = max(os.path.getmtime(src), 315619200)
            info = zipfile.ZipInfo(str(i).zfill(w) + ext, date_time=time.localtime(mtime)[:6])
            info.compress_type = zipfile.ZIP_STORED
            with open(src, 'rb') as fh: z.writestr(info, fh.read())
    os.replace(tmp, out)
    return len(files)

def walk_files(d):
    """Alle Dateien unter d als Pfade relativ zu d."""
    return [os.path.relpath(os.path.join(root, f), d) for root, _, fs in os.walk(d) for f in fs]

def walk_images(d):
    res = [p for p in walk_files(d) if os.path.splitext(p)[1].lower() in IMG and not is_junk(p)]
    res = sort_pages(res)
    return [(os.path.join(d, p), os.path.splitext(p)[1].lower()) for p in res]

def run(cmd):
    return subprocess.run(cmd, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# ---------- CBR ----------
def conv_cbr(src, out):
    tmp = tempfile.mkdtemp(prefix='cbz_')
    try:
        tools = [
            ([which('7zz', '7z', '7za')], lambda t: [t[0], 'x', '-y', '-o' + tmp, src]),
            ([which('unar')], lambda t: [t[0], '-q', '-f', '-o', tmp, src]),
            ([which('unrar')], lambda t: [t[0], 'x', '-o+', '-idq', src, tmp + '/']),
            ([which('bsdtar')], lambda t: [t[0], '-xf', src, '-C', tmp]),
        ]
        ok = False
        for t, cmd in tools:
            if not t[0]: continue
            r = run(cmd(t))
            if walk_images(tmp) or any(os.path.splitext(p)[1].lower() in SKIP_IMG for p in walk_files(tmp)):
                ok = True; break
            shutil.rmtree(tmp); os.makedirs(tmp)
        if not ok:
            raise RuntimeError('Entpacken fehlgeschlagen. Bitte "brew install sevenzip" (oder unar) installieren.')
        report_skipped(walk_files(tmp))
        return pack(walk_images(tmp), out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# ---------- EPUB ----------
def conv_epub(src, out):
    tmp = tempfile.mkdtemp(prefix='cbz_')
    try:
        with zipfile.ZipFile(src) as z:
            names = {n.lower(): n for n in z.namelist() if not n.endswith('/')}
            report_skipped(list(names.values()))
            ordered, seen = [], set()
            try:
                cont = minidom.parseString(z.read(names['meta-inf/container.xml']))
                opf = cont.getElementsByTagNameNS('*', 'rootfile')[0].getAttribute('full-path')
                doc = minidom.parseString(z.read(names[opf.lower()]))
                manifest = {i.getAttribute('id'): i.getAttribute('href') for i in doc.getElementsByTagNameNS('*', 'item')}
                for ir in doc.getElementsByTagNameNS('*', 'itemref'):
                    href = manifest.get(ir.getAttribute('idref'))
                    if not href: continue
                    page = posixpath.normpath(posixpath.join(posixpath.dirname(opf), urllib.parse.unquote(href.split('#')[0])))
                    if page.lower() not in names: continue
                    html = z.read(names[page.lower()]).decode('utf-8', 'ignore')
                    hits = [(m.start(), m.group(1)) for m in re.finditer(r'(?is)<img\b[^>]*?\bsrc\s*=\s*["\']([^"\']+)["\']', html)]
                    hits += [(m.start(), m.group(1)) for m in re.finditer(r'(?is)<image\b[^>]*?\bhref\s*=\s*["\']([^"\']+)["\']', html)]
                    for _, ref in sorted(hits):
                        p = posixpath.normpath(posixpath.join(posixpath.dirname(page), urllib.parse.unquote(ref.split('#')[0].split('?')[0])))
                        if os.path.splitext(p)[1].lower() in IMG and p.lower() in names and p.lower() not in seen:
                            seen.add(p.lower()); ordered.append(names[p.lower()])
            except Exception as e:
                print('  Hinweis: Lesereihenfolge nicht lesbar (%s), nutze Dateinamen.' % e)
                ordered = []
            if not ordered:
                ordered = sort_pages([n for n in z.namelist() if os.path.splitext(n)[1].lower() in IMG and not is_junk(n)])
                if ordered: print('  Hinweis: nach Dateinamen sortiert, bitte Ergebnis pruefen.')
            if not ordered: raise RuntimeError('Keine Bilder im EPUB (evtl. DRM oder reiner Text).')
            files = []
            for i, n in enumerate(ordered):
                ext = os.path.splitext(n)[1].lower()
                p = os.path.join(tmp, '%06d%s' % (i, ext))
                with z.open(n) as a, open(p, 'wb') as b: shutil.copyfileobj(a, b)
                files.append((p, ext))
        return pack(files, out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# ---------- MOBI / AZW / AZW3 (Mobipocket und KF8, ohne Kopierschutz) ----------
def _palmdoc(b):
    out = bytearray(); i = 0
    while i < len(b):
        c = b[i]; i += 1
        if c == 0 or 9 <= c <= 0x7f: out.append(c)
        elif 1 <= c <= 8: out += b[i:i + c]; i += c
        elif c >= 0xc0: out += b' ' + bytes([c ^ 0x80])
        else:
            if i >= len(b): break
            c = (c << 8) | b[i]; i += 1
            dist = (c >> 3) & 0x7ff; ln = (c & 7) + 3
            if dist == 0 or dist > len(out): break
            for _ in range(ln): out.append(out[-dist])
    return bytes(out)

def _image_ext(b):
    if b[:3] == b'\xff\xd8\xff': return '.jpg'
    if b[:4] == b'\x89PNG': return '.png'
    if b[:3] == b'GIF': return '.gif'
    if b[:2] == b'BM': return '.bmp'
    return None

def conv_mobi(src, out):
    with open(src, 'rb') as f: d = f.read()
    if d[60:68] != b'BOOKMOBI': raise RuntimeError('Keine MOBI-Datei.')
    n = struct.unpack('>H', d[76:78])[0]
    offs = [struct.unpack('>I', d[78 + 8 * i:82 + 8 * i])[0] for i in range(n)] + [len(d)]
    rec = lambda i: d[offs[i]:offs[i + 1]]
    r0 = rec(0)
    comp, _, _, textrecs, _, enc = struct.unpack('>HHIHHH', r0[:14])
    if enc != 0: raise RuntimeError('Datei ist kopiergeschuetzt (DRM) und wird nicht unterstuetzt.')
    if comp not in (1, 2): raise RuntimeError('Kompressionsart %d wird nicht unterstuetzt.' % comp)
    mobi = r0[16:]
    version = struct.unpack('>I', mobi[20:24])[0]
    if any(rec(i)[:8] == b'BOUNDARY' for i in range(n)):
        raise RuntimeError('MOBI/KF8-Mischformat wird noch nicht unterstuetzt.')
    kf8 = version >= 8
    hlen = struct.unpack('>I', mobi[4:8])[0]
    # Zusatzdaten am Ende jedes Textblocks (Flags liegen bei Byte 0xF2 des ersten Datensatzes)
    extra = struct.unpack('>H', r0[0xf2:0xf4])[0] if 16 + hlen >= 0xf4 else 0
    def strip(rd):
        end = len(rd)
        for bit in range(15, 0, -1):
            if extra >> bit & 1:
                v = 0; shift = 0; p = end - 1
                while p >= 0:
                    b = rd[p]; v |= (b & 0x7f) << shift; shift += 7
                    if b & 0x80: break
                    p -= 1
                end -= v
        if extra & 1: end -= (rd[end - 1] & 3) + 1
        return rd[:end]
    text = b''.join(rec(i) if comp == 1 else _palmdoc(strip(rec(i))) for i in range(1, textrecs + 1))
    first = struct.unpack('>I', mobi[0x6c:0x70])[0]
    if first in (0, 0xffffffff) or first >= n or not _image_ext(rec(first)):
        first = next((i for i in range(textrecs + 1, n) if _image_ext(rec(i))), None)
    if first is None: raise RuntimeError('Keine Bilder in der MOBI-Datei gefunden.')
    order, seen = [], set()
    pattern = rb'kindle:embed:([0-9A-Va-v]+)' if kf8 else rb'<img\b[^>]*?recindex="(\d+)"'
    for m in re.finditer(pattern, text, re.I):
        idx = int(m.group(1), 32 if kf8 else 10)
        if idx not in seen and first + idx - 1 < n and _image_ext(rec(first + idx - 1)):
            seen.add(idx); order.append(first + idx - 1)
    if not order:
        order = [i for i in range(first, n) if _image_ext(rec(i))]
        print('  Hinweis: Reihenfolge nach Datensaetzen (nicht aus dem Text lesbar), bitte pruefen.')
    tmp = tempfile.mkdtemp(prefix='cbz_')
    try:
        files = []
        for k, i in enumerate(order):
            data = rec(i); ext = _image_ext(data)
            p = os.path.join(tmp, '%06d%s' % (k, ext))
            with open(p, 'wb') as fh: fh.write(data)
            files.append((p, ext))
        return pack(files, out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# ---------- PDF ----------
def source_height(src, lst):
    """Echte Pixelhoehe einer Seite laut eingebetteten Bildern (x-ppi), sonst None.
    Verhindert, dass niedrig aufgeloeste PDFs sinnlos hochgerechnet werden."""
    ppis = [int(m.group(1)) for m in re.finditer(
        r'^\s*\d+\s+\d+\s+image\s+\d+\s+\d+\s+\S+\s+\d+\s+\d+\s+\S+\s+\S+\s+\d+\s+\d+\s+(\d+)\s+\d+\s', lst, re.M)]
    size = re.search(r'^Page size:\s+[\d.]+\s+x\s+([\d.]+)', run([which('pdfinfo') or 'pdfinfo', src]).stdout, re.M)
    if not ppis or not size:
        return None
    return int(float(size.group(1)) * max(ppis) / 72 + 0.5)

def full_page_images_only(src, lst):
    """True, wenn jede Seite genau ein ganzseitiges JPG/PNG ist (typischer Comic-Scan).
    Sonst (Text mit Logo, mehrere Bilder pro Seite, JPEG2000/JBIG2/CCITT) gingen beim Uebernehmen der
    Originalbilder Inhalte verloren, dann wird gerendert. Ohne pdfinfo: wie bisher uebernehmen."""
    pdfinfo = which('pdfinfo')
    if not pdfinfo:
        return True
    info = run([pdfinfo, src]).stdout
    m = re.search(r'^Pages:\s+(\d+)', info, re.M)
    if not m:
        return True
    pages = int(m.group(1))
    sizes = {}
    for m in re.finditer(r'^Page\s+(\d+)\s+size:\s+([\d.]+)\s+x\s+([\d.]+)',
                         run([pdfinfo, '-f', '1', '-l', str(pages), src]).stdout, re.M):
        sizes[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
    per_page = {}
    for m in re.finditer(r'^\s*(\d+)\s+\d+\s+image\s+(\d+)\s+(\d+)\s+\S+\s+\d+\s+\d+\s+(\S+)\s+\S+\s+\d+\s+\d+\s+(\d+)\s+(\d+)\s',
                         lst, re.M):
        pg, w, h, enc, xppi, yppi = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4), int(m.group(5)), int(m.group(6))
        if enc not in ('jpeg', 'image'):
            return False
        per_page[pg] = per_page.get(pg, 0) + 1
        size = sizes.get(pg)
        if size and xppi > 0 and yppi > 0:
            shown_w, shown_h = w * 72.0 / xppi, h * 72.0 / yppi
            if shown_w < size[0] * 0.9 or shown_h < size[1] * 0.9:
                return False
    return all(per_page.get(pg, 0) == 1 for pg in range(1, pages + 1))

def render_pages(src, tmp, height=None):
    """Seiten als JPG zeichnen: pdftoppm, sonst macOS-Renderer ueber Swift."""
    height = min(height, PDF_HEIGHT) if height else PDF_HEIGHT
    pdftoppm = which('pdftoppm')
    if pdftoppm:
        r = run([pdftoppm, '-jpeg', '-jpegopt', 'quality=%d' % JPG_QUALITY, '-cropbox', '-scale-to-y', str(height), '-scale-to-x', '-1', src, os.path.join(tmp, 'page')])
    else:
        r = run(['/usr/bin/swift', os.path.join(HERE, 'render.swift'), src, tmp, str(height), str(JPG_QUALITY)])
    if r.returncode != 0:
        raise RuntimeError('Rendern fehlgeschlagen: ' + r.stderr.strip()[-300:])

def conv_pdf(src, out):
    tmp = tempfile.mkdtemp(prefix='cbz_')
    try:
        pdfimages = which('pdfimages')
        use_render = pdfimages is None
        height = None
        if pdfimages:
            lst = run([pdfimages, '-list', src]).stdout
            height = source_height(src, lst)
            if re.search(r'^\s*\d+\s+\d+\s+image\s+\d+\s+\d+\s+cmyk\s', lst, re.M):
                # CMYK-JPEGs aus PDFs sind meist invertiert (Decode-Array geht beim Extrahieren verloren)
                print('  Hinweis: CMYK-Bilder im PDF (Farben waeren falsch) - Seiten werden gerendert.')
                use_render = True
            elif not full_page_images_only(src, lst):
                # Text mit kleinem Bild o. ae.: Originalbilder wuerden nur Teile der Seite zeigen.
                # Die Aufloesung kleiner Bilder sagt dann nichts ueber die Seite aus -> Standardhoehe.
                print('  Hinweis: Seiten sind keine reinen Bildseiten - Seiten werden gerendert.')
                height = None
                use_render = True
            elif height and height > PDF_HEIGHT * 1.1:
                # Quellbilder groesser als noetig: auf PDF_HEIGHT verkleinern
                print('  Hinweis: Bilder im PDF sind gross (ca. %d px Seitenhoehe) - Seiten werden auf %d px Hoehe verkleinert.' % (height, PDF_HEIGHT))
                use_render = True
            else:
                masks = {m.group(1) for m in re.finditer(r'^\s*\d+\s+(\d+)\s+(?:smask|mask)\s', lst, re.M)}
                run([pdfimages, '-all', '-p', src, os.path.join(tmp, 'img')])
                items = []
                for f in os.listdir(tmp):
                    m = re.match(r'img-(\d+)-(\d+)\.(\w+)$', f)
                    if m and m.group(2) not in masks:
                        items.append((int(m.group(1)), int(m.group(2)), os.path.join(tmp, f), '.' + m.group(3).lower()))
                if items:
                    items.sort()
                    pages = re.search(r'^Pages:\s+(\d+)', run([which('pdfinfo') or 'pdfinfo', src]).stdout, re.M)
                    if pages and int(pages.group(1)) != len(items):
                        print('  Warnung: PDF hat %s Seiten, aber %d Bilder extrahiert. Bitte pruefen.' % (pages.group(1), len(items)))
                    odd = {e for _, _, _, e in items if e not in ('.jpg', '.jpeg', '.png')}
                    if odd:
                        print('  Warnung: ungewoehnliche Bildformate (%s), evtl. nicht lesbar.' % ', '.join(sorted(odd)))
                    return pack([(p, e) for _, _, p, e in items], out)
                print('  Keine eingebetteten Bilder, rendere Seiten.')
                use_render = True
        else:
            print('  Hinweis: kein pdfimages (brew install poppler) - Seiten werden gerendert (JPG).')
        for f in os.listdir(tmp):
            os.remove(os.path.join(tmp, f))
        if height and height < PDF_HEIGHT:
            print('  Hinweis: PDF-Bilder haben nur ca. %d px Seitenhoehe - kein Hochrechnen, Hoehe %d px.' % (height, height))
        render_pages(src, tmp, height)
        return pack(walk_images(tmp), out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def convert(path):
    out = os.path.splitext(path)[0] + '.cbz'
    if os.path.exists(out):
        print('Uebersprungen, CBZ existiert schon: ' + out); return 'skip'
    print('Bearbeite: ' + path)
    ext = os.path.splitext(path)[1].lower()
    try:
        n = {'.epub': conv_epub, '.pdf': conv_pdf, '.mobi': conv_mobi, '.azw': conv_mobi, '.azw3': conv_mobi}.get(ext, conv_cbr)(path, out)
        print('  Fertig (%d Seiten): %s' % (n, out)); return 'ok'
    except Exception as e:
        print('  FEHLER: %s' % e)
        for p in (out, out + '.part'):
            if os.path.exists(p): os.remove(p)
        return 'fail'

def main(args):
    todo = []
    for a in args:
        if os.path.isdir(a):
            for root, _, fs in os.walk(a):
                for f in sorted(fs, key=nat):
                    if os.path.splitext(f)[1].lower() in SUPPORTED and not f.startswith('._'):
                        todo.append(os.path.join(root, f))
        elif os.path.splitext(a)[1].lower() in SUPPORTED:
            todo.append(a)
        else:
            print('Uebersprungen (Format nicht unterstuetzt): ' + a)
    res = [convert(p) for p in todo]
    print('\n==== Zusammenfassung ====')
    print('Umgewandelt:   %d\nUebersprungen: %d\nFehler:        %d' % (res.count('ok'), res.count('skip'), res.count('fail')))
    if skipped_total:
        print('Bilder in nicht unterstuetzten Formaten uebersprungen: %d' % skipped_total)
    return 1 if 'fail' in res else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
