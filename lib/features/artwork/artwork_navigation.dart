import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'artwork_store.dart';

/// The immutable feed context carried by an artwork detail route.
///
/// Keeping the sequence on the route (instead of in one global mutable queue)
/// means opening a related work and then going back restores the original
/// gallery sequence correctly.
final class ArtworkBrowseSession {
  ArtworkBrowseSession(Iterable<String> ids)
    : ids = List<String>.unmodifiable(_deduplicate(ids));

  factory ArtworkBrowseSession.fromArtworks(Iterable<Artwork> artworks) =>
      ArtworkBrowseSession(artworks.map((artwork) => artwork.id));

  final List<String> ids;

  String? previousOf(String id) => _neighbor(id, -1);

  String? nextOf(String id) => _neighbor(id, 1);

  ArtworkNavigationTarget? target(
    String id,
    ArtworkNavigationDirection direction,
  ) {
    final targetId = switch (direction) {
      ArtworkNavigationDirection.previous => previousOf(id),
      ArtworkNavigationDirection.next => nextOf(id),
    };
    if (targetId == null) return null;
    return ArtworkNavigationTarget(
      artworkId: targetId,
      routeContext: ArtworkRouteContext(session: this, direction: direction),
    );
  }

  String? _neighbor(String id, int offset) {
    final index = ids.indexOf(id);
    if (index < 0) return null;
    final target = index + offset;
    if (target < 0 || target >= ids.length) return null;
    return ids[target];
  }

  static List<String> _deduplicate(Iterable<String> ids) {
    final seen = <String>{};
    return <String>[
      for (final id in ids)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
  }
}

enum ArtworkNavigationDirection { previous, next }

/// Route metadata for an artwork opened from a feed. The direction is null on
/// the first open and is set for subsequent previous/next transitions.
final class ArtworkRouteContext {
  const ArtworkRouteContext({required this.session, this.direction});

  final ArtworkBrowseSession session;
  final ArtworkNavigationDirection? direction;

  static ArtworkRouteContext? fromExtra(Object? extra) => switch (extra) {
    final ArtworkRouteContext context => context,
    final ArtworkBrowseSession session => ArtworkRouteContext(session: session),
    _ => null,
  };
}

final class ArtworkNavigationTarget {
  const ArtworkNavigationTarget({
    required this.artworkId,
    required this.routeContext,
  });

  final String artworkId;
  final ArtworkRouteContext routeContext;
}

/// Different artwork IDs must always produce different route keys. GoRouter's
/// default page key identifies the route template (`/artwork/:id`), which can
/// otherwise preserve a detail page's busy state across replacements.
ValueKey<String> artworkPageKey(String artworkId) =>
    ValueKey<String>('artwork:$artworkId');

ValueKey<String> artworkRoutePageKey(
  ValueKey<String> navigationKey,
  String artworkId,
) => ValueKey<String>('${navigationKey.value}:artwork:$artworkId');

Offset artworkTransitionBegin(ArtworkNavigationDirection? direction) =>
    switch (direction) {
      ArtworkNavigationDirection.previous => const Offset(-0.18, 0),
      ArtworkNavigationDirection.next => const Offset(0.18, 0),
      null => const Offset(0, 0.025),
    };

/// Opens a detail page with the visible feed as its previous/next sequence and
/// caches every item so numeric web IDs remain resolvable while swiping.
void openArtworkFromList(
  BuildContext context,
  WidgetRef ref, {
  required Iterable<Artwork> artworks,
  required Artwork artwork,
}) {
  final items = List<Artwork>.unmodifiable(artworks);
  ref.read(artworkStoreProvider.notifier).putAll(items);
  context.push(
    '/artwork/${artwork.id}',
    extra: ArtworkRouteContext(
      session: ArtworkBrowseSession.fromArtworks(items),
    ),
  );
}

/// Converts a completed horizontal drag into feed navigation. A child
/// horizontal pager (multi-image artwork) wins the gesture arena; it delegates
/// only edge overscroll back to the artwork callbacks.
final class ArtworkSwipeRegion extends StatefulWidget {
  const ArtworkSwipeRegion({
    required this.child,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<ArtworkSwipeRegion> createState() => _ArtworkSwipeRegionState();
}

final class _ArtworkSwipeRegionState extends State<ArtworkSwipeRegion> {
  double _distance = 0;
  double _visualOffset = 0;
  bool _dragging = false;

  void _resetDrag() {
    if (!mounted) return;
    setState(() {
      _distance = 0;
      _visualOffset = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onPrevious == null && widget.onNext == null) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Mouse drag belongs to the inner PageView / horizontal list. The outer
      // artwork swipe region only claims touch-style drags so the two do not
      // fight inside the detail page on desktop.
      supportedDevices: const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      onHorizontalDragStart: (_) {
        setState(() {
          _distance = 0;
          _visualOffset = 0;
          _dragging = true;
        });
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _distance += details.delta.dx;
          _visualOffset = (_distance * 0.16).clamp(-36, 36);
        });
      },
      onHorizontalDragCancel: _resetDrag,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final threshold = (MediaQuery.sizeOf(context).width * 0.16).clamp(
          56.0,
          96.0,
        );
        final callback =
            (_distance > threshold || velocity > 700) &&
                widget.onPrevious != null
            ? widget.onPrevious
            : (_distance < -threshold || velocity < -700) &&
                  widget.onNext != null
            ? widget.onNext
            : null;
        _resetDrag();
        callback?.call();
      },
      child: AnimatedSlide(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        offset: Offset(_visualOffset / MediaQuery.sizeOf(context).width, 0),
        child: widget.child,
      ),
    );
  }
}

enum ArtworkSwipeDirection { previous, next }

/// Accumulates only PageView edge overscroll. Moving among pages in a
/// multi-image work never changes artwork; another swipe beyond the first or
/// last page does.
final class ArtworkEdgeSwipeTracker {
  ArtworkSwipeDirection? _direction;
  double _distance = 0;
  bool _allowPrevious = false;
  bool _allowNext = false;

  /// Locks edge ownership when a new pointer gesture begins. A gesture that
  /// starts on an ordinary page can only change pages; reaching the first or
  /// last page during that same gesture never promotes it into artwork
  /// navigation. The user must release and swipe outward again.
  void start({required bool atFirst, required bool atLast}) {
    reset();
    _allowPrevious = atFirst;
    _allowNext = atLast;
  }

  void reset() {
    _direction = null;
    _distance = 0;
    _allowPrevious = false;
    _allowNext = false;
  }

  void add(double overscroll) {
    final direction = switch (overscroll) {
      < 0 when _allowPrevious => ArtworkSwipeDirection.previous,
      > 0 when _allowNext => ArtworkSwipeDirection.next,
      _ => null,
    };
    if (direction == null) return;
    if (_direction != direction) {
      _direction = direction;
      _distance = 0;
    }
    _distance += overscroll.abs();
  }

  ArtworkSwipeDirection? finish({double threshold = 56}) {
    final result = _distance >= threshold ? _direction : null;
    reset();
    return result;
  }
}
