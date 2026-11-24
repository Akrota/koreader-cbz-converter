# Comics zu CBZ - Mac

Wandelt **CBR, CB7, CBT, PDF, EPUB (auch KEPUB), MOBI, AZW und AZW3** in **CBZ** um. Die App: `Comics zu CBZ.app`.

## Einmalig installieren (optional, je nach Bedarf)

| Programm | Wofuer | Download |
|---|---|---|
| **Homebrew** | Paketmanager fuer die Programme unten | https://brew.sh |
| **7-Zip** (`sevenzip`) oder **The Unarchiver** | CBR (RAR) entpacken, falls das eingebaute `bsdtar` ein RAR nicht schafft | Terminal: `brew install sevenzip` oder https://theunarchiver.com |
| **Poppler** (`pdfimages`) | PDF: Aufloesung auslesen, kleine Originalbilder unveraendert uebernehmen | Terminal: `brew install poppler` |

- **EPUB** braucht nichts extra.
- **MOBI/AZW** (Mobipocket, nur ohne Kopierschutz) braucht nichts extra: die Seitenbilder werden unveraendert in der richtigen Reihenfolge herausgeholt. **AZW3/KF8** (reines KF8) wird ebenfalls unterstuetzt; das Mischformat (MOBI+KF8 in einer Datei) noch nicht.
- **PDF** geht auch ohne Poppler: Seiten werden gerendert (JPG, 1680 px Hoehe, Qualitaet 90). Ohne Poppler kennt die App die echte Aufloesung der PDF-Bilder nicht und rendert immer auf 1680 px, rechnet niedrig aufgeloeste PDFs also hoch (Datei groesser, Bild nicht schlechter). **Mit Poppler** (empfohlen): Die Aufloesung wird ausgelesen, kleine PDFs werden nicht hochgerechnet, und sind die Seiten reine Bildseiten (eine ganzseitige JPG/PNG pro Seite, bis ca. 1850 px Hoehe), kommen die Originalbilder unveraendert heraus. Seiten mit Text und kleinen Bildern, mehreren Bildern oder exotischen Bildformaten werden komplett gerendert, damit nichts verloren geht; CMYK-PDFs werden immer gerendert. Fuer das Rendern muss Swift vorhanden sein (Xcode Command Line Tools: Terminal `xcode-select --install`).
- Python 3 wird gebraucht (`/usr/bin/python3` kommt mit den Command Line Tools).

## Benutzung
- Dateien oder Ordner auf das **App-Symbol** ziehen (Finder oder Dock).
- Oder die App per Doppelklick starten und Dateien im Auswahlfenster waehlen.
- Die CBZ liegt **neben dem Original**; vorhandene CBZ werden uebersprungen.
- Am Ende zeigt ein Fenster die Zusammenfassung.

## Erster Start
Die App ist nicht von Apple signiert. Falls macOS sie blockiert: **Rechtsklick -> Oeffnen** -> "Oeffnen" bestaetigen (nur einmal noetig).

## Hinweise
- Nur DRM-freie Dateien.
- Wer ohne App arbeiten will: `python3 Quellcode/cbz.py datei.cbr` im Terminal.

## Nach einer Aenderung an der App (Oktober 2026)
In der App wurde `cbz.py` aktualisiert (PDF-Fix fuer Seiten mit Text und kleinem Bild). Dadurch passt die Signatur der
App nicht mehr. Meldet macOS beim Start, die App sei beschaedigt oder koenne nicht geoeffnet werden, einmal im Terminal
im Ordner der App ausfuehren:

    codesign --force --deep -s - "Comics zu CBZ.app"

Danach startet sie wieder normal. Dieser Stand wurde nicht auf einem Mac getestet.
