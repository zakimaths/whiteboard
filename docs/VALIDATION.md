# Native preview validation

## Build and environment

The release build was compiled on Apple silicon with Swift 5.10 and the installed command-line macOS SDK, on macOS 26.6.2. The application has a macOS 13 deployment target; compatibility on older operating-system versions has not yet been tested. No external dependencies were downloaded.

- App: `build/Whiteboard.app`, version 0.2.0.
- App bundle disk size at measurement: approximately 728 KiB. This excludes shared macOS frameworks, document data and development files.
- Profiled executable SHA-256: `936cadeecfbeb8480996aee8ca7c0e1ee7b9a365ca82a527d04980bafd05a707`. This identifies the earlier stress-tested build, not the 0.2.0 release executable. Later quality changes are described below.
- The local ad-hoc signature passed strict verification after removing Finder layout metadata from the generated bundle. This is a local development app, not a notarised public distribution.

## Automated correctness checks

`bash scripts/check.sh` passed **20 core checks, with no failures**:

1. Zoom preserves the document point under the cursor, including minimum and maximum zoom.
2. Moving an image moves its attached ink and leaves unrelated ink alone; locked images remain stationary.
3. The eraser tests actual line segments rather than erasing everything inside a broad bounding box.
4. Save/reopen preserves editable content, Unicode text, negative coordinates and viewport state.
5. Duplicate filenames do not overwrite existing boards.
6. Twenty-five successive autosaves do not conflict with the app’s own atomic writes.
7. Unsafe filename characters cannot escape the selected status folder.
8. Finished/unfinished transitions move the real package and keep it editable.
9. A detected external file edit prevents automatic overwrite.
10. A removed destination is not silently recreated.
11. The previous metadata revision remains readable after a normal save.
12. Unsupported versions, unsafe asset references and duplicate object identities are rejected.
13. Copied boards retain their assets after the original package is removed.
14. An asset-copy failure does not leave a broken new shelf item.
15. Preview dimensions fit the shared pixel budget for one through 128 visible images.
16. Image resizing transforms attached ink, respects locking and survives save/reopen.
17. Duplication remaps image attachments; a fresh attempt leaves the original intact.
18. Recovery creates a copy of a valid previous revision even when the current metadata is corrupt.
19. Invalid saves leave the current file unchanged and failed creation leaves no broken shelf item.
20. PNG/PDF export includes offscreen text and source images, and missing images fail explicitly. The exported PNG was visually inspected for text and image orientation.

These are executable checks against the core used by the app, using temporary files. They establish those cases, not an absence of all possible bugs. Full fault injection, disk-full handling, symlink hardening and multiwriter/cloud-folder concurrency need further coverage before a stable release.

## Optional typesetting checks

With `WHITEBOARD_TEX_CHECKS=1` and the installed TeX Live 2025 packages, **23 checks passed**: the 20 core cases plus real LaTeX rendering and copy/reopen with source/vector assets, real TikZ rendering, and rejection of invalid TeX and reads outside the isolated working directory. Both rendered images were visually inspected. The compiler leaves no persistent TeX service running. In the native app, both source editors were opened, their built-in examples rendered successfully, the results autosaved, and a double-click reopened the original TikZ source. A workspace preview was exported and inspected. This does not establish compatibility with all distributions, packages or future macOS sandbox changes.

## Native interaction checks

The actual application was opened and exercised through native controls. Typing, drawing a stroke, changing zoom and completing an idea produced saved document content. The resulting package was inspected on disk, and the content and viewport reopened after a restart. The filename moved to the actual Finished folder and appeared as a green finished button.

The board moved from the built-in 1710 × 1112 display to a connected 1920 × 1080 monitor and back. Its drawing and zoom were preserved. This verifies that connected-display pair; physical unplug/replug, sleep/wake, fullscreen Spaces and Stage Manager still require dedicated tests.

