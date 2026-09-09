# Reversible screenshot cropping

Select one unlocked screenshot with V, then press C or choose Edit → Crop selected image. The full original appears while editing. Drag the area to keep and press Return or Apply crop. Escape or Cancel leaves the current image unchanged. Edit → Restore full image removes an applied crop. Undo and redo also work.

A crop changes the visible part of the image. It does not erase or clip separate ink. Attached annotations stay in place when cropping; moving or resizing the cropped image transforms its attached ink together with it. Resize uses the visible bottom-right handle and preserves proportions. Locked images and LaTeX/TikZ vector objects cannot be cropped.

## Saving and sharing

The editable `.whiteboard` package retains the full original asset and a small normalised crop rectangle. Reopening, duplicating or copying the board preserves both. This makes restoration possible and means an editable file still contains pixels hidden by the crop.

PNG and PDF content exports render only the retained bitmap pixels, rather than embedding the complete original image behind a PDF clipping mask. Separate ink outside the crop remains part of the board and its export. Review the actual content before sharing it; crop is not a document-redaction tool.

Boards with crops use format version 2 and need Whiteboard 0.4 or later. Old version 1 boards open normally in 0.4. A board that has used cropping stays version 2 after restoration so an older application cannot silently discard newer document data.

## Resource use

The app keeps the compressed original once and reuses the existing bounded preview cache. Cropping adds a rectangle to the document; it does not create another full-resolution preview, start a worker or run a background recognition model. Export decodes images on demand using the existing size limits.
