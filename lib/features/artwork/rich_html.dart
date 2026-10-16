import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../core/l10n/app_strings.dart';

String normalizeRichImageUrl(String source) {
  var trimmed = source.trim();
  if (trimmed.startsWith('//')) trimmed = 'https:$trimmed';
  if (trimmed.startsWith('/')) {
    return Uri.https('www.deviantart.com', trimmed).toString();
  }
  final uri = Uri.tryParse(trimmed);
  // DA's da-gif nodes can point to Giphy's MP4 rendition. Image codecs
  // cannot decode video; use the GIF rendition verified in the live specimen
  // documented in test/fixtures/artwork_description/README.md.
  if (uri != null &&
      (uri.isScheme('https') || uri.isScheme('http')) &&
      (uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com')) &&
      uri.path.startsWith('/media/') &&
      uri.path.endsWith('/giphy.mp4')) {
    return uri
        .replace(path: '${uri.path.substring(0, uri.path.length - 4)}.gif')
        .toString();
  }
  return trimmed;
}

/// Rich-text renderer with a cached, progressive and retryable implementation
/// for network images. flutter_html's default image renderer uses Image.network
/// directly, which redownloads across screens and offers no loading feedback.
final class RichHtml extends StatelessWidget {
  const RichHtml({
    required this.data,
    required this.strings,
    required this.onLinkTap,
    super.key,
  });

  final String data;
  final AppStrings strings;
  final void Function(String? url) onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Html(
      data: data,
      extensions: <HtmlExtension>[
        ImageExtension(
          handleAssetImages: false,
          handleDataImages: false,
          networkSchemas: const <String>{'', 'http', 'https'},
          builder: (extension) {
            final source = extension.attributes['src'];
            final normalized = source == null
                ? null
                : normalizeRichImageUrl(source);
            final uri = normalized == null ? null : Uri.tryParse(normalized);
            if (uri == null ||
                !(uri.isScheme('http') || uri.isScheme('https'))) {
              return Text(
                extension.attributes['alt'] ?? strings.imageLoadFailed,
              );
            }
            return _RichNetworkImage(
              url: uri.toString(),
              alt: extension.attributes['alt'],
              width: double.tryParse(extension.attributes['width'] ?? ''),
              height: double.tryParse(extension.attributes['height'] ?? ''),
              strings: strings,
            );
          },
        ),
      ],
      onLinkTap: (url, attributes, element) => onLinkTap(url),
    );
  }
}

final class _RichNetworkImage extends StatefulWidget {
  const _RichNetworkImage({
    required this.url,
    required this.strings,
    this.alt,
    this.width,
    this.height,
  });

  final String url;
  final String? alt;
  final double? width;
  final double? height;
  final AppStrings strings;

  @override
  State<_RichNetworkImage> createState() => _RichNetworkImageState();
}

final class _RichNetworkImageState extends State<_RichNetworkImage> {
  int _attempt = 0;

  Future<void> _retry() async {
    await CachedNetworkImage.evictFromCache(widget.url);
    if (mounted) setState(() => _attempt += 1);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final targetWidth = widget.width == null
        ? viewport
        : widget.width!.clamp(1, viewport).toDouble();
    final decodeWidth = (targetWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(320, 2048)
        .toInt();
    final ratio =
        widget.width != null &&
            widget.height != null &&
            widget.width! > 0 &&
            widget.height! > 0
        ? widget.width! / widget.height!
        : null;

    Widget loading() {
      final progress = const Center(child: CircularProgressIndicator());
      return SizedBox(
        width: targetWidth,
        child: ratio == null
            ? SizedBox(height: 180, child: progress)
            : AspectRatio(aspectRatio: ratio, child: progress),
      );
    }

    return CachedNetworkImage(
      key: ValueKey<String>('${widget.url}#$_attempt'),
      imageUrl: widget.url,
      width: targetWidth,
      fit: BoxFit.contain,
      memCacheWidth: decodeWidth,
      fadeInDuration: const Duration(milliseconds: 180),
      progressIndicatorBuilder: (context, url, progress) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          loading(),
          if (progress.progress != null)
            Text('${(progress.progress! * 100).round()}%'),
        ],
      ),
      errorWidget: (context, url, error) => SizedBox(
        width: targetWidth,
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.broken_image_outlined),
              const SizedBox(height: 4),
              Text(
                widget.alt?.trim().isNotEmpty == true
                    ? widget.alt!
                    : widget.strings.imageLoadFailed,
              ),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(widget.strings.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
