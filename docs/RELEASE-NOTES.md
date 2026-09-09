# Whiteboard 0.4.0 · crop, restore and return

- Select a screenshot and press C to crop it. Drag the area to keep, then Return or Apply crop. Escape cancels. Edit → Restore full image restores the original. Crop edits support undo and survive save/reopen, copying, movement and resizing with attached ink.
- PNG and PDF content exports use the retained image region. Editable board files keep the full original asset. Cropping affects the image only; separate ink outside its bounds remains visible. LaTeX/TikZ vector objects are not cropped.
- Hold Command–Shift–Space to temporarily hide the board and use the app underneath; release to return. The shortcut is registered only while the board is visible, uses press/release events and adds no keyboard monitor or polling loop. Normal show/hide remains a recovery route.
- Saving now has executable fault-injection coverage for simulated full-disk failures during current/previous metadata writes, creation and asset import. Failed writes preserve existing saved content; a retry succeeds after the injected failure is lifted. Oversized metadata is rejected before writing.

**36 local checks pass: 33 core and 3 real LaTeX/TikZ checks.** Native interaction verified cropping, resize with attached ink, undo, reopening a saved crop, restoring the full image and cancelling a crop. A physical held-key test while clicking/scrolling another app, shortcut conflicts and sleep/wake still require dedicated testing.

Cropped boards use document format version 2 and require Whiteboard 0.4 or later. Existing version 1 boards remain readable. Cropping is reversible editing, not removal of private pixels from editable files. [Crop details](CROPPING.md).

**GitHub preview for Apple silicon; ad-hoc signed, not Apple-notarised.** The four editable demos require no TeX installation. Rendering new LaTeX/TikZ objects requires local TeX. The complete framework is still in progress; [feature status](IMPLEMENTATION.md), [demos](DEMOS.md) and [validation](VALIDATION.md) describe the exact limits.

---

# Whiteboard 0.3.0 · shapes, shelf and an editable demo

- Sketch naturally with Auto shapes enabled: clear lines, arrows, rectangles, circles and ellipses snap at pen-up. Undo restores the original stroke; Shift keeps one stroke freehand. Recognition is geometric and local, conservatively skips ambiguous input, and never runs as a background service.
- Explicit tools also draw lines, arrows, rectangles and ellipses. Hold Shift for 45° angles or equal sides; Escape cancels a shape in progress. Shapes use the existing ink format, including undo, screenshot attachment and exports.
- Pin shelf ideas and move them earlier or later within their pinned/unpinned group. Preferences survive restarts and in-app filename/status changes.
- Click Demo for four editable fictional examples in a separate library. My ideas restores the previous personal board. Demo edits persist without duplicating samples on each visit.
- Finished ideas show a Reopen action. The background control shows Desktop, Paper or Dim; the pen-width control restores the saved width.
- File URLs now retain consistent package identity after creation, directory enumeration, rename and status moves.

LaTeX/TikZ source editing remains available. These additions introduce no continuous rendering, thumbnail decoding or polling service. Recognition examines at most 20,000 input points, resamples to 128, and fits only once per completed pen stroke. Shape previews update on pointer/modifier events; shelf preferences are small per-library data; demo assets load only when requested.

**GitHub distribution only.** The Apple silicon app is ad-hoc signed and not notarised. No App Store submission, accounts or subscription. The sample ZIP and in-app demo do not require TeX; rendering new LaTeX/TikZ objects requires a local installation. Pin preferences currently live on the Mac, and are not transported with library files or migrated after external Finder renames.

This remains a working preview. [Full feature status](IMPLEMENTATION.md), [demo access](DEMOS.md), [validation](VALIDATION.md).

---

# Whiteboard 0.2.0 · native preview

A small desktop whiteboard for ideas, screenshots and working things out. This preview develops the core writing, saving and returning-to-an-idea loop. The full feature framework remains in the implementation checklist.

## Available now

- Transparent, dimmed or paper canvas; pen, highlighter, right-button eraser and typed notes.
- Scroll, pan, zoom and fit all content.
- Editable LaTeX equations and TikZ diagrams, with saved source, PNG previews and vector PDF assets. Local TeX is used only when rendering.
- Screenshot import, clipboard paste and an interactive macOS capture action.
- Select, move and resize a screenshot with attached ink. Duplicate a selection, or duplicate a reference without its annotations.
- A collapsible filename shelf with red unfinished and green finished states, search, archive and menu-based status changes.
- Serial local autosaving, external-change detection, one previous-save recovery copy, and a durable default library outside the app bundle.
- Whole-content or selected-content PNG/PDF export; copy a selection as PNG; export the app workspace without capturing the desktop.
- Connected-display switching and a menu-bar show/hide control.
- Optional fictional sample ideas for trying the app and making public demos.

## Distribution

The downloadable app is an **Apple silicon preview**, ad-hoc signed for local development. It is **not notarised by Apple**. macOS may block a downloaded copy until it is explicitly allowed in Privacy & Security. Building locally is also supported. The minimum deployment target is macOS 13; local interaction testing used macOS 26.6.2. Intel and older-macOS interaction testing remain outstanding.

No accounts, analytics, application network requests, background OCR or continuous screen recording. Optional typesetting requires a local TeX installation; saved renderings remain available without it. The capture action is user initiated and may require macOS permission. The app's workspace preview export renders its own views and does not require screen-recording access.

## Still to build or validate

This is not the complete 84-item release. Shelf thumbnails, direct drag-to-status, image cropping, configurable global shortcuts, OCR, equation recognition, snippets and longer-term recovery history remain planned. Physical monitor disconnects, fullscreen Spaces, long-session memory behaviour, disk-full fault injection and external global-shortcut interaction need further coverage. Interactive screen capture has not been validated end to end in this development environment.

See [validation](VALIDATION.md), the [full framework](IMPLEMENTATION.md) and [optimisation research](OPTIMISATION-RESEARCH.md) for exact evidence and limits. A passing test suite is not a claim that the app is bug-free.
