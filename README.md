# Whiteboard

A quiet macOS canvas for sudden ideas, screenshots and working things out.

Write over your desktop. Keep unfinished thoughts on a small filename shelf. Come back when they are useful. Add editable LaTeX equations and TikZ diagrams when a thought needs more precision.

![The actual Whiteboard workspace with fictional academic sample content](docs/demos/academic-workspace.png)

**Native preview · Apple silicon · Local files · No account**

[Download the app](https://github.com/zakimaths/whiteboard/releases/tag/v0.3.0) · [Try the demos](docs/DEMOS.md) · [Full feature checklist](docs/IMPLEMENTATION.md) · [Research and optimisation](docs/OPTIMISATION-RESEARCH.md)

## What works today

- Immediate drawing and typing on a transparent, dimmed or paper board.
- Scroll for more room, pan, pinch to zoom, or fit all content.
- Automatic shapes: sketch a line, arrow, box, circle or ellipse with the pen and it snaps when you lift. Undo restores your original ink. Recognition stays local and runs only at pen-up.
- Explicit shape tools are also available, with Shift constraints and the same undo/save/export behaviour as ink.
- Drop or paste screenshots; select, move, resize and annotate them. Attached ink follows the image.
- A collapsible top shelf whose buttons read real filenames. Red is unfinished, green is finished; labels and symbols accompany the colours.
- Pin important ideas and move them earlier or later on the shelf. Preferences stay separate for each library.
- Local autosave, save/reopen, copies, archive, and recovery of the previous saved revision as a separate file.
- LaTeX and TikZ source editing, bounded image previews and vector PDF assets. No typesetting process remains running between renders.
- Content or selection export to PNG/PDF; copy an annotated selection as PNG; export a workspace preview with the desktop excluded.
- Menu-bar show/hide and movement between connected monitors.

This is a working preview, not the complete 84-feature product. Thumbnail cards, direct drag-to-status, cropping, OCR, handwriting-to-equation recognition and longer recovery history remain planned. [Exact implementation status](docs/IMPLEMENTATION.md).

## Open and use

Unzip the download and open **Whiteboard.app**. A pencil icon appears in the macOS menu bar. The preview is ad-hoc signed, **not notarised by Apple**; macOS may require an explicit allowance in Privacy & Security for a downloaded copy. Building locally is also supported.

Click **Demo** on the shelf, or choose **File → Open demo workspace**. Four editable examples open in a separate demo library. Click **My ideas** to return to your previous board. Demo edits persist; reopening the demo does not create duplicate samples. No account or TeX installation is needed for these four examples.

To look around without installing anything, [view the public demos](docs/DEMOS.md). Distribution is through GitHub; there is no App Store listing.

| Action | Control |
| --- | --- |
| Show / hide | Shift–Command–B or the menu-bar control |
| Pen / highlighter / eraser / select / text | P / H / E / V / T |
| Automatic shape recognition | Draw with the pen; Auto shapes is on by default |
| Keep original handwriting | Undo a snap; hold Shift for a stroke, or turn off Auto shapes |
| Line / arrow / rectangle / ellipse | L / A / R / O, or the Shapes toolbar menu |
| Constrain a shape | Hold Shift for 45° angles, squares or circles |
| Cancel an in-progress shape | Escape |
| Temporary ink eraser | Right-drag |
| More space / pan | Scroll / Option-drag |
| Zoom | Pinch, Command-scroll, or + / − |
| Fit everything / reset view | Command–1 / Command–0 |
| Rename / new idea | Return / Command–N |
| Import screenshot | Drop, paste, or File → Import image |
| Capture screenshot | Camera button; macOS permission may be required |
| Resize an image | Select it and drag its bottom-right handle |
| Duplicate selection | Command–D |
| Fresh copy without annotations | Edit menu |
| LaTeX / TikZ | File → Insert LaTeX / Insert TikZ |
| Edit maths source | Select tool, then double-click the item |
| Copy selection as PNG | Command–C |
| Undo / redo | Command–Z / Shift–Command–Z |
| Export whole content or selection | Command–E; File menu for PDF |
| Pin / reorder | Control-click a shelf file → Pin, Move earlier / later |
| Change status or archive | Finish / Reopen button or Control-click a shelf file |
| Try / leave the demo | Demo / My ideas in the shelf |
| Change monitor | Screens or the menu-bar display actions |

### Your files

New libraries default to `~/Library/Application Support/Whiteboard/Ideas`, outside the app bundle. **File → Choose ideas folder…** selects another folder. The app creates `Unfinished`, `Finished` and `Archive` there. **Show ideas folder** in the menu bar opens it in Finder.

Pins and manual order are stored in macOS preferences for each library. In-app rename and status moves retain them; external Finder renames and moving the library to another Mac do not yet carry these preferences.

Each `.whiteboard` directory holds editable `board.json`, one `previous.json` revision and an `assets` folder. Reopen it through the shelf. Imported screenshots and typeset PDF/PNG assets are copied into the board, so moving their original source files does not break it. The original handwriting is retained.

**Saved locally** appears after a successful write. Save failures keep the in-memory work and offer a copy workflow. Saves commit completed gestures; an in-flight stroke commits on release, hide or quit. Keep backups of important work while using the preview.

### LaTeX and TikZ

Rendering needs a local TeX installation with `pdflatex`, `standalone`, `amsmath`, `amssymb` and TikZ. Saved maths remains viewable and exportable without that installation. No TeX distribution is bundled or downloaded automatically. [Examples, editing behaviour and supported packages](docs/MATHS.md).

## Built for a quiet desktop

The app uses AppKit and Core Graphics, with no webview or third-party Swift packages. Drawing responds to input and invalidation; saves and folder refreshes use one-shot scheduling. Screenshot previews share a 48 MiB decoded-image budget. Typesetting is an optional short-lived process on its own utility queue.

A pre-typesetting sample-board build measured roughly **52 MiB RSS and 0.23% average idle CPU over 30 seconds** on the development Mac. An earlier larger-board check and the exact limitations are in [validation](docs/VALIDATION.md). RSS is not total system memory, and these measurements are not battery-life guarantees.

## Build and check

Requires macOS and Apple’s Swift command-line tools. The deployment target is macOS 13; local interaction testing used Apple silicon and macOS 26.6.2. Older macOS and Intel interaction testing remain outstanding.

```sh
bash scripts/check.sh
bash scripts/build.sh
```

The result is `build/Whiteboard.app`. Compiler caches stay in `.build`; normal user ideas stay outside the build folder.

The core checks use actual temporary files and the same implementation as the app. Optional integration checks use an installed TeX engine:

```sh
WHITEBOARD_TEX_CHECKS=1 bash scripts/check.sh
```

[Release notes](docs/RELEASE-NOTES.md) · [Validation](docs/VALIDATION.md) · [Sharing materials](docs/SHARING.md)
