# Änderungen – CBZ-Konverter

## 11.11.2026 (Windows-Claude): Fortschrittsdatei in eigenem Ordner

- Die Fortschrittsdatei liegt jetzt in `cache/cbzconverter/progress.txt` statt direkt in `cache/`. KOReader merkt sich beim Start alle Dateien direkt in `cache/` (Seiten-Zwischenspeicher) und stürzt beim Schließen eines Buchs ab, wenn eine davon inzwischen gelöscht ist (`doccache.lua:72`, gefunden über die Drive-Bibliothek). Backup: `Backups/cbzconverter.koplugin_vor-cache-unterordner_2026-11-11`. Test `test_cbz_hintergrund.sh`: 31 bestanden. Auf dem Kobo; GitHub-Ordner noch nicht angeglichen.

## 28.10.2026 (Windows-Claude): Umwandlung im Hintergrund

Rückmeldung des Nutzers: Bei großen PDFs blockierte das Fenster „Zum Abbrechen tippen“ den E-Reader, und nach der Einschlafzeit (10 Min.) schlief der Kobo ein, die Umwandlung wurde nicht fertig. Backup vorher: `Koreader\Backups\CBZ-Konverter vor Einschlaf-Schutz_2026-10-26` (Arbeitsstand) und `…Kobo vor Kuerzung und CBZ-Hintergrund_2026-10-28` (Kobo).
- **Neues Modul `cbz_job.lua`:** Jede Datei wird in einem eigenen Unterprozess umgewandelt (`ffiutil.runInSubProcess`, wie Story Recall und KOReaders Titelbild-Erstellung). KOReader bleibt bedienbar, man kann weiterlesen. Der Unterprozess schreibt den Fortschritt einmal pro Sekunde in `cache/cbzconverter-progress.txt`, das Ergebnis kommt über eine Pipe. Wird KOReader beendet, merkt der Unterprozess das (`getppid`) und bricht ab, unfertige Dateien werden gelöscht.
- Beim Start kurzer Hinweis „Umwandlung läuft im Hintergrund. Fortschritt und Abbrechen: Werkzeuge → CBZ-Konverter.“ Startet man weitere Dateien, während eine läuft, kommen sie in die Warteschlange (doppelte nicht zweimal).
- **Live-Fortschritt** als oberste Zeile im Menü („Läuft: Datei 1/2, Seite 14/40“, bei Archiven „Bild n“), zeichnet sich bei offenem Menü von selbst neu. Antippen fragt „Umwandlung abbrechen?“ (unfertige CBZ wird gelöscht, Warteschlange verworfen). Ohne Umwandlung: „Keine Umwandlung läuft“, nicht antippbar.
- **Kein Einschlafen von selbst** während der Umwandlung: KOReaders Schalter `PluginShare.pause_auto_suspend` (eine fremde Pause wird nicht zurückgenommen) und `preventStandby` (Standby würde den Unterprozess anhalten). Hülle und Knopf wirken weiter, die Umwandlung pausiert dann. Dimmen bleibt unberührt (autodim nutzt den Schalter nicht).
- **Am Ende** das gewohnte Fenster mit „Originale löschen / Behalten“, Überschrift „CBZ-Umwandlung fertig.“, bei genau einer Datei „Name.cbz (N Seiten)“. Erscheint auch mitten im Lesen.
- Neue Fehlertexte: Umwandlung konnte nicht gestartet werden / unerwartet beendet (evtl. zu wenig Speicher). Trapper (Fenster mit Antippen zum Abbrechen) entfällt, alte Texte entfernt. Anleitung um einen Absatz zum Hintergrund ergänzt.
- Öffnen des Originals während der Umwandlung wird nicht gesperrt (harmlos, beide lesen nur; die CBZ heißt bis zum Ende `.cbz.part`).
- **Test:** `Testumgebung/test_cbz_hintergrund.sh` + `2-cbz-hintergrund.lua`, 31 Prüfungen bestanden: Hauptprogramm läuft während der Umwandlung weiter, Fortschritt steigt, Warteschlange, Einschlafen pausiert und danach normal, Fertig-Fenster, 40-Seiten-PDF (selbst erzeugt) und CBR richtig, keine Reste, Abbrechen mittendrin (keine `.part`/`.tmp`, Original da), Menü (Status oben, Anleitung zuletzt), alle Testcomics CBT, EPUB, KEPUB, MOBI, AZW3, PDF mit je 12 Seiten. Im Test wird jede Seite künstlich gebremst, weil der Emulator viel schneller ist als der Kobo.
- Auf dem Kobo seit 28.10. Noch nicht im GitHub-Ordner (erst nach dem Test des Nutzers). Nicht getestet: echtes großes PDF auf dem Kobo, Speicher beim gleichzeitigen Lesen.