A PNG was imported through the native file picker and persisted in the package’s assets directory. The larger fixture then visibly rendered eight image previews. The 0.2.0 application was also exercised with proportional screenshot resizing, aligned attached ink, undo, copying the selected image and ink as PNG, creating a new board, pasting that image, autosave and restart. The pasted image reopened successfully. Filename buttons were checked after fixing unwanted compression of their titles. Raw file drag-and-drop, direct menu-bar “Bring here”, global shortcut conflicts and keyboard-only accessibility need further interaction coverage. The macOS screen-capture permission path is not yet fully tested.

Two issues found during interaction testing were corrected: stale file modification attributes after an atomic save, and a cache eviction/redecode loop that raised idle CPU during image display. The repeated-save and preview-budget checks cover the relevant core invariants; the final eight-image workload verified that previews remain visible after the cache change.

## Resource measurement

The release app loaded a labelled synthetic fixture with **2,000 strokes, 120,000 points, eight separate PNG assets and one text label**. The board metadata is approximately 4.4 MB. The original measured fixture used eight reference-page images and was retained only locally. The published `scripts/make_stress_fixture.py` now generates its own synthetic 708 × 1000 pixel grids; it reads no screenshots or personal files. It creates a separate `build/Performance Library` by default and refuses to overwrite an existing fixture. These replacement image bytes are not the exact original measured workload.

`scripts/profile_idle.py` reads the app’s process resident set size and cumulative user-plus-system CPU time using `ps`, every five seconds over a 30-second interval. Average CPU is calculated from the change in cumulative CPU time divided by elapsed wall time. CPU counters have limited precision. The raw samples are retained alongside this document.

| State | Observed resident memory | Average CPU, one-core basis | Duration |
| --- | --- | --- | --- |
| Visible stress board, settled after loading | 37.73–63.81 MiB | 0.1994% | 30.089 seconds |
| After Hide on the same stress board | 54.30 MiB | 0.2327% | 30.078 seconds |

Raw samples: [visible-stress-idle.json](benchmarks/visible-stress-idle.json), [hidden-stress-idle.json](benchmarks/hidden-stress-idle.json).

Resident memory is not physical footprint, peak allocation or the total memory cost of the desktop compositor. The system can page or compress memory during a sample. Other applications, WindowServer, cloud filesystem services and system frameworks can incur costs outside this process. These short measurements do not establish battery-life improvement or power consumption in watts.

The fixture file’s modification time and size were unchanged across the visible idle interval. Source inspection found no repeating application timers, screenshot streams, periodic OCR or network requests. The two scheduled delays are event-triggered one-shot save and folder-refresh work.

## 0.2 sample-workspace measurement

A second 30.11-second visible-idle check used the actual academic sample board on the 0.2 drawing/save engine. Observed RSS was **52.06–52.09 MiB**, with **0.2325%** average CPU on a one-core basis. This is a small one-image board, not the stress workload above. [Raw sample](benchmarks/v0.2-sample-idle.json).

The profiled executable was `18fe5a15bef6737da3be578160666a1efd1e1956a01b0336527ecf9116f90417`. The delivery build subsequently adds an on-demand workspace preview export and optional LaTeX/TikZ rendering. The recorded sample does not measure a typesetting session or the final process footprint. No periodic work was introduced. The same limitations on RSS, power and CPU-counter precision apply.

## Remaining performance work

- Measure drawing frame-time distributions during real continuous input; the current check confirms usable interaction, not a measured 60/120 Hz guarantee.
- Test longer sessions, repeated large-image imports and transitions between many image-rich boards.
- Record physical footprint, allocation growth, wakeups and energy impact with full Instruments tooling.
- Exercise library pagination with thousands of filenames and verify every page remains reachable.
- Test the preview budget at high bit depths and more than 128 simultaneously visible images; excess previews currently require zooming in.
- Add prolonged-stroke checkpoints and longer-term history. Queued image decoding now has cancellation tokens; previous-save recovery has an explicit UI action.

The first build is a working foundation for the approved framework. Its implementation checklist identifies planned features explicitly; it is not the complete 84-feature product.
