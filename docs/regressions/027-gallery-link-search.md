# REG-027: Gallery links and search submission

Status: Partial

## Evidence and cause

- User report on 2026-11-04: `https://www.deviantart.com/cyberxiandou-vore/gallery`
  was not recognized. The parser accepted a single username segment but no
  gallery root suffix. A standalone Dart check against production code returned
  null before the fix and `/artist/cyberxiandou-vore` afterward.
- Independent URL evidence retrieved on 2026-11-04:
  [DeviantArt gallery page](https://www.deviantart.com/jointline-studios/gallery).
  The site's Gallery navigation uses the same `/username/gallery` shape.
  Fetching the reported account page failed; its contents and availability
  were not verified.
- SearchScreen displayed a non-interactive search icon and submitted all
  non-tag input as keywords. The home Open Link dialog already used the shared
  URL parser. ArtistScreen already opens on its Works tab.

## Change and checks

- Gallery root URLs reuse the artist Works route. Both search-button clicks and
  keyboard submission use the shared parser. Recognized links skip live keyword
  search. Folder-specific gallery paths remain unsupported.
- `test/da_uri_test.dart` covers the reported URL, a trailing slash, query
  parameters, the independently retrieved URL, and host/folder exclusions.
- `test/search_submission_test.dart` covers button and keyboard navigation,
  including a wait beyond the debounce with no keyword feed request.
- Native Dart checks passed for 12 URL cases; formatting passed for `lib test`
  (240 files unchanged; dependency-resolution warnings for flutter_lints).
- Flutter verification was initially Blocked by Environment. During release
  preparation on 2026-11-04 an isolated Flutter 3.47.1 toolchain was installed;
  old-code failures and fixed-code checks are recorded in [REG-028](028-global-user-lookup.md).
  Target-account loading, CI, release and device acceptance remain Unverified.
