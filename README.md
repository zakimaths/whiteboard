# Whiteboard

A quiet macOS canvas for sudden ideas, screenshots and working things out.

Write over your desktop. Keep unfinished thoughts on a small filename shelf. Come back when they are useful. Add editable LaTeX equations and TikZ diagrams when a thought needs more precision.

![Worked heat-diffusion model exported by Whiteboard](docs/demos/pde-heat.png)

**Native preview · Apple silicon · Local files · No account**

[Download the app](https://github.com/zakimaths/whiteboard/releases/tag/v0.6.0) · [Try the demos](docs/DEMOS.md) · [Full feature checklist](docs/IMPLEMENTATION.md) · [Research and optimisation](docs/OPTIMISATION-RESEARCH.md)

## What works today

- Immediate drawing and typing on a transparent, dimmed or paper board.
- Scroll for more room, pan, pinch to zoom, or fit all content.
- Automatic shapes: sketch a line, arrow, box, circle or ellipse with the pen and it snaps when you lift. Undo restores your original ink. Recognition stays local and runs only at pen-up.
- Explicit shape tools are also available, with Shift constraints and the same undo/save/export behaviour as ink.
- Drop or paste screenshots; select, crop, restore, move, resize and annotate them. Attached ink follows movement and resizing.
- A capture tray for collecting image files, pasted images and screenshots before placing copies on boards. References persist separately for each library.
- Detailed heat, wave and Poisson examples with editable LaTeX equations, vector TikZ diagrams, boundary conditions and solution checks.
- A collapsible top shelf whose buttons read real filenames. Red is unfinished, green is finished; labels and symbols accompany the colours.
- Pin important ideas and move them earlier or later on the shelf. Preferences stay separate for each library.
- Local autosave, save/reopen, copies, archive, manual checkpoints and dated recovery history, restored as separate files.
- LaTeX and TikZ source editing, bounded image previews and vector PDF assets. No typesetting process remains running between renders.
- Content or selection export to PNG/PDF; copy an annotated selection as PNG; export a workspace preview with the desktop excluded.
- Menu-bar show/hide and movement between connected monitors. Hold Command–Shift–Space to temporarily use the app underneath; release to return.

This is a working preview, not the complete 84-feature product. Thumbnail cards, direct drag-to-status, OCR, handwriting-to-equation recognition and deleted-idea recovery remain planned. [Exact implementation status](docs/IMPLEMENTATION.md).

## Open and use

Unzip the download and open **Whiteboard.app**. A pencil icon appears in the macOS menu bar. The preview is ad-hoc signed, **not notarised by Apple**; macOS may require an explicit allowance in Privacy & Security for a downloaded copy. Building locally is also supported.

Click **Demo** on the shelf, or choose **File → Open demo workspace**. Six editable examples open in a separate demo library. Click **My ideas** to return to your previous board. Demo edits persist; reopening the demo does not create duplicate samples. Existing demo libraries gain the three PDE examples once, retaining earlier boards. No account or TeX installation is needed for these six examples.

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
| Collect references | Tray icon or File → Capture tray; Add files, Paste or Capture |
| Capture screenshot | Camera button; macOS permission may be required |
| Temporarily use the desktop | Hold Command–Shift–Space; release to return |
| Crop an image | Select it, C, drag the area to keep, then Return; Escape cancels |
| Restore a cropped image | Edit → Restore full image |
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
| Keep / recover a version | File → Save checkpoint / Recovery history; also Control-click a shelf card |
| Try / leave the demo | Demo / My ideas in the shelf |
| Change monitor | Screens or the menu-bar display actions |

### Your files

New libraries default to `~/Library/Application Support/Whiteboard/Ideas`, outside the app bundle. **File → Choose ideas folder…** selects another folder. The app creates `Unfinished`, `Finished` and `Archive` there. **Show ideas folder** in the menu bar opens it in Finder.

Pins and manual order are stored in macOS preferences for each library. In-app rename and status moves retain them; external Finder renames and moving the library to another Mac do not yet carry these preferences.

The capture tray stores its compressed references in `.capture-tray` within the selected library; placed copies live with their board. [Tray controls and limits](docs/CAPTURE-TRAY.md).

Each `.whiteboard` directory holds editable `board.json`, one `previous.json` revision, an `assets` folder and (after editing or checkpointing) a `history` folder. Reopen it through the shelf. Imported screenshots and typeset PDF/PNG assets are copied into the board, so moving their original source files does not break it. The original handwriting is retained. Cropping also retains the original screenshot in the editable file; it is not redaction. Cropped boards require version 0.4 or later. [Crop controls, exports and file compatibility](docs/CROPPING.md).

History retains up to 20 snapshots within a 64 MiB metadata budget. Automatic snapshots are spaced five minutes apart during edits; manual checkpoints are available at any time. [Recovery behaviour and limits](docs/RECOVERY.md).

**Saved locally** appears after a successful write. Save failures keep the in-memory work and offer a copy workflow. Saves commit completed gestures; an in-flight stroke commits on release, hide or quit. Keep backups of important work while using the preview.

### LaTeX and TikZ

Rendering needs a local TeX installation with `pdflatex`, `standalone`, `amsmath`, `amssymb` and TikZ. Saved maths remains viewable and exportable without that installation. No TeX distribution is bundled or downloaded automatically. [Examples, editing behaviour and supported packages](docs/MATHS.md).

## Built for a quiet desktop

The app uses AppKit and Core Graphics, with no webview or third-party Swift packages. Drawing responds to input and invalidation; saves and folder refreshes use one-shot scheduling. Screenshot previews share a 48 MiB decoded-image budget. Typesetting is an optional short-lived process on its own utility queue.

A 30-second check of the 0.5 build after its recovery workflow measured **129.56 MiB RSS**, with no increase in the process CPU counter at its available precision. This is a short visible-idle sample, not a battery-life or memory-reduction guarantee. [Measurements and remaining performance work](docs/VALIDATION.md).

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
