# Artwork access and media resolution

Related cards and artist galleries can use different sources for the same artwork. Access evidence must survive mapping so cards, detail views, and cached media agree.

| Dimension | States or facts | Meaning |
| --- | --- | --- |
| Content | `isMature` | Adult content; no payment or session verdict |
| Preview | `missing`, `blurred`, `clear` | Media response; a clear thumbnail is not an access grant |
| Restrictions | Mature login, purchase, subscription, blocked, deleted, login, unknown | A set: several restrictions can coexist |
| Resolution | `unresolved`, `checking`, `confirmed`, `retryableFailure` | Lookup progress, separate from authentication |
| Web session | `WebSessionStatusState` | Produced by the existing verification chain |

`ArtworkAccessEvidence` preserves the source, restrictions, unknown reason codes, and preview state. Sources are mapped lists, raw web lists, full web detail, and official OAuth detail. The parser recognizes `mature_loggedout`, explicit purchase-access fields, tier locks, and blocked/deleted fields. Other reason codes remain unknown. A browsing-settings restriction exists in the model but requires explicit evidence; the current parser does not infer it from an unknown code.

Resolution begins with a suspicious preview or restriction. Only identity-matched canonical evidence successfully committed to the media cache confirms a resolution. Failed requests, mismatched artwork, and inconclusive evidence lead to `retryableFailure`. Retrying starts a new lookup; session recovery resets previous results.

Clear, conclusive official detail takes priority for the main image, followed by conclusive full web detail, then list evidence. Failed OAuth lookup can fall back to complete web detail for the same author and artwork path. The app never edits blurred CDN URLs to obtain clear media.

Main-image access and web additional-page access remain separate. A clear OAuth main image does not erase the web session's `mature_loggedout` evidence for additional pages. Mature-login and payment restrictions are retained together when both are reported. Confirmed media survives later sparse-list writes, and cards read their image and access notice from the updated cache.

Login restrictions or unexplained blur can request web-session verification. A known payment restriction alone does not request a Cookie check. Only the verifier decides whether the session is anonymous; challenges and network failures retain their existing backoff behavior.

A confirmed web login or successful Cookie import increments the access epoch and invalidates related media providers. Cookie import also requests server verification. A response from an earlier epoch cannot update media, evidence, or lookup progress.

The web repository preserves raw reasons, the access model decides evidence precedence, the access controller owns lookup phases and epochs, the artwork store protects canonical media, providers coordinate requests and recovery, and the presentation layer selects notices and icons. Automated tests cover combined restrictions, unknown codes, both page formats, source boundaries, stale results, web fallback, and card updates. See [REG-013](../regressions/013-mature-related-preview.md) for the live-artwork verification limit.
