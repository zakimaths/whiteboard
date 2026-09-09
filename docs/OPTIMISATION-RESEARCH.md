# Optimising a personal desktop whiteboard

## Recommendation

Build the first version as a native macOS application using AppKit, a single custom drawing view and local editable documents. Make work event-driven: input triggers drawing, an edit schedules a save, and a filesystem notification refreshes the shelf. Keep recognition optional and separate from persistence. The primary optimisation target is the cost of ordinary use, especially the time the application spends doing nothing.

The product is a desktop overlay for sudden ideas, screenshots, explanations and academic work. Its top shelf presents real filenames from Unfinished and Finished folders, with red and green status indications. An idea remains editable after completion. The board can move between displays, retain its view and extend through scrolling and zooming. These behaviours define the initial architecture; the longer feature list supplies the roadmap.

The recommended approach follows documented macOS mechanisms but is an engineering judgment, not a measured comparison of complete competing applications. Native software can still consume excessive memory or power. The acceptance programme must measure the finished implementation under representative workloads. “No errors or bugs” is a quality objective addressed by specific tests and recovery behaviour, not a property established by framework choice.

Documentation was checked on 9 September 2026. The local development environment has macOS 26.6.2, Swift 5.10 and command-line SDKs up to macOS 14.4. The first build targets macOS 13 or newer and avoids APIs that require a newer installed SDK. Apple’s older performance guides are marked as archived guidance; their event-driven principles are paired with current API documentation and local compilation. This report separates platform facts from proposed budgets and implementation recommendations.

## 1. Platform choice and operating cost

Electron uses a main process and renderer processes, with Chromium’s multiprocess architecture. Tauri separates its core process from operating-system webview processes. These documented architectures explain why either would add another UI runtime to this narrowly Mac-specific tool; they do not establish universal RAM or battery rankings.[^1][^2]

| Approach | Fit for this product | Trade-off |
| --- | --- | --- |
| AppKit and Core Graphics | Direct control of overlay windows, the menu bar, input and display placement | More native drawing and interaction work; Mac-specific |
| SwiftUI shell with AppKit drawing | Useful for substantial settings and library screens later | Two UI state systems must remain consistent |
| Tauri with a web canvas | Relevant if cross-platform support becomes a near-term requirement | Webview lifecycle and native integration remain part of the system |
| Electron with a web canvas | Broad web ecosystem and cross-platform tooling | More runtime machinery than the initial Mac-only workflow requires |

Choose AppKit for the first build. Do not add SwiftUI merely to render a few buttons, and do not start with a continuously running Metal renderer. Retain a small model module independent of AppKit so document behaviour and coordinate transforms can be tested without displaying a window. Revisit the drawing backend only if profiling shows a persistent drawing bottleneck that simpler changes cannot resolve.

Keep third-party dependencies at zero initially. This reduces the number of systems to configure, update and debug. It is not a claim that dependencies are intrinsically slow; it is a scope decision for a small native application whose first requirements are served by platform APIs.

## 2. Idle power and scheduling

Apple explains that unnecessary timers cause wakeups and can prevent low-power idle states. Its Mac energy guide explicitly recommends dispatch sources for file changes and event notifications for other system changes.[^3] The whiteboard should therefore have no permanent five-second housekeeping loop. The revised product requirement is automatic file updating, not mandatory recognition every five seconds.

Use one-shot, cancellable save work following completed edits. A short debounce combines nearby changes. If another edit arrives during a write, retain one newest pending state and save it when the active write finishes. Avoid an unbounded queue of obsolete document snapshots. Do not start a timer merely to ask whether that queue is finished; use completion callbacks.

The idle policy is simple: no canvas animation loop, no directory polling, no screenshot-folder surveillance, no periodic OCR and no background network requests. Shelf refreshes may be coalesced into a single update after a burst of filesystem notifications. A changing save indicator should settle into a static label. A hidden board should stop producing drawing work and release disposable image previews.

| Event | Appropriate response | Work that should stay inactive |
| --- | --- | --- |
| Pointer adds ink | Update the active stroke and affected region | Folder scans, OCR and whole-document image encoding |
| Edit completes | Schedule a local save | Repeated full-library searches |
| Shelf folder changes | Refresh filenames and statuses | Decoding every board and screenshot |
| App hides | Complete pending persistence and drop disposable previews | Canvas redraw and decorative animation |
| Display disconnects | Move the existing window to an available display | Creating a duplicate board |

