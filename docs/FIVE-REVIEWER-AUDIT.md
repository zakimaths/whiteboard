# Five-reviewer product audit

Date: 9 September 2026  
Reviewed release: Whiteboard 0.6.0 (`e945456`)

**Follow-up:** [0.7 fixes and dispositions](AUDIT-RESOLUTION.md). This document preserves the original review hypotheses. Native event testing disproved the panning claim: the original document anchor already stayed fixed throughout a drag. Other findings include both confirmed defects and feature suggestions; the follow-up distinguishes them.

Five independent reviewers examined the product from these perspectives:

1. STEM student using boards for problems, equations and revision.
2. PDE lecturer checking the mathematics and teaching value.
3. Senior native macOS engineer reviewing AppKit, lifecycle and resource use.
4. macOS accessibility specialist reviewing keyboard, VoiceOver and display access.
5. Adversarial QA engineer testing failure modes and edge cases.

The reviewers made no source or personal-library changes. The existing executable test suite passed 44 core checks in the independent engineering reviews. The release validation had already passed 44 core checks, three real LaTeX/TikZ checks and three independent numerical PDE check groups. No incorrect PDE solution or sign error was found.

## Priority 0: accessibility blockers

- **Expose board objects to VoiceOver.** The canvas is currently one generic accessibility element. Text, screenshots, ink, equations and diagrams need stable virtual accessibility children, useful roles, selection/lock state, screen frames and actions. Add a persistent accessible description to `BoardImage`, with curated spoken maths and diagram summaries for the PDE objects. Relevant code: `CanvasView.swift`, `Board.swift`, `PDEExamples.swift`.
- **Make existing objects operable from the keyboard.** A keyboard user can change tools and delete an already-selected object, but cannot traverse, select, move, resize or crop board objects. Add object navigation, a visible focus ring, arrow-key nudging, keyboard resize/crop actions and equivalent Edit-menu commands.
- **Offer semantic academic exports.** Current PDF exports are visual rather than tagged documents. Add accessible HTML/MathML or a structured text companion before describing exported PDFs as screen-reader accessible.

## Priority 1: correctness and data safety

- **Locked references can still be deleted or separated from their ink.** Movement and cropping respect `locked`, while deletion does not. Marquee movement can move attached ink away from a locked image. Treat a locked reference and its attachments as one protected unit for movement and deletion. Add regression tests for direct and marquee selection.
- **Hand/Option-drag panning accumulates the wrong delta.** Drag updates continue measuring from the initial mouse-down point without updating the stored point, so repeated events can accelerate and overshoot. Apply incremental deltas or calculate a single displacement from the original viewport.
- **Correct EXIF-oriented image geometry.** JPEG/HEIC frame dimensions use stored pixel width and height while decoding applies orientation. Portrait images stored with orientation metadata can receive a landscape frame and mismatched crop coordinates. Derive the board aspect ratio from oriented dimensions and test crop/export corners.
- **Do not permanently block saving after a transient error.** The current save failure path uses the same lasting block for conflicts and temporary I/O failures. Keep the hard block for verified external conflicts; add retry/backoff and a visible Retry action for recoverable failures.
- **Strengthen external-change detection.** Modification time alone can miss a replacement whose timestamp was preserved. Store a content hash, generation token, or inode/size/hash fingerprint and reject a stale save even when timestamps match.
- **Track capture and export during termination.** Quit currently waits for saves/imports but not an active screenshot helper or export. Track these tasks, cancel or finish them cleanly, and remove temporary files.
- **Bound a capture before reading it into memory.** Inspect the screenshot file size and dimensions before loading its full data. Report oversize captures instead of silently doing nothing.
- **Keep healthy capture references usable when one entry is corrupt.** Enumeration currently throws for the entire tray when one UUID package is malformed. Quarantine or report the damaged entry and return the valid entries.
- **Make demo creation fully idempotent.** A one-time marker and the empty-shelf shortcut can leave a partial demo set after interruption, while an individually deleted PDE example is not restorable. Give samples stable IDs, check each expected sample independently, and add “Restore original demos” without overwriting renamed or annotated copies.

## Priority 1: performance and visual quality

- **Avoid scanning the whole board on every pen redraw.** Partial drawing invalidations still iterate through every image, stroke and text item. Add a spatial index or screen-tile buckets updated when objects move. Measure frame times on large boards.
- **Reduce whole-document autosave I/O.** Frequent saves read the old JSON and rewrite both current and previous metadata. Use an adaptive debounce, flush on lifecycle events, and update the recovery copy only when its recovery interval is due. Consider filesystem clones where supported.
- **Refresh undersized cached previews after zooming.** Image previews cached for a smaller pixel budget can remain blurry when the budget grows. Track decoded dimensions and replace any cached preview below the requested resolution. This matters particularly for equations and diagrams.
- **Put a byte/point budget on undo.** Forty full `Board` snapshots can retain large copied arrays. Use command-based undo eventually; meanwhile cap history using an estimated byte or point count and stress-test a large board through repeated edits.
- **Reclaim unreferenced assets safely.** Deleted screenshots and repeated TeX renders accumulate files. Compact only after taking the union of assets referenced by the current board, previous revision, every recovery snapshot and any live undo state.

