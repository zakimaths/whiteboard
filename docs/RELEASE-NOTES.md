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