The debounce duration is a tunable product parameter. Begin around 400 milliseconds after a completed content edit and a longer delay for viewport changes. Saving every pointer sample would increase work without guaranteeing survival of every in-flight hardware event. Flush completed content before switching documents, moving their files or quitting. Consider a bounded active-stroke checkpoint later if measured long-writing sessions show that saving only completed strokes leaves too much unsaved work.

## 3. Canvas rendering and expandable space

AppKit gathers invalidated drawing regions and can coalesce them before a redraw. Apple recommends limiting drawing to affected objects and generally avoiding immediate display calls that prevent this coalescing.[^4] A stroke should therefore invalidate its new segment, rather than the entire desktop. Pan and zoom legitimately invalidate the visible canvas because its relationship to the document changed.

Keep a fixed-size view over the current display. Store objects in document coordinates and transform them through a viewport origin and zoom. Scrolling changes the origin; zooming changes scale while preserving the document point beneath the pointer. This provides more working space without allocating an enormous offscreen bitmap or an enormous view.

Use cached bounds for rejection of offscreen content. Cache reusable drawing paths in a bounded collection. The current foundation may scan the object list to test those bounds; that is simpler and easier to validate than an early spatial database. If stress measurements show that the scan dominates, add a grid or tree keyed by object bounds and update only affected entries.

Avoid rebuilding all historical ink while appending to the active stroke. Keep the active path separate, append new samples as they arrive, and commit it as one editable object. Any reduction in near-identical samples must preserve the shape at the displayed scale. Do not simplify existing work destructively as an invisible optimisation.

Apple also recommends reducing unnecessary content updates, avoiding drawing while content is hidden, and limiting expensive opacity over changing content.[^5] Use simple, mostly opaque shelf and toolbar surfaces. The desktop can remain visible through the canvas as required, but full-screen animated blur is unnecessary. A plain-paper background is a useful option for visual clarity; the application cannot prevent another visible app or video from consuming its own power.

## 4. Screenshot memory and image storage

Compressed image file size is not decoded image memory. For a simple four-byte-per-pixel illustration, 3840 × 2160 pixels occupy about 31.6 MiB before other copies and framework overhead. Ten decoded screenshots can therefore be significant even when their PNG files look small. This calculation is an estimate of one pixel buffer, not a measurement of process memory.

Keep imported originals on disk inside the editable board package. Store their filenames and placement in the document. Decode display-sized previews lazily with Image I/O thumbnail creation, which exposes thumbnail options including a maximum pixel dimension.[^6] A screenshot can retain its original for future export while the canvas draws a bounded preview.

Use a serial image-decoding queue and a small maximum number of pending loads. Begin with at most four pending previews, a 1536-pixel maximum longest edge and a 48 MiB decoded-preview budget. Reduce the preview dimensions as the visible image count increases, and bound the number of simultaneous visible previews. Keep visible images in an explicitly managed cache: an automatically evicting cache can otherwise cause a load, eviction and redraw cycle. The preview budget is not a whole-app memory limit; window backing stores, paths, undo history, transient buffers and system libraries add memory outside it.

When the board changes or hides, discard preview references and invalidate outstanding generations so stale completions do not repopulate the cache. On memory-pressure notifications, release disposable caches first. Avoid repeatedly decoding a broken image on every redraw; retain an error result until the document or source changes.

Image import should validate file type, dimensions and byte size before decoding. The first build can impose explicit per-import limits and explain a rejected image. Larger imports can later use tiled or progressive processing. Never solve RAM pressure by silently degrading the stored original. Advanced export should decode at the required output size in bounded batches, rather than keeping every full-resolution original resident.

## 5. Automatic saving and recoverability

Use one editable package per idea:

```text
Ideas/
  Unfinished/
    Experiment notes.whiteboard/
      board.json
      previous.json
      assets/
        <image-id>.png
  Finished/
  Archive/
```

The visible package basename is the shelf filename. The containing folder supplies the status. `board.json` contains the version, object identities, strokes, typed text, image references and viewport. Compressed assets are stored once. `previous.json` retains a previous valid content revision; it is recovery assistance, not a complete backup system.

Foundation exposes atomic data writing, intended to replace a destination through an auxiliary write rather than stream partial data directly into the existing destination.[^7] Use atomic replacement for the document metadata and write imported assets before committing references to them. This does not make several separate files into a single filesystem transaction, nor establish survival under every power-loss scenario.

