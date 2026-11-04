import 'package:daviewer/core/data/da_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Reported by the user on 2026-11-04. Independently checked the /user/gallery
  // shape against https://www.deviantart.com/jointline-studios/gallery that day;
  // the reported account page itself could not be fetched.
  test('parses the reported gallery URL to the artist works route', () {
    for (final suffix in ['', '/', '?sort=newest']) {
      expect(
        parseDeviantArtUrl(
          'https://www.deviantart.com/cyberxiandou-vore/gallery$suffix',
        )?.route,
        '/artist/cyberxiandou-vore',
      );
    }
    expect(
      parseDeviantArtUrl('https://www.deviantart.com/jointline-studios/gallery')
          ?.route,
      '/artist/jointline-studios',
    );
  });

  test('does not turn other hosts or gallery folders into artist roots', () {
    expect(parseDeviantArtUrl('https://fav.me/user/gallery'), isNull);
    expect(parseDeviantArtUrl('https://example.com/user/gallery'), isNull);
    expect(
      parseDeviantArtUrl('https://www.deviantart.com/user/gallery/123'),
      isNull,
    );
  });

  test('parses an artwork URL to an artwork route with the author', () {
    final link = parseDeviantArtUrl(
      'https://www.deviantart.com/user/art/title-123456789',
    );
    expect(link?.route, '/artwork/123456789?username=user');
  });

  test('parses a fav.me shortcode', () {
    expect(
      parseDeviantArtUrl('https://fav.me/abc123')?.route,
      '/artwork/abc123',
    );
  });

  test('parses a bare username to an artist route', () {
    expect(
      parseDeviantArtUrl('https://www.deviantart.com/someuser')?.route,
      '/artist/someuser',
    );
  });

  test('rejects non-DeviantArt hosts', () {
    expect(parseDeviantArtUrl('https://example.com/art/1'), isNull);
  });

  test('rejects reserved top-level paths as artists', () {
    expect(parseDeviantArtUrl('https://www.deviantart.com/gallery'), isNull);
  });

  test('returns null for empty input', () {
    expect(parseDeviantArtUrl('   '), isNull);
  });
}
