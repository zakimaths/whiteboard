# Audit follow-up · Whiteboard 0.7

Whiteboard remains a general-purpose desktop canvas. The installed app ships three everyday demo boards and generic LaTeX/TikZ defaults. PDE examples live only in the optional GitHub sample materials; they are not bundled or injected into the app. The former demo library remains saved, including any user annotations.

## Confirmed errors addressed

| Area | Result |
| --- | --- |
| Locking | Locked images and attached ink remain together under selection movement/deletion; bulk Clear Ink respects them. Deliberate pen/eraser annotation is still possible. |
| Oriented images | JPEG/HEIC display dimensions respect EXIF orientation before placing the frame; source decoding and crop coordinates agree. |
| Save failures | Temporary Cocoa I/O errors receive two event-triggered retries. File → Retry saving remains available; actual external conflicts require a copy. |
| External changes | SHA-256 content fingerprints catch replacements even with preserved file timestamps. Identical saves perform no metadata writes. |
| Capture/export exit | Quit waits for exports and tracked imports, cancels an active capture helper and waits for its cleanup. Capture sizes are checked before full data loading; permission denial is explained. |
| Tray corruption | Damaged entries are reported individually. Healthy references can still be read or removed. Unknown storage blocks new additions until set aside. |
| Tray removal | Disk-backed Undo last removal survives restarts. Up to eight active and eight removed entries share 64 MiB; restore respects the active limit. Explicit emptying frees removed entries. |
| Demo installation | General examples use per-demo markers, preserve renamed/edited boards, retry incomplete installations and have an explicit restore-as-copies action. Unreadable unrelated boards cannot block restoration and remain untouched. |
| Canvas rendering | A spatial index yields visible object positions in drawing order. Small pen redraws avoid scanning every stored stroke; moves rebuild indexes on completion. |
| Preview quality | A changed preview budget invalidates undersized cached images so they are decoded at the new resolution. |
| Undo | Histories have count and estimated-byte budgets: 40 entries and a 32 MiB target per stack, retaining at least one usable checkpoint even if it alone exceeds the target. No-op clicks/erases/resizes do not consume a checkpoint. |
| Unused assets | Related TeX assets import transactionally. Explicit cleanup preserves current, previous, history and live undo references and only removes generated asset filenames. |
| Rendering edits | Editing is temporarily disabled during TeX compilation, preventing deletion/undo races with its result. No resident compiler runs. |
| File drops | One serial batch imports up to eight files and reports successful, failed and skipped counts. |
| Display switching | Menu items store stable display IDs; smaller destinations preserve the old view centre and reduce zoom without resizing document content. The minimum zoom remains 15%. |
| Busy commands | Mutating menu commands are disabled while work is blocking input. Lock actions require an actual selected image. |
| Appearance/focus | Controls follow system appearance; shelf text uses semantic label colour. Shelf/tray updates restore keyboard focus to a stable control or a sensible fallback. Resize handles are larger. |
| Multiline text | Notes support explicit line breaks with a native text editor; canvas hit testing and export share actual glyph measurements. |
| Keyboard access | Tab/Shift–Tab and menu actions traverse objects; arrows move, Option-arrows resize images, and Return edits. Crop controls work from the keyboard. |
| VoiceOver | Stable virtual objects expose notes, ink and author-described images with Select/Edit actions. This improves object access; a full assistive-technology usability study remains separate. |
| Accessible sharing | HTML export includes a visual overview plus readable notes, image descriptions and editable equation source. Handwriting is not automatically transcribed; PDF output remains a visual, untagged format. |

An integration check also caught coarse spatial cells selecting neighbours outside a marquee; exact bounds now filter candidates. Another verifies that undoing tray removal cannot exceed capacity.

## Correction to the audit

The reported accelerating hand-drag bug was a false positive. `world(event)` includes the changing viewport origin, so using the initial document anchor already compensates for every successive drag event. A native multi-event regression check confirms the grabbed document point remains under the pointer at different zoom levels. That behavior was preserved.

Crop annotations outside the retained image region are also intentional and were already documented: cropping clips the screenshot, while independent ink remains available. Cropping is not redaction and keeps the original image in editable files.

## GitHub mathematical materials

The academic showcase now states interior index ranges, positive definiteness, relative-temperature boundaries, decay-rate wording and the distinction between solver residual and discretisation error. Wave zero displacement and the Poisson boundary are clearer. A solved Poisson grid sequence verifies second-order solution error; residual sampling stays inside the time domain. All twelve TeX fragments have a regeneration check against their PNG previews, and prose descriptions accompany the equations and diagrams.

## Feature suggestions retained as future work

Grouping typed text/equations with screenshots, saved section views, cover/reveal practice copies, a persistent live-preview TeX side editor, automatic alignment, a broader STEM shape vocabulary and custom interface scaling are product additions rather than errors in shipped controls. They remain in the implementation checklist. PDE-specific teaching workflows will stay in GitHub examples, not become the app's default experience.

## Evidence and limits

The release validation covers 52 core checks, three real TeX checks, ten native interaction checks, three numerical PDE groups and regeneration of all twelve academic assets. Tests include actual temporary files, native mouse/key events, accessibility actions, save-failure injection and preview decoding. Physical monitor unplug/sleep/fullscreen combinations, system permission dialogs and a full VoiceOver session still need broader hardware/manual coverage. Passing these checks is not a claim that the product is free of every possible bug.