Serialize file operations on one storage queue. Never allow an older save to finish after a newer save and become the final state. Do not say “Saved” until the write succeeds. File errors should keep the in-memory work, stop automatic overwrites and offer a copy path. A close or quit action must wait for outstanding persistence or remain open if it fails.

Recognise external changes before overwriting. The foundation can compare a known file modification marker; later collaboration or cloud-folder support requires stronger coordination, conflict identity and multiwriter testing. If a file disappears, do not silently recreate it at its old path. If an external edit is detected, preserve it and allow the current in-memory work to be saved separately.

Use non-overwriting names such as `Idea 2.whiteboard` when a desired filename exists. Move complete packages between status folders and flush outstanding edits first. Reject invalid document versions and unsafe asset references. Keep deleted assets available while undo history or recovery metadata can still reference them; eventual garbage collection must understand those references.

## 6. A shelf that reads real folders

The shelf should begin with inexpensive filename buttons. Present Unfinished in red and Finished in green, accompanied by the words and a status symbol. This preserves the requested appearance while avoiding reliance on colour alone. Thumbnails can appear on deliberate inspection or for visible cards once a thumbnail cache exists; loading every board to render a closed shelf would contradict the low-memory objective.

Dispatch filesystem sources provide event handlers associated with a monitored file descriptor.[^8] Watch the small set of status folders and coalesce rename, addition and removal events. Enumerate filenames and lightweight attributes off the main thread. Because atomic replacement can change filesystem objects, watch parent directories rather than assuming a watch on one old file object remains sufficient forever.

Folder watching and document reloading are different jobs. The shelf can accurately reflect a filename rename without automatically replacing the board a person is editing. If a selected item was moved outside the app, handle that transition explicitly. Full support for arbitrary external editors should not be inferred from a working filename shelf.

For large libraries, virtualise or page the shelf. Show an initial bounded set and make additional matching results accessible; never silently omit the rest. Search filenames without opening every package. An index of recognised content can be built incrementally later, with an invalidation strategy and a storage budget. The current first build only needs filename search to verify the intended folder interaction.

Pinned order, drag-to-status, thumbnail previews and selection-to-idea behaviour should all operate on the same document identities. A card that represents a separate extracted idea should get its own document identity and embedded assets. A bookmark into a board should be clearly defined as a bookmark instead. Mixing the two without indicating ownership creates surprising editing and deletion behaviour.

## 7. Display movement and input reliability

Use one overlay window whose frame moves to the chosen display. Preserve the document and viewport independently of the display. The shelf, toolbar and canvas remain children of that one window, so they travel together. Do not duplicate the rendering pipeline or screenshot caches merely because a second screen is attached.

AppKit provides window collection behaviours and mouse-event pass-through controls, while the application can receive a notification when screen parameters change.[^9][^10][^11] Build the monitor menu from the current display list and respond to changes. Display layouts can contain negative coordinates and different scales; use the platform’s screen rectangles rather than assuming the primary display begins every arrangement.

The requested top control should be an app menu-bar item that opens monitor actions, rather than an attempted modification of the system Dock. Include “Bring here” and a display list in the first version. Add visual screen outlines once their selection and current-screen indication have been tested. If a display disconnects, retain the board and choose an available display.

Global show/hide should use a registered shortcut where possible. A temporary desktop-interaction key is more subtle: release may occur after focus has moved away. Before shipping hold-to-interact, verify release handling, app activation, permission refusal and recovery through the menu bar. An invisible click-blocking overlay or a permanently click-through board is a correctness failure, even if idle CPU looks excellent.

Separate spaces, fullscreen apps, Stage Manager, display scaling, sleep/wake and disconnect are a hardware/OS test matrix. The available APIs justify building these interactions, but the first machine’s successful launch does not establish compatibility with every arrangement. Avoid claiming complete monitor support until those cases have actually been exercised.

## 8. Recognition, search and future features

The original five-second reading idea should become an optional setting if retained. A continuously running OCR cycle conflicts with the updated emphasis on automatic saving and minimum idle power. Default recognition to an explicit selection action first, then consider recognition after a writing pause when there is changed content.

Vision provides text recognition requests, a speed/accuracy choice, language controls and custom vocabulary. The locally installed Vision headers also describe handwriting improvements in request revision 3.[^12] This supports evaluating local transcription; it does not guarantee accurate equations, faithful layout reconstruction or recognition of every handwriting style. Equation recognition needs its own representative test set and correction flow.

Use one recognition job at a time. Stamp each request with document identity and content revision. Discard a result if its source was erased or changed. Preserve the original ink, label extracted screenshot text separately, and do not make a recognition failure prevent a save. Only accepted results should participate in reliable search or paired export.

