import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:daviewer/features/artwork/artwork_description.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/rich_html.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes provider-relative rich image URLs', () {
    expect(
      normalizeRichImageUrl('//images.example.test/a.jpg'),
      'https://images.example.test/a.jpg',
    );
    expect(
      normalizeRichImageUrl('/assets/a.jpg'),
      'https://www.deviantart.com/assets/a.jpg',
    );
  });

  testWidgets('rich network images use the shared disk cache renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichHtml(
            data: '<p>before</p><img src="https://example.test/a.jpg">',
            strings: AppStrings.en,
            onLinkTap: _ignoreLink,
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text('before'), findsOneWidget);
  });

  test('rendition conversion is restricted to Giphy media', () {
    for (final url in <String>[
      'https://example.test/media/id/giphy.mp4',
      'https://giphy.com.example.test/media/id/giphy.mp4',
      'https://media4.giphy.com/media/id/giphy.gif',
      'https://media4.giphy.com/media/id/other.mp4',
    ]) {
      expect(normalizeRichImageUrl(url), url);
    }
    expect(
      normalizeRichImageUrl('//media4.giphy.com/media/id/giphy.mp4?x=1'),
      'https://media4.giphy.com/media/id/giphy.gif?x=1',
    );
  });

  testWidgets('captured description renders both Giphy embeds as images', (
    tester,
  ) async {
    final payload = jsonDecode(
      File('test/fixtures/artwork_description/web_page_giphy.json')
          .readAsStringSync(),
    ) as Map;
    final description = ArtworkDescriptionRepository.parseWeb(
      Map<Object?, Object?>.from(payload),
    );
    final markup =
        payload['deviation']['extended']['descriptionText']['html']['markup']
            as String;
    final nodes = jsonDecode(markup)['document']['content'] as List;
    final urls = nodes
        .where((node) => node['type'] == 'da-gif')
        .map((node) => node['attrs']['url'] as String)
        .toList();
    expect(urls, hasLength(2));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichHtml(
              data: description.html!,
              strings: AppStrings.en,
              onLinkTap: _ignoreLink,
            ),
          ),
        ),
      ),
    );
    final images = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(images, hasLength(2));
    expect(
      images.map((image) => image.imageUrl),
      urls.map((url) => url.replaceFirst('/giphy.mp4', '/giphy.gif')),
    );
    expect(
      find.textContaining('Cheekeh Cherreh Archive', findRichText: true),
      findsOneWidget,
    );
  });
}

void _ignoreLink(String? url) {}
