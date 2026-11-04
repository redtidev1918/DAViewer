/// Parses a DeviantArt URL into an in-app route so a pasted link can jump
/// straight to the artwork or artist.
final class DaLink {
  const DaLink._(this.route);

  /// A go_router route, e.g. `/artwork/1370691608` or `/artist/pyradk`.
  final String route;
}

/// Recognizes:
/// - `https://www.deviantart.com/<user>/art/<title>-<numericId>` → artwork
/// - `https://fav.me/<short>` or `https://www.deviantart.com/<short>` → artwork
/// - `https://www.deviantart.com/<user>` → artist
/// - `https://www.deviantart.com/<user>/gallery` → artist works
DaLink? parseDeviantArtUrl(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  final isDa = host == 'deviantart.com' || host.endsWith('.deviantart.com');
  final isFavMe = host == 'fav.me' || host.endsWith('.fav.me');
  if (!isDa && !isFavMe) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  // fav.me/<short> (or a bare shortcode path on deviantart.com).
  if (isFavMe && segments.length == 1) {
    return DaLink._('/artwork/${segments.first}');
  }

  // /<user>/art/<title>-<numericId>
  final artIndex = segments.indexWhere((s) => s.toLowerCase() == 'art');
  if (artIndex > 0 && artIndex + 1 < segments.length) {
    final last = segments.last;
    final numeric = RegExp(r'-(\d+)$').firstMatch(last)?.group(1);
    if (numeric != null && numeric.isNotEmpty) {
      // Carry the author along: the numeric-id resolver needs it to find the
      // deviation (and R18 ones in particular).
      final username = segments[artIndex - 1];
      return DaLink._('/artwork/$numeric?username=$username');
    }
  }

  // The artist page opens on its Works tab, matching a gallery root link.
  if (!isFavMe &&
      (segments.length == 1 ||
          (segments.length == 2 && segments[1].toLowerCase() == 'gallery'))) {
    final name = segments.first;
    if (!const <String>{
      'art',
      'users',
      'favourites',
      'gallery',
      'search',
    }.contains(name.toLowerCase())) {
      return DaLink._('/artist/$name');
    }
  }

  return null;
}
