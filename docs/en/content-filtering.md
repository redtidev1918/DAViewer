# Content filters

Open Settings → Content filters to hide platform-marked AI works, exact tags, artist usernames or individual artwork URLs/IDs. Long-press an artwork card to hide it or its artist's works. Remove entries in Settings to undo.

Rules are local to this device and do not change DeviantArt follows, favourites or account blocks. They apply to recommendation, search, watched, gallery, collection and related-artwork lists. Notifications, download tasks, visit history and explicitly opened detail links are retained.

Tags and usernames match exactly, ignoring case. AI filtering uses only `isAiGenerated`, never tag guesses or the separate NoAI training permission. Missing tags/AI flags cannot be identified; old caches need a refresh to acquire missing flags. The recommendation cache retains observed AI flags.

Filtering preserves original pagination cursors. A fully hidden page offers “Load more artworks”. Removing a rule immediately restores already-loaded items.

## Implementation and validation

Rules are saved by atomic file replacement and serialized controller updates. DAKit 2.0.0 does not expose the AI flag on Artwork, so the app uses a read-only metadata compatibility index on existing DeviantArt Dio responses. It does not alter requests, responses, SDK mapping or session decisions, and sends no extra requests. Replace it when the SDK exposes the flag.

Real-world sample provenance is recorded in `test/fixtures/content_filter/README.md` (captured 2026-10-17). Tests cover flag semantics, persistence, concurrent edits, unblocking, late metadata updates and fully filtered pagination.
