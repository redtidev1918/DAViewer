# REG-029: Clearer search history with tag records

Status: Verified (Code Verified; remote CI and device acceptance Unverified)

## Scope

Local history now retains the newest 100 unique query strings using the existing
queued store and JSON list format. Repeating a query moves it to the front;
existing records load without migration. Previously discarded records cannot
be recovered.

History uses Material list rows, separate from discovery tags: total count,
latest five initially, View all / Show less, individual delete buttons and a
confirmation before clearing all. Long queries wrap to two lines with a full
text tooltip. Tag records use a tag icon and retain the `#` prefix; selecting
one reuses the production submission handler to open the tag page.

Both submitted `#tag` searches and recommended/popular tag selections are
saved. Normal typing remains debounced and does not create history records.
Artwork/artist URLs still navigate without adding search history. History is
local and shares the 100-entry limit across keywords and tags.

## Design references

Reviewed on 2026-11-04: [Material search](https://m3.material.io/components/search/guidelines),
[Flutter's native search suggestions](https://api.flutter.dev/flutter/material/SearchAnchor-class.html),
and [YouTube's individual/whole-history management](https://support.google.com/youtube/answer/57711?hl=en).
The recent-five preview and 100-entry limit are DAViewer product choices.
No dependency, new storage schema or speculative timestamps were added.

## Evidence

- `search_history_store_test.dart`: 110 additions retain the newest 100;
  reloading after a repeat preserves order, uniqueness and the oldest retained
  entry. Existing invocation-order/disposal checks remain green.
- `search_history_screen_test.dart`: count, five-row preview, expand/collapse,
  delete without searching, repeat/reorder, confirmation cancel/confirm, and
  tag submission/button/popular-card/history navigation with persisted `#tag`
  records and no keyword feed request.
- `app_strings_test.dart`: Chinese and English controls/confirmation/count.
- Against the unchanged v0.7.1 store and screen, nine new behavior checks fail.
  The fixed tree passes analyze, format and all 658 tests with
  `DAVIEWER_VERSION=0.7.1` using Flutter 3.47.1.
- Native Flutter widget renders at 390×844 were inspected in light/dark themes
  with Chinese text and sample records. These are layout previews, not device
  or authenticated-account evidence.

The user resumed publication on 2026-11-04. Delivery is tracked in T-015;
v0.7.1 does not contain these changes. Remote CI and release acceptance are
pending for 0.7.2.
