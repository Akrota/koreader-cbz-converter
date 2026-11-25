# Changelog – CBZ Converter

*Deutsche Fassung weiter unten.*

## 11 Nov 2026

- The progress file now lives in its own subfolder (`cache/cbzconverter/`). KOReader's page cache could crash when closing a book if a helper file directly in `cache/` had been deleted.

## 28 Oct 2026: conversion in the background

- Every file is converted in its own background process. KOReader stays usable and you can keep reading.
- Files started while a conversion is running are queued. Live progress is shown as the top line of the menu; tapping it asks whether to cancel (the unfinished CBZ is deleted).
- The device does not fall asleep by itself while converting. The cover and the power button still work, the conversion pauses then.
- At the end the usual window offers "Delete originals" or "Keep", also while you are reading.

## 23 Oct 2026

(Applies to the plugin and the Windows and Mac versions.)

- **Page order:** paths are compared folder by folder, and numbers with decimals count correctly (2 before 2.5 before 10).
- **Cover:** loose images come before subfolders, and an image whose name starts with "cover" on the top level comes first.
- **macOS leftovers** (`__MACOSX/`, `._*`) are ignored everywhere.
- **Skipped images:** formats KOReader cannot show (AVIF, HEIC/HEIF, JXL, JPEG 2000, TIFF) are counted and reported.
- Plugin menu: new entry "How does it work?".
- Windows version: sorting no longer depends on the Windows language setting.

---

# Deutsch

## 11.11.2026

- Die Fortschrittsdatei liegt jetzt in einem eigenen Unterordner (`cache/cbzconverter/`). KOReaders Seiten-Zwischenspeicher konnte beim Schließen eines Buchs abstürzen, wenn eine Hilfsdatei direkt in `cache/` gelöscht worden war.

## 28.10.2026: Umwandlung im Hintergrund

- Jede Datei wird in einem eigenen Hintergrundprozess umgewandelt. KOReader bleibt bedienbar, man kann weiterlesen.
- Weitere Dateien, die während einer Umwandlung gestartet werden, kommen in die Warteschlange. Der Fortschritt steht als oberste Zeile im Menü; Antippen fragt, ob abgebrochen werden soll (die unfertige CBZ wird gelöscht).
- Während der Umwandlung schläft das Gerät nicht von selbst ein. Hülle und Ein-Knopf wirken weiter, die Umwandlung pausiert dann.
- Am Ende bietet das gewohnte Fenster „Originale löschen“ oder „Behalten“ an, auch mitten im Lesen.

## 23.10.2026

(Gilt für das Plugin und die Windows- und Mac-Fassung.)

- **Seitenreihenfolge:** Pfade werden Ordner für Ordner verglichen, Zahlen mit Nachkommastellen zählen richtig (2 vor 2.5 vor 10).
- **Titelbild:** Lose Bilder kommen vor Unterordnern, ein Bild mit dem Namensanfang „cover“ steht auf oberster Ebene ganz vorn.
- **macOS-Reste** (`__MACOSX/`, `._*`) werden überall ignoriert.
- **Übersprungene Bilder:** Formate, die KOReader nicht anzeigt (AVIF, HEIC/HEIF, JXL, JPEG 2000, TIFF), werden gezählt und gemeldet.
- Plugin-Menü: neuer Eintrag „Wie funktioniert das?“.
- Windows-Fassung: Die Sortierung hängt nicht mehr von der Windows-Spracheinstellung ab.
