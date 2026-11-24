-- Minimale Zweisprachigkeit (Deutsch / Englisch), Sprache folgt der KOReader-Einstellung
local strings = {
    de = {
        menu_title = "CBZ-Konverter",
        menu_file = "Datei wählen …",
        menu_folder = "Ordner wählen (alle CBR/EPUB/PDF darin) …",
        button_convert = "In CBZ umwandeln",
        no_files = "Keine CBR/EPUB/PDF-Dateien gefunden.",
        confirm_folder = "%d Datei(en) in CBZ umwandeln?\n\nDas kann dauern. Die Originale bleiben zunächst erhalten.",
        start = "Starten",
        status_idle = "Keine Umwandlung läuft",
        status_file = "Läuft: Datei %d/%d …",
        status_page = "Läuft: Datei %d/%d, Seite %d/%d",
        status_image = "Läuft: Datei %d/%d, Bild %d",
        started_bg = "Umwandlung läuft im Hintergrund.\nFortschritt und Abbrechen: Werkzeuge → CBZ-Konverter.",
        queued = "Läuft schon eine Umwandlung: Die Datei(en) kommen danach dran.",
        cancel_q = "Umwandlung abbrechen?\n%s\n\n(Die unfertige CBZ wird gelöscht, das Original bleibt erhalten. Weitere Dateien in der Warteschlange werden nicht mehr bearbeitet.)",
        done_title = "CBZ-Umwandlung fertig.",
        done_one = "%s (%d Seiten)",
        err_unknown = "unbekannter Fehler",
        err_start = "Umwandlung konnte nicht gestartet werden.",
        err_crash = "Umwandlung unerwartet beendet (evtl. zu wenig Speicher).",
        sum_ok = "Umgewandelt: %d",
        sum_skip = "Übersprungen (CBZ existiert): %d",
        sum_fail = "Fehler: %d",
        delete_q = "Originaldateien der %d erfolgreich umgewandelten Datei(en) löschen?\n(Spart Speicherplatz. Nicht rückgängig zu machen.)",
        delete_ok = "Originale löschen",
        delete_keep = "Behalten",
        deleted = "%d Original(e) gelöscht.",
        err_no_images = "Keine Bilder gefunden.",
        err_cbz_create = "CBZ konnte nicht angelegt werden: ",
        err_write = "Schreiben fehlgeschlagen: ",
        err_archive = "Archiv nicht lesbar: ",
        err_epub = "EPUB nicht lesbar: ",
        err_epub_no_images = "Keine Bilder im EPUB (evtl. DRM oder reiner Text).",
        err_pdf = "PDF nicht lesbar.",
        err_mobi = "MOBI nicht lesbar.",
        err_mobi_drm = "MOBI ist kopiergeschützt (DRM) und wird nicht unterstützt.",
        err_mobi_kf8 = "MOBI/KF8-Mischformat wird noch nicht unterstützt.",
        err_mobi_no_images = "Keine Bilder in der MOBI-Datei gefunden.",
        err_render = "Rendern fehlgeschlagen: ",
        note_order = "Reihenfolge nach Dateinamen (bitte prüfen)",
        note_pdf_native = "PDF-Bilder nur %d px hoch, nicht hochgerechnet",
        skip = "übersprungen, CBZ existiert schon",
        cancelled = "abgebrochen",
        abort = "Abbrechen",
        continue = "Weiter",
        sum_cancel = "Abgebrochen – restliche Dateien wurden nicht bearbeitet.",
        note_skipped = "%d Bild(er) in nicht unterstützten Formaten übersprungen (z. B. %s)",
        about = "Wie funktioniert das?",
        about_text = "Wandelt CBR, CB7, CBT, PDF, EPUB (auch KEPUB), MOBI, AZW und AZW3 direkt auf dem Gerät in CBZ um.\n\n"
            .. "Die CBZ landet im selben Ordner wie das Original. Das Original bleibt unverändert. Am Ende können Sie wählen, ob die Originale gelöscht werden.\n\n"
            .. "Die Umwandlung läuft im Hintergrund, Sie können währenddessen lesen. Den Fortschritt zeigt die oberste Zeile dieses Menüs, Antippen bricht ab. Von selbst schläft der E-Reader in der Zeit nicht ein, Hülle zuklappen geht weiter (die Umwandlung pausiert dann).\n\n"
            .. "Seitenreihenfolge bei Comic-Archiven: nach Namen, Ordner für Ordner, Zahlen richtig gezählt (2 vor 2.5 vor 10). Einzelne Bilder kommen vor den Unterordnern, ein Titelbild namens cover ganz nach vorn. EPUB und MOBI behalten ihre eigene Reihenfolge.\n\n"
            .. "Bilder in Formaten, die KOReader nicht anzeigen kann (z. B. AVIF, HEIC, TIFF), werden übersprungen. Die Zusammenfassung am Ende sagt, wie viele.",
    },
    en = {
        menu_title = "CBZ converter",
        menu_file = "Choose file …",
        menu_folder = "Choose folder (all CBR/EPUB/PDF inside) …",
        button_convert = "Convert to CBZ",
        no_files = "No CBR/EPUB/PDF files found.",
        confirm_folder = "Convert %d file(s) to CBZ?\n\nThis may take a while. Originals are kept for now.",
        start = "Start",
        status_idle = "No conversion running",
        status_file = "Running: file %d/%d …",
        status_page = "Running: file %d/%d, page %d/%d",
        status_image = "Running: file %d/%d, image %d",
        started_bg = "Converting in the background.\nProgress and cancel: Tools → CBZ converter.",
        queued = "A conversion is already running: the file(s) come next.",
        cancel_q = "Cancel conversion?\n%s\n\n(The unfinished CBZ is deleted, the original is kept. Further files in the queue are not processed.)",
        done_title = "CBZ conversion finished.",
        done_one = "%s (%d pages)",
        err_unknown = "unknown error",
        err_start = "Conversion could not be started.",
        err_crash = "Conversion ended unexpectedly (maybe not enough memory).",
        sum_ok = "Converted: %d",
        sum_skip = "Skipped (CBZ exists): %d",
        sum_fail = "Failed: %d",
        delete_q = "Delete the original files of the %d successfully converted file(s)?\n(Saves space. Cannot be undone.)",
        delete_ok = "Delete originals",
        delete_keep = "Keep",
        deleted = "%d original(s) deleted.",
        err_no_images = "No images found.",
        err_cbz_create = "Could not create CBZ: ",
        err_write = "Writing failed: ",
        err_archive = "Cannot read archive: ",
        err_epub = "Cannot read EPUB: ",
        err_epub_no_images = "No images in EPUB (DRM or text only?).",
        err_pdf = "Cannot read PDF.",
        err_mobi = "Cannot read MOBI.",
        err_mobi_drm = "MOBI is copy-protected (DRM) and is not supported.",
        err_mobi_kf8 = "Mixed MOBI/KF8 format is not supported yet.",
        err_mobi_no_images = "No images found in the MOBI file.",
        err_render = "Rendering failed: ",
        note_order = "sorted by file name (please check)",
        note_pdf_native = "PDF images only %d px high, not upscaled",
        skip = "skipped, CBZ already exists",
        cancelled = "cancelled",
        abort = "Cancel",
        continue = "Continue",
        sum_cancel = "Cancelled – remaining files were not processed.",
        note_skipped = "%d image(s) in unsupported formats skipped (e.g. %s)",
        about = "How does it work?",
        about_text = "Converts CBR, CB7, CBT, PDF, EPUB (including KEPUB), MOBI, AZW and AZW3 to CBZ, right on the device.\n\n"
            .. "The CBZ is saved in the same folder as the original. The original stays untouched. At the end you can choose whether to delete the originals.\n\n"
            .. "Conversion runs in the background, you can keep reading. The top line of this menu shows the progress, tapping it cancels. The e-reader does not fall asleep by itself meanwhile; closing the cover still works (the conversion pauses then).\n\n"
            .. "Page order in comic archives: by name, folder by folder, with numbers counted correctly (2 before 2.5 before 10). Loose images come before subfolders, a title image named cover comes first. EPUB and MOBI keep their own order.\n\n"
            .. "Images in formats KOReader cannot show (e.g. AVIF, HEIC, TIFF) are skipped. The summary at the end tells you how many.",
    },
}

local function language()
    local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
    if not ok or type(lang) ~= "string" then
        ok, lang = pcall(function() return require("gettext").current_lang end)
    end
    return (ok and type(lang) == "string" and lang:sub(1, 2):lower() == "de") and "de" or "en"
end

return function(key, ...)
    local s = strings[language()][key] or strings.en[key] or key
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end
