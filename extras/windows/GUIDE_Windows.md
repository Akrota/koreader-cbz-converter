# Comics to CBZ - Windows

Converts **CBR, CB7, CBT, PDF, EPUB (also KEPUB), MOBI, AZW and AZW3** to **CBZ**. Everything is in one file: `Comics_zu_cbz.bat`.

## One-time setup

| Program | Used for | Required? | Download |
|---|---|---|---|
| **7-Zip** | Unpacking CBR (RAR), CB7 and CBT | Yes, for CBR/CB7/CBT | https://www.7-zip.org/download.html (take the 64-bit "Windows x64" version, keep the default install path) |
| **Poppler** (`pdfimages.exe`) | PDF: read the image resolution, keep small original images unchanged | No, optional | https://github.com/oschwartz10612/poppler-windows/releases (download the latest `Release-...zip`) |

- **EPUB** needs nothing extra.
- **MOBI/AZW** (Mobipocket, only without copy protection) needs nothing extra: the page images are extracted unchanged, in the correct reading order. **AZW3/KF8** (pure KF8) is supported as well; the mixed format (MOBI+KF8 in one file) is not yet. Tested on Windows (October 2026).
- **PDF** also works without Poppler: the pages are then drawn as JPG by the renderer built into Windows (1680 px height, quality 90; low-resolution PDFs are not upscaled). With Poppler, the resolution of the PDF images is read: if they are not larger than necessary (up to about 1850 px height), the original images are kept unchanged, otherwise the pages are downscaled to 1680 px height. Original images are only kept when every page is a single full-page image (typical comic scan); pages with text, several images or unusual image formats are rendered in full so nothing gets lost.

### Setting up Poppler (optional)
1. Download the ZIP from the release page and unzip it.
2. Put the unzipped folder (e.g. `poppler-26.09.0`) **next to** `Comics_zu_cbz.bat`. The script finds `pdfimages.exe` on its own, also in subfolders.

## Usage
- **Drag and drop:** drag files or whole folders onto `Comics_zu_cbz.bat`.
- **Double-click:** a window opens where you can drop files/folders.
- The CBZ is saved **next to the original**; the original is left unchanged.
- If the CBZ already exists, the file is skipped.
- A summary is shown at the end (converted / skipped / failed).

## Notes
- Same name as EPUB and PDF in the same folder: the second file is skipped (the CBZ already exists by then).
- Only DRM-free files work.
- If Windows shows "Windows protected your PC" (SmartScreen): "More info" -> "Run anyway".
- For warnings like "PDF has X pages, but Y images were extracted", take a quick look at the result.
