import 'dart:convert';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/artwork_access_controller.dart';
import 'package:daviewer/features/artwork/artwork_access_presentation.dart';
import 'package:daviewer/features/artwork/artwork_access_state.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/features/artwork/artwork_web_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork _artwork({bool blurred = true}) => Artwork(
  id: '123',
  title: 'Work',
  author: const UserProfile(id: 'u', username: 'artist'),
  pageUri: Uri.parse('https://www.deviantart.com/artist/art/work-123'),
  isMature: true,
  media: <MediaAsset>[
    MediaAsset(
      id: 'preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse(
        blurred
            ? 'https://images.example.test/v1/blur_30/work.jpg'
            : 'https://images.example.test/clear.jpg',
      ),
    ),
  ],
);

ArtworkAccessEvidence _web(
  Map<Object?, Object?> raw, {
  bool blurred = true,
  ArtworkAccessSource source = ArtworkAccessSource.webList,
}) => ArtworkAccessEvidence.fromWeb(
  raw,
  _artwork(blurred: blurred),
  source: source,
);

Map<String, Object?> _raw() => <String, Object?>{
  'deviationId': 123,
  'title': 'Work',
  'url': 'https://www.deviantart.com/artist/art/work-123',
  'author': <String, Object?>{'userId': 'u', 'username': 'artist'},
  'isMature': true,
  'isBlocked': true,
  'blockReasons': <String>['mature_loggedout'],
  'media': <String, Object?>{
    'baseUri': 'https://images.example.test/image',
    'prettyName': 'work.jpg',
    'types': <Object?>[
      <String, Object?>{
        't': 'fullview',
        'w': 1000,
        'h': 750,
        'c': 'v1/fit/w_1000,h_750,blur_30/<prettyName>',
      },
    ],
  },
};

