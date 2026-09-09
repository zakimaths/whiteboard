# Draw first, tidy on lift

**Auto shapes is on by default.** Use the ordinary Pen. Sketch one clear shape in a continuous stroke, then lift the pen or mouse button. A confident match becomes a line, arrow, rectangle, circle or ellipse. The checkbox shows the recognised name.

- Undo once restores the original freehand stroke; Undo again removes it. Redo reapplies the snap. This uses the current session’s bounded undo history.
- Hold Shift while drawing a pen stroke to preserve freehand for that stroke. Switch Auto shapes off to keep all pen strokes untouched; that preference survives relaunches.
- Highlighter strokes are left alone. Shapes remain normal ink for moving, erasing, copying, image attachment, saving and exports.
- Explicit shape tools remain available in the toolbar and with L/A/R/O. Shift constrains those tools to 45° angles or equal sides.

The current recogniser fits geometry locally at pen-up. It does not use a cloud model, OCR, an always-running classifier or a timer. It skips strokes longer than 20,000 input points and fits at most 128 resampled points. Very small marks are skipped to reduce interference with handwriting. Geometry that is unclear stays freehand.

Supported cases include rotated boxes and single-stroke arrows drawn tail → tip → one wing → tip → the other wing (or the reverse). Separate shaft and arrowhead strokes, triangles, arbitrary polygons and semantic diagram recognition are not yet supported. Ellipse fitting currently favours upright ellipses. Recognition can still miss a rough shape or misinterpret a mark; use the one-stroke override or Undo when needed.