Reusable snippets should reference compact geometry and assets. Personal vocabulary should grow from approved corrections. Symbol-to-action mappings should initially be explicit selections or stamps, so ordinary mathematical notation does not accidentally issue commands. These choices keep the features predictable while avoiding an always-running model that tries to infer intent from every stroke.

Built-in capture should be user-triggered. ScreenCaptureKit documents single-frame capture through SCScreenshotManager.[^13] Its exact availability depends on the deployed OS and SDK. There is no reason to run a continuous screen stream for a feature whose goal is one screenshot. OS screenshot drag-and-drop provides a useful first path before adding screen-recording permissions and capture UI.

## 9. Performance budgets and verification

Budgets below are proposed acceptance targets. They must not be advertised as measured results until the release build and workload have been recorded. Resident memory, physical footprint and total memory attributable to all processes are different metrics; publish the metric actually collected. Similarly, a short CPU sample is not a battery-life measurement.

| Scenario | Initial objective | Method |
| --- | --- | --- |
| Empty board, idle | Near-zero sustained app CPU after startup settles; no recurring app timer work | Compare process CPU time over a quiet interval and inspect scheduling |
| Hidden board | No drawing; no new idle file writes; disposable images released | Observe process, document modification times and render instrumentation |
| Ordinary drawing | No visible dropped segments; short main-thread work | Scripted stroke replay plus interaction testing |
| 60 Hz drawing workload | Aim for drawing work below the 16.7 ms frame interval, leaving time for input/compositing | Release renderer instrumentation; distributions, not one best frame |
| 120 Hz hardware | Evaluate against 8.3 ms where applicable | Actual supported display and input tests |
| Image-rich board | Bounded preview cache and decode concurrency | Import representative large screenshots, pan, hide, reopen |
| Autosave | Successful writes shortly after completed edits; latest revision wins | Rapid edits, slow writes, document switches and file inspection |
| Large shelf | No decoding of all board contents; bounded visible controls | Hundreds/thousands of generated package names |

Apple recommends keeping expensive non-UI work away from the main thread and using responsiveness tools to diagnose hitches and hangs.[^14] Measure drawing, decoding, encoding and filesystem operations separately. A slow import should not make the pen unresponsive. A small average CPU value should not conceal a recurring main-thread stall.

The test suite should cover zoom anchor invariance, negative document coordinates, image/annotation movement, eraser geometry, encode/decode round trips, duplicate filenames, status moves, external edits, missing files, version rejection, invalid asset paths, recovery revisions and copied asset independence. UI checks add text focus, keyboard commands, hiding, export and actual shelf selection.

Add fault injection before public release: simulate a write failure, deny folder access, remove an image, corrupt metadata and terminate between asset creation and document commit. Verify that the last valid document remains readable. Review production error messages so every failure tells the person what is safe and how to keep their current work.

## 10. Implementation sequence

First establish a working native loop: open the overlay, draw or type, import a screenshot, scroll/zoom, save automatically, reopen a filename from the shelf, change its folder status and move the window through a display menu. This first build proves the central interaction and the persistence model together.

Then strengthen the same loop: input-loss recovery, bounded save scheduling during prolonged interaction, shelf pagination, thumbnail demand loading, direct drag-to-status, selected-content export, screenshot resizing with attached ink and a visible restore action. Profile the real workload before choosing spatial indexing, tile caching or a new rendering backend.

Introduce heavier features after the baseline is stable: local recognition, accepted-text search, equation experiments, capture permissions, full-resolution multipage exports and sophisticated personal symbols. The complete 84-item feature list remains the product roadmap. Performance-sensitive sequencing avoids putting unfinished background services underneath every early interaction.

The intended public promise is concrete: a quiet desktop whiteboard whose ideas live in ordinary folders, with fast capture and recoverable editable work. Evidence for low resource use should be published with a named build, machine, workload and method. Avoid a universal RAM number or a claim of being bug-free.

## 11. LaTeX and TikZ without an idle engine

The later academic requirement adds explicit source-based typesetting. TikZ is a LaTeX package, and the standalone class can crop a single equation or picture to its content.[^15][^16] The project therefore keeps a source string, a bounded preview and a PDF asset together. Viewing and exporting saved items need no compiler; editing runs local `pdflatex` only when Render is chosen. This is separate from handwriting recognition.