void main() {
  test('blur alone has an unknown cause and no paid lock', () {
    final evidence = _web(<Object?, Object?>{});
    expect(evidence.restrictions, isEmpty);
    expect(evidence.requestsSessionCheck, isTrue);
    final state = const ArtworkAccessState().observe(evidence);
    final notice = artworkAccessPresentation(_artwork(), state, AppStrings.zh)!;
    expect(notice.icon, Icons.help_outline);
    expect(notice.label, AppStrings.zh.previewRestrictionUnknown);
    expect(state.phase, ArtworkAccessPhase.unresolved);
  });

  test('NSFW logged-out reason does not become generic blocked or paid', () {
    final evidence = _web(<Object?, Object?>{
      'isBlocked': true,
      'blockReasons': <String>['mature_loggedout'],
    });
    expect(evidence.restrictions, <ArtworkRestriction>{
      ArtworkRestriction.matureLogin,
    });
    expect(evidence.requestsSessionCheck, isTrue);
    final notice = artworkAccessPresentation(
      _artwork(),
      const ArtworkAccessState().observe(evidence),
      AppStrings.zh,
    )!;
    expect(notice.icon, Icons.visibility_off_outlined);
    expect(notice.label, AppStrings.zh.matureLoginRequired);
  });

  test('purchase and subscription can coexist with NSFW login restriction', () {
    final evidence = _web(<Object?, Object?>{
      'blockReasons': <String>['mature_loggedout'],
      'premiumFolderData': <String, Object?>{'hasAccess': false},
      'tierAccess': 'locked-subscribed',
    });
    expect(evidence.restrictions, <ArtworkRestriction>{
      ArtworkRestriction.matureLogin,
      ArtworkRestriction.purchase,
      ArtworkRestriction.subscription,
    });
    final notice = artworkAccessPresentation(
      _artwork(),
      const ArtworkAccessState().observe(evidence),
      AppStrings.zh,
    )!;
    expect(notice.label, contains(AppStrings.zh.matureLoginRequired));
    expect(notice.label, contains(AppStrings.zh.viewLockedSubscription));
  });

  test('a known paid gate alone does not request a cookie check', () {
    final evidence = _web(<Object?, Object?>{
      'premium_folder_data': <String, Object?>{'has_access': false},
    });
    expect(evidence.requestsSessionCheck, isFalse);
    expect(evidence.restrictions, contains(ArtworkRestriction.purchase));
  });

  test('unknown reason codes remain unknown even with a clear thumbnail', () {
    final evidence = _web(
      <Object?, Object?>{
        'isBlocked': true,
        'blockReasons': <String>['future_reason'],
      },
      blurred: false,
      source: ArtworkAccessSource.webDetail,
    );
    expect(evidence.unknownReasons, <String>['future_reason']);
    expect(evidence.restrictions, <ArtworkRestriction>{
      ArtworkRestriction.unknown,
    });
    expect(evidence.grantsAccess, isFalse);
    expect(evidence.isConclusive, isFalse);
  });

  test('OAuth main access does not grant access to web additional pages', () {
    var state = const ArtworkAccessState().observe(
      _web(<Object?, Object?>{
        'blockReasons': <String>['mature_loggedout'],
      }),
    );
    state = state.observe(
      ArtworkAccessEvidence.fromArtwork(
        _artwork(blurred: false),
        source: ArtworkAccessSource.officialDetail,
      ),
    );
    expect(state.mainRestrictions, isEmpty);
    expect(state.mainEvidence!.grantsAccess, isTrue);
    expect(state.webRestrictions, contains(ArtworkRestriction.matureLogin));
  });

  test('missing or blurred canonical media never grants access', () {
    final blurred = ArtworkAccessEvidence.fromArtwork(
      _artwork(),
      source: ArtworkAccessSource.officialDetail,
    );
    expect(blurred.isConclusive, isFalse);
    final missing = ArtworkAccessEvidence.fromArtwork(
      _artwork().copyWith(media: const <MediaAsset>[]),
      source: ArtworkAccessSource.officialDetail,
    );
    expect(missing.preview, ArtworkPreviewState.missing);
    expect(missing.grantsAccess, isFalse);
  });

  test(
    'lookup phases retry and reject all results from an earlier session',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(artworkStoreProvider.notifier);
      final access = container.read(artworkAccessControllerProvider.notifier);
      store.putAll(<Artwork>[_artwork()]);
      final epoch = access.beginResolution('123');
      expect(access.forId('123').phase, ArtworkAccessPhase.checking);
      access.resolutionFailed('123', epoch);
      expect(access.forId('123').phase, ArtworkAccessPhase.retryableFailure);
      access.beginResolution('123');
      access.resetSession();
      final clear = _artwork(blurred: false);
      final evidence = ArtworkAccessEvidence.fromArtwork(
        clear,
        source: ArtworkAccessSource.officialDetail,
      );
      expect(
        store.setResolvedMedia(clear, evidence: evidence, epoch: epoch),
        isFalse,
      );
      access.resolutionFailed('123', epoch);
      access.observe('123', evidence, epoch: epoch);
      expect(access.forId('123').phase, ArtworkAccessPhase.unresolved);
      expect(store.byId('123')!.media.single.uri!.path, contains('blur_'));
      final nextEpoch = access.beginResolution('123');
      expect(
        store.setResolvedMedia(clear, evidence: evidence, epoch: nextEpoch),
        isTrue,
      );
      expect(access.forId('123').phase, ArtworkAccessPhase.confirmed);
      store.putAll(<Artwork>[_artwork()]);
      expect(store.byId('123')!.media.single.uri, clear.media.single.uri);
    },
  );

  test('streamed related pages preserve raw restriction reasons', () {
    final cache = <String, Object?>{
      'relatedContent': <String, Object?>{
        'relatedContent': <Object?>[
          <String, Object?>{
            'contentType': 'recommended',
            'deviations': <Object?>[_raw()],
          },
        ],
      },
    };
    final html =
        'window.__RCACHE__ = JSON.parse(${jsonEncode(jsonEncode(cache))});';
    final batch = ArtworkWebRepository.parseRelated(html, deviationId: '999');
    expect(batch.artworks.single.id, '123');
    expect(batch.evidence['123']!.restrictions, <ArtworkRestriction>{
      ArtworkRestriction.matureLogin,
    });
  });

  test('legacy normalized pages preserve reasons without crossing artwork IDs', () {
    final state = <String, Object?>{
      '@@entities': <String, Object?>{
        'deviation': <String, Object?>{
          '123': _raw(),
          '456': <String, Object?>{
            'blockReasons': <String>['other'],
          },
        },
        'user': <String, Object?>{},
      },
      '@@DUPERBROWSE': <String, Object?>{
        'currentBiMetadata': <String, Object?>{
          '999': jsonEncode(<Object?>[
            <String, Object?>{
              'type': 'relatedContent',
              'blocks': <Object?>[
                <String, Object?>{
                  'contentType': 'gallery',
                  'deviations': <Object?>[
                    <String, Object?>{'deviationid': 123},
                  ],
                },
              ],
            },
          ]),
        },
      },
    };
    final html =
        'window.__INITIAL_STATE__ = JSON.parse(${jsonEncode(jsonEncode(state))});';
    final batch = ArtworkWebRepository.parseRelated(html, deviationId: '999');
    expect(batch.evidence.keys, <String>['123']);
    expect(
      batch.evidence['123']!.restrictions,
      contains(ArtworkRestriction.matureLogin),
    );
  });
}
