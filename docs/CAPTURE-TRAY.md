# Collect references before placing them

Open the tray icon below the camera, or choose **File → Capture tray**. **Add files** accepts one or several images. **Paste** takes an image from the clipboard. **Capture** temporarily hides Whiteboard and uses the existing interactive macOS screenshot action, returning the result to the tray.

Click a reference's name to place a copy near the centre of the current view. Select it to move, resize, crop or annotate it. The reference stays in the tray for another board or attempt. The × beside a reference removes its tray copy; copies already placed on boards and files you originally imported remain intact. Removal has no tray-specific Undo yet.

The tray closes without discarding its contents and restores its references after an app restart. Personal and demo libraries have separate trays. Switching ideas within a library keeps the same references available.

![Actual app with a placed heat-equation reference and the capture tray](demos/tray-workspace.png)

## Storage and limits

Each library keeps its tray in a hidden `.capture-tray` folder, outside individual board packages. It holds up to eight references and 64 MiB of compressed image data, with a 32 MiB limit per image and a 100-million-pixel dimension limit. PNG, JPEG, TIFF, HEIC and GIF files are accepted. It stores original compressed bytes and small metadata files; no tray thumbnails are decoded or retained. Placed images use the existing bounded board-preview cache.

A full tray rejects another reference without evicting an existing one. A failed write removes the incomplete entry created by that operation. Multi-file imports proceed in order: if a later file fails, earlier successful additions remain. Abrupt process termination can leave a hidden staging folder; crash cleanup and simultaneous external writers need further coverage. The stated data budget covers committed references, excluding temporary writes, metadata and filesystem overhead.

Filename buttons currently place by clicking. Dragging directly from the tray, thumbnails, reference renaming, removing with Undo and repeating the previous capture area remain future improvements. macOS screen-recording permission and end-to-end screen capture still need dedicated validation; file import, paste, placement, removal and restart persistence were exercised in the app.
