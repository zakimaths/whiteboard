# Collect references before placing them

Open the tray icon below the camera, or choose **File → Capture tray**. **Add files** accepts one or several images. **Paste** takes an image from the clipboard. **Capture** temporarily hides Whiteboard and uses the existing interactive macOS screenshot action, returning the result to the tray.

Click a reference's name to place a copy near the centre of the current view. Select it to move, resize, crop or annotate it. The × sets its tray copy aside; placed copies and imported originals remain intact. **Undo last removal** restores a removed entry, including after a restart. **Empty removed references** permanently clears those removed entries after confirmation.

The tray closes without discarding its contents and restores its references after an app restart. Personal and demo libraries have separate trays. Switching ideas within a library keeps the same references available.

![Actual app with a placed heat-equation reference and the capture tray](demos/tray-workspace.png)

## Storage and limits

Each library keeps its tray in `.capture-tray`, outside individual board packages. It holds up to eight active and eight removed references; both share a 64 MiB compressed-data budget, with a 32 MiB per-image and 100-million-pixel limit. PNG, JPEG, TIFF, HEIC and GIF are accepted. No tray thumbnails are decoded. Rotated-image metadata is respected; placed images use the bounded board-preview cache.

A full tray rejects another reference without evicting an existing one. A failed write removes the incomplete entry created by that operation. Multi-file imports proceed in order: if a later file fails, earlier successful additions remain. Abrupt process termination can leave a hidden staging folder; crash cleanup and simultaneous external writers need further coverage. The stated data budget covers committed references, excluding temporary writes, metadata and filesystem overhead.

Damaged entries are reported individually. Healthy references remain usable; set a damaged entry aside before adding more so unknown storage cannot bypass the limit. Filename buttons place by clicking; direct tray dragging, thumbnails, renaming and repeat-capture remain future improvements. Native permission and physical multi-display capture coverage are documented in [validation](VALIDATION.md).