## Priority 1: academic workflow

- **Add resizable multiline text.** The current fixed single-line text field is too limited for definitions, derivations, pasted questions and lab notes. Store width and text layout in the document format and preserve older files.
- **Generalise attachments and groups.** Handwriting can attach to a screenshot, but typed text and LaTeX cannot. Let screenshots, text, equations and ink move and resize as a group.
- **Turn PDE references into revision activities.** Add a Practice copy that begins with the model and conditions while keeping hints, exact solution, energy check and discretisation independently revealable.
- **Add section anchors and view history.** Large boards need saved views or clickable section headings plus Back/Forward view navigation. The four PDE sections are a natural first implementation.
- **Improve the equation editor.** Use a persistent side editor with preview, snippets, clearer line-specific errors and a duplicate-before-edit action. Keep compilation explicitly user-triggered to preserve battery use.

## Priority 2: maths and diagram improvements

- Replace Poisson shorthand `A=A^T>0` with an explicit symmetric-positive-definite statement such as `A=A^T` and `z^TAz>0` for nonzero `z`.
- Explain that `r=f-Au_h` is an algebraic solver residual, distinct from truncation and discretisation error.
- Extend the numerical check to solve the Poisson system at several grid sizes and verify the displayed maximum-norm solution error, rather than checking only the exact-solution stencil residual.
- Keep centred residual sampling inside the stated time domain: start at positive time or use a one-sided derivative at `t=0`.
- State interior index ranges explicitly for every finite-difference scheme.
- Change “decays nine times faster” to “has nine times the decay rate.”
- Change “zero-temperature ends” to “zero relative-temperature boundary values.”
- Make the zero-displacement wave state more informative with a velocity or kinetic/strain-energy inset.
- Draw a clear zero-valued Poisson boundary strip or use grid nodes so cell-centre colours do not appear to contradict the boundary condition.
- Add a compact convergence table and a “verify this identity” task to each model.
- Compile all twelve bundled TeX fragments in release validation and detect source/render drift.

## Priority 2: interaction and display access

- Preserve keyboard and VoiceOver focus when shelf and tray rows update instead of rebuilding without focus restoration.
- Increase small fixed UI text and controls, offer an interface scale, enlarge the resize handle and test at 100%, 125% and 150%.
- Use dark semantic text for shelf cards and verify contrast in normal and Increase Contrast appearances; retain red/green as an accent and symbol.
- Stop forcing Aqua appearance. Support Dark Mode, Increase Contrast and Reduce Transparency with semantic colours.
- Announce meaningful accessibility changes such as recognition, failed saves and tray placement/removal, without announcing routine autosaves or every zoom tick.
- Add Undo for tray removal and restore focus to the next reference.
- Fit the viewport when moving to a smaller display without changing document coordinates.
- Identify screens by stable display IDs rather than menu array positions, which can change after a disconnect.
- Replace the single long Help paragraph with short task-based help and searchable commands.
- Add object ordering, alignment, distribution and grouping for academic diagrams and comparisons.
- Extend automatic shape recognition toward crossed coordinate axes, graph grids, braces, angle marks and labelled vector arrows.

## Priority 3: hardening and test coverage

- Aggregate multi-file drag results and report imported, skipped and failed counts instead of accepting the drop before background imports succeed.
- Prevent TeX completion from leaving orphan PNG/PDF files when the object is deleted or undone during rendering.
- Disable or guard mutating menu actions while background work blocks canvas input.
- Avoid creating undo checkpoints for empty clicks, no-op erases, no-op resizes or lock-without-selection.
- Decide and document whether annotations outside a screenshot crop should remain visible; test the chosen behavior in preview and export.
- Add injected screenshot-runner tests for success, cancellation, permission denial and quitting during capture.
- Add decode-memory/fuzz tests around the 64 MiB metadata limit and aggregate object counts.
- Exercise monitor unplug/reorder, sleep/wake, fullscreen Spaces, Stage Manager, multi-file tray selection and long image-heavy sessions on real hardware.
- Remove the duplicate ineffective sleep observer registered with the default notification center.

## Recommended implementation order

1. Fix panning, locked-object deletion/attachment behavior, oriented-image geometry, save retry and capture lifecycle.
2. Fix blurry preview upgrades, reduce redraw scanning and autosave I/O, then add byte-bounded undo and asset compaction.
3. Add multiline text, general object grouping, section anchors and Practice copies.
4. Build semantic canvas accessibility and keyboard object editing alongside those new object models, then add accessible academic exports.
5. Refine PDE wording, Poisson verification and diagrams; compile all twelve sources in release validation.
6. Finish contrast, appearance, focus restoration, tray undo and screen-transition hardening.

This review is a defect and opportunity inventory, not a claim that every item should ship in one release. The first two steps protect work and preserve smoothness; the next two make Whiteboard substantially more useful and inclusive for the intended academic niche.
