# CBZ converter for KOReader

*Deutsch: [README.de.md](README.de.md)*

A KOReader plugin that converts **CBR, CB7, CBT, PDF, EPUB (also KEPUB), MOBI, AZW and AZW3** to **CBZ** directly on your e-reader. No computer is needed. The CBZ is saved next to the original, and the original is kept.

**Bonus:** the same converter is also available for [Windows and Mac](#bonus-windows-and-mac), for converting whole collections on a computer.

## Installation

1. Download the ZIP from [Releases](../../releases) and unpack it, or download this repository.
2. Copy the folder **`cbzconverter.koplugin`** to KOReader's `plugins` folder. On a Kobo, that is `.adds/koreader/plugins/`. The `.adds` folder is hidden: on a Mac press `Cmd + Shift + .` in Finder, on Windows turn on "Hidden items".
3. Restart KOReader.

When updating, replace the whole `cbzconverter.koplugin` folder, not single files.

## Usage

- **Single file:** in the file manager, **long-press** a file and tap **"Convert to CBZ"**.
- **Via the menu:** top menu → Tools → **CBZ converter** → "Choose file" or "Choose folder". The folder option converts everything inside, including subfolders.
- **Cancel:** a message shows the progress. Tapping the screen asks "Cancel / Continue". On cancel, the unfinished CBZ is deleted and the original stays untouched. The cancel takes effect after the current step (for PDFs, after the current page).
- **Delete originals?** At the end, a popup asks whether to delete or keep the originals of the successfully converted files. "Keep" is the safe choice. A file is only deleted if its new CBZ exists and is not empty.
- If the CBZ already exists, the file is skipped. A summary (converted / skipped / failed) is shown at the end.
- **Language:** German or English, depending on KOReader's language. Any other language falls back to English.

## How it works

- **CBR, CB7, CBT:** the images are unpacked, sorted naturally (1, 2, 10 instead of 1, 10, 2) and packed unchanged into a CBZ. KOReader ships with libarchive, so no extra program is needed.
- **EPUB:** the reading order comes from the EPUB itself. If the plugin can't find it, it sorts by file name and tells you.
- **MOBI, AZW, AZW3** (only without copy protection): the page images are taken in reading order and packed unchanged. The mixed MOBI+KF8 format isn't supported yet.
- **PDF:** each page is rendered by KOReader as a **JPG at 1680 px height** (the screen height of the Kobo Libra Colour) with quality 90. The plugin uses the height so that single pages and double-page spreads are equally sharp. Low-resolution PDFs are **not upscaled**: the plugin reads the size of the full-page images in the PDF and renders at most at that height. Rendering takes a few seconds per page. `PDF_HEIGHT` and `PDF_QUALITY` at the top of `cbz_converter.lua` can be lowered if memory runs short.

## Limits

- It only works with DRM-free files.
- Very large PDFs (100+ pages) take a long time, so keep an eye on the battery.
- Very large single images can run out of memory. You then get an error instead of a CBZ.

## Bonus: Windows and Mac

[`extras/`](extras) contains the same converter for computers, with the same rules (1680 px, no upscaling, CBR/EPUB repacked unchanged):

| | What it is | Guide |
| --- | --- | --- |
| [`extras/windows`](extras/windows) | `Comics_zu_cbz.bat`, everything in one file, with drag and drop | [GUIDE_Windows.md](extras/windows/GUIDE_Windows.md) |
| [`extras/mac`](extras/mac) | `Comics zu CBZ.app`, a droplet app (source code in `Quellcode/`) | [GUIDE_Mac.md](extras/mac/GUIDE_Mac.md) |

Optional helper programs: [7-Zip](https://www.7-zip.org/) and [Poppler](https://github.com/oschwartz10612/poppler-windows/releases) on Windows, and `brew install poppler sevenzip` on a Mac. They aren't part of this repository.

## Test files

[`testfiles/`](testfiles) contains a self-made 12-page test comic in every supported format, with no third-party content.

## Tested on

- Kobo Libra Colour with KOReader 2026.07.1 (also with ZenOS), with all test files.
- Windows 11, with and without Poppler.
- macOS: the app was used on a Mac. The latest change to `cbz.py` hasn't been tested there yet.

## Who made this

The code was written entirely by **Claude**, an AI by Anthropic: the plugin and the Mac version by Claude on a Mac, and the Windows version, testing and fixes by Claude on Windows. The owner of this repository came up with the idea, tested it and gave feedback, but did not write the code.

There is no warranty and no guaranteed support. Bug reports are welcome as [issues](../../issues). Please attach `crash.log` from the KOReader folder.

## License

[MIT](LICENSE). 7-Zip and Poppler are separate programs with their own licenses.
