# Comics zu CBZ - Windows

Wandelt **CBR, CB7, CBT, PDF, EPUB (auch KEPUB), MOBI, AZW und AZW3** in **CBZ** um. Alles steckt in einer Datei: `Comics_zu_cbz.bat`.

## Einmalig installieren

| Programm | Wofuer | Pflicht? | Download |
|---|---|---|---|
| **7-Zip** | CBR (RAR), CB7 und CBT entpacken | Ja, fuer CBR/CB7/CBT | https://www.7-zip.org/download.html (die 64-bit-Version "Windows x64" nehmen, Standardpfad lassen) |
| **Poppler** (`pdfimages.exe`) | PDF: Aufloesung auslesen, kleine Originalbilder unveraendert uebernehmen | Nein, optional | https://github.com/oschwartz10612/poppler-windows/releases (neueste `Release-...zip` laden) |

- **EPUB** braucht nichts extra.
- **MOBI/AZW** (Mobipocket, nur ohne Kopierschutz) braucht nichts extra: die Seitenbilder werden unveraendert in der richtigen Reihenfolge herausgeholt. **AZW3/KF8** (reines KF8) wird ebenfalls unterstuetzt; das Mischformat (MOBI+KF8 in einer Datei) noch nicht. Unter Windows getestet (Oktober 2026).
- **PDF** funktioniert auch ohne Poppler: Dann werden die Seiten mit dem in Windows eingebauten Renderer als JPG gezeichnet (1680 px Hoehe, Qualitaet 90, niedrig aufgeloeste PDFs werden nicht hochgerechnet). Mit Poppler wird die Aufloesung der PDF-Bilder ausgelesen: Sind sie nicht groesser als noetig (bis ca. 1850 px Hoehe), kommen die Originalbilder unveraendert heraus, sonst werden die Seiten auf 1680 px Hoehe verkleinert. Originalbilder werden nur uebernommen, wenn jede Seite ein einziges ganzseitiges Bild ist (typischer Comic-Scan); Seiten mit Text, mehreren Bildern oder exotischen Bildformaten werden komplett gerendert, damit nichts verloren geht.

### Poppler einrichten (optional)
1. ZIP von der Release-Seite herunterladen und entpacken.
2. Den entpackten Ordner (z. B. `poppler-26.09.0`) **neben** `Comics_zu_cbz.bat` legen. Die Bat findet `pdfimages.exe` selbst, auch in Unterordnern.

## Benutzung
- **Drag and Drop:** Dateien oder ganze Ordner auf `Comics_zu_cbz.bat` ziehen.
- **Per Doppelklick:** Es oeffnet sich ein Fenster, in das du Dateien/Ordner hineinziehen kannst.
- Die CBZ liegt danach **neben dem Original**, das Original bleibt unveraendert.
- Existiert die CBZ schon, wird die Datei uebersprungen.
- Am Ende steht eine Zusammenfassung (umgewandelt / uebersprungen / Fehler).

## Hinweise
- Gleicher Name als EPUB und PDF im selben Ordner: die zweite Datei wird uebersprungen (CBZ existiert dann schon).
- Nur DRM-freie Dateien funktionieren.
- Meldet Windows "Der Computer wurde durch Windows geschuetzt" (SmartScreen): "Weitere Informationen" -> "Trotzdem ausfuehren".
- Bei Warnungen wie "PDF hat X Seiten, aber Y Bilder" kurz das Ergebnis ansehen.