A local TeX installation was already available on the development Mac. Reusing it avoids bundling a large distribution or adding a remote rendering service. The tradeoff is that another Mac needs the relevant packages to create or modify a render. A portable TeX bundle could be evaluated later; it should be an explicit install, not part of idle startup.

The rendering queue is separate from saving and drawing. Only one render runs at a time, and it has input, output, CPU and wall-time bounds. The preview has an eight-million-pixel budget and 4096-pixel long-edge cap. The PDF asset is used for content exports to avoid enlarging a low-resolution preview. These are implementation decisions, not claims of a measured total-memory cap.

The TeX Live 2026 changes remove the effect of `openin_any`, so it would be incorrect to describe that setting alone as reliable file isolation.[^17] The implementation disables shell escape and uses an operating-system child sandbox to restrict file contents, writes, process execution and network access. It never compiles source simply because a board was opened. This mechanism requires compatibility testing on other macOS versions; failed sandbox setup must fail the render rather than silently weakening it.

The local integration checks rendered a quadratic formula and a TikZ arrow, retained source and PDF through copy/reopen, and rejected invalid source and a read outside the isolated working directory. Further measurement should include complex diagrams, cancellation, long repeated-edit sessions and transient compilation memory. The earlier idle samples do not measure compilation cost.

## Sources

[^1]: Electron. [Process Model](https://www.electronjs.org/docs/latest/tutorial/process-model). Live official documentation; accessed 9 September 2026. Used for the main/renderer process architecture.
[^2]: Tauri. [Process Model](https://v2.tauri.app/concept/process-model/). Version 2 official documentation; accessed 9 September 2026. Used for core/webview process separation.
[^3]: Apple. [Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html). Archived Energy Efficiency Guide for Mac Apps; accessed 9 September 2026. Used for wakeup costs and event-driven alternatives.
[^4]: Apple. [Optimizing View Drawing](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaViewsGuide/Optimizing/Optimizing.html). Archived View Programming Guide; accessed 9 September 2026. Used for invalidation, coalescing and dirty-region drawing.
[^5]: Apple. [Avoid Extraneous Content Updates](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html). Archived guide, page updated 13 September 2016; accessed 9 September 2026. Used for hidden drawing, opacity and unnecessary refresh costs.
[^6]: Apple. [CGImageSourceCreateThumbnailAtIndex](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)). Live Image I/O documentation; accessed 9 September 2026. Used for thumbnail decoding. Local ImageIO SDK declarations were also checked.
[^7]: Apple. [NSData.WritingOptions.atomic](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic). Live Foundation documentation; accessed 9 September 2026. Used for atomic-write semantics; the local NSData.h declaration was checked.
[^8]: Apple. [makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)](https://developer.apple.com/documentation/dispatch/dispatchsource/makefilesystemobjectsource(filedescriptor:eventmask:queue:)). Live Dispatch documentation; accessed 9 September 2026. Used for folder event notification APIs.
[^9]: Apple. [NSWindow.CollectionBehavior.canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications). Live AppKit documentation; accessed 9 September 2026. Window collection behaviour availability was also checked in the installed NSWindow.h SDK header.
[^10]: Apple. [NSWindow.ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents). Live AppKit documentation; accessed 9 September 2026. Used for input pass-through capability, not a claim that focus recovery is automatic.
[^11]: Apple. [NSApplication.didChangeScreenParametersNotification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification). Live AppKit documentation; accessed 9 September 2026. Used for reacting to display changes.
[^12]: Apple. [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest). Live Vision documentation plus installed VNRecognizeTextRequest.h; accessed 9 September 2026. Used for optional recognition capabilities and their limits.
[^13]: Apple. [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager). Live ScreenCaptureKit documentation; accessed 9 September 2026. Used for single-frame capture capability.
[^14]: Apple. [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness). Live Xcode documentation; accessed 9 September 2026. Used for main-thread responsiveness and profiling principles.

[^15]: PGF/TikZ. [Supported Formats](https://tikz.dev/drivers) and [Installation](https://tikz.dev/installation). Official project manual; accessed 9 September 2026.
[^16]: Martin Scharrer. [The standalone package manual](https://tug.ctan.org/macros/latex/contrib/standalone/standalone.pdf). CTAN package documentation; accessed 9 September 2026.
[^17]: TeX Users Group. [TeX Live bugs and updates](https://www.tug.org/texlive/bugs.html). Official distribution notes; accessed 9 September 2026. Used for the removal of openin_any behaviour in TeX Live 2026.
