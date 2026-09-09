# Keep an earlier version

Choose **File → Save checkpoint** before trying a different approach or making a large edit. The current work is saved first, then a snapshot is kept. The shelf briefly reports **Checkpoint saved**.

To revisit it, choose **File → Recovery history…**, select a date and time, and click **Recover as copy**. A separate unfinished idea opens with “recovered” added to its filename. Your current idea stays intact. The recovered file includes its own copies of referenced screenshots and LaTeX/TikZ assets.

You can also Control-click any shelf card → **Recovery history…**. This does not need to open the current board first, so a readable snapshot can be recovered even if that board's current metadata is damaged. Missing or damaged snapshots and missing assets produce an error without replacing the original.

## What is kept

- Automatic snapshots preserve the previously saved board before the first edit is saved, then before a subsequent save when at least five minutes have elapsed since the latest snapshot. There is no timer running between edits.
- Manual checkpoints can be saved at any time and reset the five-minute spacing. These are dated snapshots, not named or permanently pinned versions.
- Each board keeps up to **20 snapshots within 64 MiB of history metadata**. Oldest snapshots are pruned after a new snapshot is written successfully. Large documents may retain fewer than 20. A new snapshot temporarily needs additional disk space before pruning.
- History stores JSON only and shares the original board's assets. It does not repeatedly copy screenshots. Referenced assets are copied when you recover into a new idea.
- History travels inside the `.whiteboard` package when the idea is renamed, moved between statuses or copied in Finder. The app's **Save a copy** and recovery commands create independent boards from the selected version, without cloning all of its history.
- The existing **Recover previous save as a copy** command and 40-edit in-memory Undo remain available.

A snapshot includes ink, text, image placement, crops, maths source and viewport state. Applying a newer edit does not rewrite existing snapshots. The list reads file metadata; it decodes only the version being recovered. History begins when this update is used and cannot reconstruct older missing versions.

## Limits

History belongs to the board package. It cannot recover a package deleted with all its snapshots, or protect against loss of the drive. Keep external backups of important work. In-progress strokes are not periodically checkpointed; they commit on release, hide or quit as before.

A history-write failure during autosave follows the app's existing save-error path: disk content remains intact, the in-memory edit remains available, and the interface asks you to save a copy. The core can retry after the storage failure is resolved; a dedicated in-app retry control remains future work. File-system races, physical disk failure, interrupted atomic writes and simultaneous cloud-folder writers are not exhaustively covered.

[Try it with fictional sample content](DEMOS.md) · [Validation](VALIDATION.md)
