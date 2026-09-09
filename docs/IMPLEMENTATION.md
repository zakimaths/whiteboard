# Framework implementation checklist

The approved 84-item framework is retained below. **Built** means the first native implementation exists; it does not mean every hardware, accessibility or failure case has been validated. **Partial** states the current limit. **Next** is planned, not simulated in the interface.

| ID | Requirement | Current state |
| --- | --- | --- |
| 01 | Desktop-visible whiteboard | Built: transparent overlay plus paper/dim choices |
| 02 | Instant writing | Built: blank writable canvas and global show/hide |
| 03 | Automatic saved-file updates | Built: one-shot save after completed edits; no fixed polling cycle |
| 04 | Save while working | Built: editable local packages; an in-flight stroke commits on release |
| 05 | Screenshot drag-and-drop | Built: image files, image paste and explicit import |
| 06 | General purpose | Built: free canvas with no imposed academic workflow |
| 07 | Playful, quiet, precise | Partial: restrained native surfaces, personal ink; advanced polish follows testing |
| 08 | Top shelf with filenames, green/red status | Built: reads real folder entries; labels and symbols accompany colour |
| 09 | Finished / Unfinished | Built: separate folders and shelf filters |
| 10 | Collapsible shelf | Built: compact header remains visible |
| 11 | Thumbnail cards | Next: filename buttons currently avoid image decoding |
| 12 | Selection on shelf | Built: selection saves as a separate editable idea with its assets |
| 13 | Whole board on shelf | Built: every saved board is a shelf file |
| 14 | Resume content and view | Built: reopens ink, text, images and viewport |
| 15 | Drag between statuses | Partial: button/menu status moves work; direct drag is next |
| 16 | Pin and rearrange | Built: Control-click to pin, move earlier/later; order retained per library across launches and in-app rename/status moves. Direct dragging and portable preferences next |
| 17 | Search titles and recognised text | Partial: filename search; recognised-content indexing is next |
| 18 | Quiet storage | Built: no reminders, deadlines or streaks |
| 19 | Archive and recover | Partial: Archive folder and return-to-status actions; deleted-item recovery is next |
| 20 | Monitor move from top control | Built: menu-bar action and Screens button |
| 21 | Visual monitor picker | Partial: named display list, dimensions and current-screen check; outlines next |
| 22 | Bring here | Built: menu-bar action uses the pointer’s display |
| 23 | Move entire workspace | Built: one window contains canvas, shelf and controls |
| 24 | Preserve work during monitor move | Built: document unchanged while window moves |
| 25 | Fit destination display | Partial: window fits the available screen; zoom is preserved, not automatically fitted |
| 26 | Monitor cycling shortcut | Next |
| 27 | Disconnect recovery | Built notification handler; physical unplug test still required |
| 28 | Shared shelf | Built: one library and one active workspace |
| 29 | Global show/hide | Built: Shift–Command–B registration |
| 30 | Fresh space | Built: scrolls below current content |
| 31 | No naming required | Built: unique Untitled idea filenames |
| 32 | Type/draw; zoom out; scroll for space | Built |
| 33 | Hold to interact underneath | Next: requires safe release/focus recovery |
| 34 | Background choices | Built: transparent, paper and dim |
| 35 | Remember setup | Partial: per-board background and viewport, saved colour/width and last-opened idea; toolbar placement next |
| 36 | Right mouse erase | Built: stroke eraser uses segment hit testing |
| 37 | Quick title | Built: Return opens filename rename; remapping next |
| 38 | Double-click clear | Next: current clear-ink action is explicit and undoable |
| 39 | Movable compact toolbar | Partial: compact tools exist; toolbar dragging/capture button next |
| 40 | Drawing helpers | Built: automatic freehand line/arrow/rectangle/circle/ellipse recognition at pen-up, with original-ink Undo and an off switch; explicit tools and Shift constraints also available. Multi-stroke recognition and broader shape vocabulary remain future work |
| 41 | Navigation | Partial: pan, zoom, reset, fresh space and fit-all; last-view history next |
| 42 | Select and organise | Partial: selection, moving, screenshot resizing, locking and duplication; grouping next |
| 43 | Separate clears | Partial: selection delete and clear ink; clear-everything control next |
| 44 | Undo/redo | Built: bounded 40-edit in-memory history; long-term history next |
| 45 | Temporary pointer ink | Next |
| 46 | Built-in capture | Built: user-initiated macOS capture action; permission flow and end-to-end capture still need validation |
| 47 | Paste image/text/link | Partial: images and plain text; URL-specific clickable objects next |
| 48 | Capture tray | Next |
| 49 | Repeat capture area | Next |
| 50 | Crop/resize images | Partial: proportional bottom-right-handle resizing; reversible cropping next |
| 51 | Attach ink to screenshot | Partial: ink starting on an image follows movement and proportional resizing; explicit attachment next |
| 52 | Lock reference | Built: menu action locks selected images against movement |
| 53 | Side-by-side arrangement | Partial: manual positioning; automatic alignment next |
| 54 | Duplicate reference/annotations | Built: duplicate a selection or make a fresh copy without annotations |
| 55 | Floating reference | Next |
| 56 | Source links | Next: paste as plain text currently |
| 57 | Ink and readable text | Next: original ink is preserved; no recognition engine active |
| 58 | Correct transcription | Next |
| 59 | Quiet processing status | Partial: real saving/saved/error state; recognition state next |
| 60 | Search inside work | Next |
| 61 | OCR image region | Next |
| 62 | Personal vocabulary | Next |
| 63 | Equation recognition | Next: separate evaluation required |
| 64 | Personal snippets | Partial: a selection can be saved as an idea; reusable insertion tray next |
| 65 | Meaningful marks | Next |
| 66 | Pen presets | Partial: four colours and a pen-width control, remembered between launches; named custom presets next |
| 67 | Named board locations | Next |
| 68 | Purposeful animations | Next: no idle animations in current build |
| 69 | Appearance controls | Partial: paper/dim/transparent with dots on paper; dark palette/preferences next |
| 70 | Portable preferences | Next |
| 71 | Sticky notes/checklists | Partial: typed text; dedicated note/checkbox objects next |
| 72 | Graph axes/grids | Partial: visual dot grid; reusable axes next |
| 73 | Fresh attempts | Partial: clear ink keeps reference images; named attempts next |
| 74 | Cover/reveal | Next |
| 75 | Saved views | Partial: last viewport persisted; named views next |
| 76 | Views as pages | Next |
| 77 | Continuous autosave | Built: saves independent of recognition, serialised off drawing thread |
| 78 | Editable board files | Built: JSON plus embedded compressed assets |
| 79 | Recovery history | Partial: one previous metadata revision, recovery as a separate copy and in-memory undo; longer history next |
| 80 | PNG/PDF export | Built: whole-content or selected-content PNG/PDF, rendered from source assets; PNG output has a pixel limit |
| 81 | Ink + transcription export | Next |
| 82 | Drag/copy finished work out | Partial: file export and copying a selected region as PNG; outbound drag next |
| 83 | Export preview | Partial: clean content export uses paper; separate workspace preview includes controls but no desktop; interactive export preview/options next |
| 84 | Local, no account | Built: no network calls or cloud recognition |

## Next engineering work

1. Harden the capture/save/shelf loop with prolonged-stroke recovery, large-library pagination tests, disk-full fault injection and external-keyboard shortcut checks.
2. Add direct drag-to-status, thumbnail previews only on demand, reversible image cropping and export options.
3. Add performance instrumentation and large-board fixtures before changing the renderer.
4. Implement recognition as an optional selection action, then evaluate whether pause-based recognition is useful within the power budget.

Do not enable all future features as background workers. Each addition must specify what event starts it, when it stops, what memory it retains and how it recovers from interruption.

## Added academic capability

- [x] Insert a LaTeX equation from editable source.
- [x] Insert a TikZ picture from editable source.
- [x] Reopen source with the Select tool and a double-click.
- [x] Retain source, PNG preview and PDF asset with the board.
- [x] Use the PDF asset for content exports.
- [x] Render only on explicit request; no idle typesetting process.
- [ ] Handwriting-to-LaTeX recognition remains separate future work.

See [LaTeX and TikZ](MATHS.md) for supported input and local TeX requirements.