## 23.10.2026 (Windows-Claude, Arbeitsstand in WIP, noch nicht auf GitHub)

Gleich umgesetzt im Plugin (`cbz_converter.lua`), in der Mac-Fassung (`cbz.py`, auch in der App) und in der Windows-Fassung (`Comics_zu_cbz.bat`):

- **Seitenreihenfolge (11):** Pfade werden jetzt Ordner für Ordner verglichen statt als ganzer Text. Vorher kam „ch.-2.5/“ vor „ch.-2/“, weil „.“ vor „/“ sortiert. Zahlen mit Nachkommastellen zählen richtig (2 vor 2.5 vor 10, „Kapitel 9“ vor „Kapitel 10“).
- **Titelbild (12):** Pro Ebene kommen lose Bilder vor Unterordnern. Ein Bild, dessen Name mit „cover“ beginnt, kommt auf oberster Ebene ganz nach vorn. Ein gemeinsamer Oberordner um alles herum zählt als oberste Ebene. Gilt auch für die EPUB-Notlösung „nach Dateinamen“.
- **macOS-Reste (13):** Die Windows-Fassung ignoriert jetzt wie Plugin und Mac `__MACOSX/` und `._*`-Dateien, in Archiven und beim Ordner-Durchsuchen. Die Mac-Fassung filtert sie jetzt auch bei der EPUB-Notlösung.
- **Übersprungene Bilder (14):** Bilder in Formaten, die KOReader nicht anzeigt (AVIF, HEIC/HEIF, JXL, JPEG 2000, TIFF), werden weiter nicht übernommen, aber gezählt und gemeldet („N Bild(er) in nicht unterstützten Formaten übersprungen (z. B. .avif)“). Plugin: im Ergebnisfenster, Mac/Windows: als Hinweis je Datei und in der Zusammenfassung. Textdateien (txt, xml, nfo) zählen nicht.
- **Plugin-Menü:** Neuer letzter Eintrag „Wie funktioniert das?“ / „How does it work?“ mit Trennlinie davor.
- Windows-Fassung: Sortierung jetzt zeichengenau (vorher hing sie von der Windows-Spracheinstellung ab, die z. B. Bindestriche überspringt).

Tests:

- Lua-Einzeltest der Sortierung (12 Fälle) mit KOReaders LuaJIT: 12/12 bestanden. `syntax.sh`: 159 Dateien, 0 Fehler.
- KOReader-Testumgebung mit echtem libarchive: Testarchiv (Kapitelordner, cover.jpg, `__MACOSX`, `._x.jpg`, .avif, .heic, ComicInfo.xml, txt, nfo) ergibt cover, ch.-2/01, ch.-2/02, ch.-2.5/01, ch.-3/01, ch.-10/01 und den Hinweis „2 Bild(er) … (.avif, .heic)“. Alter Stand zum Vergleich: ch.-2.5 zuerst, cover zuletzt. Testcomics CBR, CBT, EPUB, MOBI: je 12 Seiten. Menü und Hilfetext (DE/EN) per Bildschirmfoto geprüft. Danach Testumgebung mit `sync.sh` zurückgesetzt.
- `cbz.py` in WSL: gleiche 12 Sortierfälle bestanden, Testarchiv als CBR und EPUB richtig, Testcomics EPUB, KEPUB, MOBI je 12 Seiten.
- `Comics_zu_cbz.bat` unter Windows mit 7-Zip: PowerShell-Teil ohne Syntaxfehler, gleiche 12 Sortierfälle bestanden, Testarchiv als CBR und EPUB richtig, Testcomics CBR, CB7, CBT, EPUB, MOBI je 12 Seiten, `._`-Quelldatei wird nicht bearbeitet.
- Nicht getestet: CB7 in der Linux-Testumgebung (scheitert dort auch mit dem alten Stand, die Linux-Fassung von KOReader liest 7z offenbar nicht), die Mac-App selbst am Mac, das Plugin auf dem Kobo.
