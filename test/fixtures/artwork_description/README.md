# Artwork description protocol evidence

## Giphy video rendition regression (2026-10-16)

`web_page_giphy.json` was independently extracted from the public page's
`window.__INITIAL_STATE__` descriptionText on 2026-10-16 (anonymous HTTP 200):
https://www.deviantart.com/biggerbutton/art/My-Belly-Button-Explained-----CheekehCherreh-ORIGINS-%5Bremoved%5D-1393595109
Only the description and artwork ID are retained, arranged in the init envelope
used by the description parser; no session data is included.

Both actual `da-gif.attrs.url` values end in `/giphy.mp4`. Live GETs returned
HTTP 200, `video/mp4`, with `ftypisom` in the header. Changing only that filename
to `giphy.gif` returned HTTP 200, `image/gif`, and `GIF89a` magic for both IDs:
`xT9DPplLC0JojWdgyI` (550 x 310) and `3osxY48u8kTJbbOQvK` (480 x 244).
The original full URLs are preserved in the fixture. This supports the narrow
Giphy rendition conversion, not arbitrary MP4-to-GIF rewriting.

Captured on 2026-10-14 from public DeviantArt pages and anonymous HTTP 200
`/_puppy/dadeviation/init` responses. No account credentials or private artwork
were used. Anonymous Cookie/CSRF values and all unrelated response fields were
discarded; they must never be committed or logged.

- `web_init_writer.json`: public page
  https://www.deviantart.com/elsevilla/art/Purple-sad-819241297 ; init query
  `deviationid=819241297&username=elsevilla&type=art&include_session=false&mature_content=true`.
  The actual `deviation.extended.descriptionText.html` has `type=writer` and
  nonempty markup containing plain text (no HTML tags). Its excerpt is empty.
- `web_init_tiptap.json`: public page
  https://www.deviantart.com/nightslayer244/art/Beautiful-Zelena-1204523558 ; init
  query `deviationid=1204523558&username=nightslayer244&type=art&include_session=false&mature_content=true`.
  Actual markup is a JSON string with `version`, `document`, and `features`,
  including paragraph, text, mention, and emote nodes. The mentioned account
  name and numeric ID were replaced with ExampleArtist / 123456789. Field
  structure, empty paragraphs, and feature metadata are retained.

Both response samples retain only `deviationId`, `extended.deviationUuid`, and
`extended.descriptionText`. They were fetched independently of the SDK parser.
No live empty-description specimen was captured; tests modifying a specimen to
empty or malformed content are explicitly derived robustness cases.

## Official API contract

Authoritative documentation fetched on 2026-10-14 (HTTP 200):

- https://deviantart.readme.io/reference/deviation_metadata
- https://deviantart.readme.io/reference/deviation_content

Their embedded OpenAPI 3.1.0 schema identifies API version `1.20240701` and
server `https://www.deviantart.com/api/v1/oauth2`.
`GET /deviation/metadata` requires a `deviationids` array of strings and returns
required `metadata`, an array whose items require `deviationid` and
`description` (both strings), among other fields. `GET /deviation/content`
instead describes full content fields including `html` and `css`. The metadata
schema does not specify HTML semantics for `description`; tests should allow
both plain strings and HTML without claiming a live metadata capture.

The legacy `www.deviantart.com/developers/http/v1/...` links currently redirect
to a default Daily Deviations documentation page, so they are not evidence for
the metadata contract. No authenticated metadata response was captured.
