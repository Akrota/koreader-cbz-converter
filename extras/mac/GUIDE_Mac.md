# Comics to CBZ - Mac

Converts **CBR, CB7, CBT, PDF, EPUB (also KEPUB), MOBI, AZW and AZW3** to **CBZ**. The app: `Comics zu CBZ.app`.

## One-time setup (optional, as needed)

| Program | Used for | Download |
|---|---|---|
| **Homebrew** | Package manager for the programs below | https://brew.sh |
| **7-Zip** (`sevenzip`) or **The Unarchiver** | Unpacking CBR (RAR) if the built-in `bsdtar` cannot handle a RAR | Terminal: `brew install sevenzip` or https://theunarchiver.com |
| **Poppler** (`pdfimages`) | PDF: read the image resolution, keep small original images unchanged | Terminal: `brew install poppler` |

- **EPUB** needs nothing extra.
- **MOBI/AZW** (Mobipocket, only without copy protection) needs nothing extra: the page images are extracted unchanged, in the correct reading order. **AZW3/KF8** (pure KF8) is supported as well; the mixed format (MOBI+KF8 in one file) is not yet.
- **PDF** also works without Poppler: pages are rendered (JPG, 1680 px height, quality 90). Without Poppler the app does not know the real resolution of the PDF images and always renders at 1680 px, so low-resolution PDFs are upscaled (bigger file, image not worse). **With Poppler** (recommended): the resolution is read, small PDFs are not upscaled, and if the pages are pure image pages (one full-page JPG/PNG per page, up to about 1850 px height) the original images are kept unchanged. Pages with text and small images, several images or unusual image formats are rendered in full so nothing gets lost; CMYK PDFs are always rendered. Rendering needs Swift (Xcode Command Line Tools: Terminal `xcode-select --install`).
- Python 3 is required (`/usr/bin/python3` comes with the Command Line Tools).

## Usage
- Drag files or folders onto the **app icon** (Finder or Dock).
- Or double-click the app and choose files in the selection window.
- The CBZ is saved **next to the original**; existing CBZ files are skipped.
- A window shows the summary at the end.

## First launch
The app is not signed by Apple. If macOS blocks it: **right-click -> Open** -> confirm "Open" (needed only once).

## Notes
- Only DRM-free files.
- To work without the app: `python3 Quellcode/cbz.py file.cbr` in the Terminal.

## After a change to the app (October 2026)
`cbz.py` inside the app was updated (PDF fix for pages with text and a small image). This breaks the app's signature.
If macOS says the app is damaged or cannot be opened, run this once in Terminal in the app's folder:

    codesign --force --deep -s - "Comics zu CBZ.app"

It then starts normally again. This version was not tested on a Mac.
