/// Explicit source routing and outcome classification for DAViewer.
///
/// Official/Web are two capability groups, not two login modes. A web session
/// being unavailable only demotes Web-dependent capabilities; it never signs
/// the user out of the OAuth identity.
library;

/// The high-level data needs DAViewer routes to one or more sources.
enum DesiredCapability {
  artworkMetadata,
  originalMedia,
  multiImageExtras,
  search,
  dailyDeviations,
  rfyFeed,
  gallery,
  collectionContents,
  moreLikeThis,
  socialMutation,
}

/// The concrete provider family for a data need.
enum DataSource { officialApi, webApi, mediaCdn, storage, transfer }

/// Which sources serve a capability, and in which order.
final class CapabilityPolicy {
  const CapabilityPolicy({required this.primary, this.secondary});

  final DataSource primary;
  final DataSource? secondary;

  static const Map<DesiredCapability, CapabilityPolicy> _plans = {
    DesiredCapability.artworkMetadata: CapabilityPolicy(
      primary: DataSource.officialApi,
      secondary: DataSource.webApi,
    ),
    DesiredCapability.originalMedia: CapabilityPolicy(
      primary: DataSource.officialApi,
      secondary: DataSource.webApi,
    ),
    DesiredCapability.multiImageExtras: CapabilityPolicy(
      primary: DataSource.webApi,
    ),
    DesiredCapability.search: CapabilityPolicy(
      primary: DataSource.webApi,
      secondary: DataSource.officialApi,
    ),
    DesiredCapability.dailyDeviations: CapabilityPolicy(
      primary: DataSource.officialApi,
    ),
    DesiredCapability.rfyFeed: CapabilityPolicy(primary: DataSource.webApi),
    DesiredCapability.gallery: CapabilityPolicy(
      primary: DataSource.officialApi,
      secondary: DataSource.webApi,
    ),
    DesiredCapability.collectionContents: CapabilityPolicy(
      primary: DataSource.webApi,
    ),
    DesiredCapability.moreLikeThis: CapabilityPolicy(
      primary: DataSource.webApi,
      secondary: DataSource.officialApi,
    ),
    DesiredCapability.socialMutation: CapabilityPolicy(
      primary: DataSource.officialApi,
    ),
  };

  static CapabilityPolicy planFor(DesiredCapability capability) =>
      _plans[capability]!;
}

/// Machine-readable distinction between a real empty, a failure, an
/// unsupported path, and an unknown state.
enum SourceStatus { success, empty, failed, unsupported, unknown }

final class SourceResult<T> {
  const SourceResult._({
    required this.status,
    this.value,
    this.source,
    this.error,
  });

  const SourceResult.success(T value, {DataSource? source})
    : this._(status: SourceStatus.success, value: value, source: source);

  const SourceResult.empty({DataSource? source})
    : this._(status: SourceStatus.empty, source: source);

  const SourceResult.failed(Object error, {DataSource? source})
    : this._(status: SourceStatus.failed, source: source, error: error);

  const SourceResult.unsupported({DataSource? source})
    : this._(status: SourceStatus.unsupported, source: source);

  const SourceResult.unknown({DataSource? source})
    : this._(status: SourceStatus.unknown, source: source);

  final SourceStatus status;
  final T? value;
  final DataSource? source;
  final Object? error;

  bool get isSuccess => status == SourceStatus.success;
  bool get isEmpty => status == SourceStatus.empty;
  bool get isFailure => status == SourceStatus.failed;
}

final class SourceAttempt<T> {
  const SourceAttempt({
    required this.source,
    required this.run,
    this.supported = true,
  });

  final DataSource source;
  final bool supported;
  final Future<SourceResult<T>> Function() run;
}

/// Runs capability attempts in policy order. `empty` is a terminal answer by
/// default: a confirmed empty result is not a fallback signal.
final class SourceCoordinator {
  const SourceCoordinator._();

  static Future<SourceResult<T>> tryInOrder<T>(
    List<SourceAttempt<T>> attempts, {
    Set<SourceStatus> retryWhen = const {
      SourceStatus.failed,
      SourceStatus.unsupported,
      SourceStatus.unknown,
    },
  }) async {
    var last = SourceResult<T>.unknown();
    for (final attempt in attempts) {
      if (!attempt.supported) {
        last = SourceResult<T>.unsupported(source: attempt.source);
        continue;
      }
      final SourceResult<T> result;
      try {
        result = await attempt.run();
      } on Object catch (error) {
        last = SourceResult<T>.failed(error, source: attempt.source);
        continue;
      }
      last = result;
      if (!retryWhen.contains(result.status)) return result;
    }
    return last;
  }
}
