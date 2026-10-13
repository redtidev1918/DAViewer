import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../../shared/widgets/app_feedback.dart';

Uri artistShareUri(String username) =>
    Uri.https('www.deviantart.com', '/${username.toLowerCase()}');

Uri folderShareUri({
  required String username,
  required String folderId,
  required bool isCollection,
}) => Uri.https(
  'www.deviantart.com',
  '/${username.toLowerCase()}'
      '/${isCollection ? 'favourites' : 'gallery'}'
      '/$folderId',
);

Uri tagShareUri(String tag) => Uri.https('www.deviantart.com', '/tag/$tag');

/// Opens the platform share sheet for a public DeviantArt link.
///
/// A native share target is preferable to silently copying a URL. If the
/// platform share bridge itself fails, the link is copied as a recoverable
/// fallback and the user is told what happened.
Future<void> shareDeviantArtLink(
  BuildContext context, {
  required Uri uri,
  required String title,
  required AppStrings strings,
}) async {
  final renderObject = context.findRenderObject();
  final origin = renderObject is RenderBox && renderObject.hasSize
      ? renderObject.localToGlobal(Offset.zero) & renderObject.size
      : null;
  try {
    await SharePlus.instance.share(
      ShareParams(
        uri: uri,
        title: title,
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
  } on Object {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!context.mounted) return;
    showFeedback(
      context,
      strings.shareFailedCopied,
      source: 'share-fallback',
      severity: AppNoticeSeverity.warning,
    );
  }
}
