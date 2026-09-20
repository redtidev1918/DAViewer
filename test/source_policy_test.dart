import 'package:daviewer/core/data/source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CapabilityPolicy', () {
    test('search is Web primary with coarse official fallback', () {
      final plan = CapabilityPolicy.planFor(DesiredCapability.search);
      expect(plan.primary, DataSource.webApi);
      expect(plan.secondary, DataSource.officialApi);
    });

    test('multi-image extras are Web-only', () {
      final plan = CapabilityPolicy.planFor(DesiredCapability.multiImageExtras);
      expect(plan.primary, DataSource.webApi);
      expect(plan.secondary, isNull);
    });
  });

  group('SourceCoordinator', () {
    test('success returns immediately', () async {
      final result = await SourceCoordinator.tryInOrder([
        SourceAttempt(
          source: DataSource.webApi,
          run: () async =>
              SourceResult<int>.success(1, source: DataSource.webApi),
        ),
      ]);
      expect(result.isSuccess, isTrue);
      expect(result.value, 1);
    });

    test('empty is terminal and does not fall back', () async {
      var officialCalled = 0;
      final result = await SourceCoordinator.tryInOrder([
        SourceAttempt(
          source: DataSource.webApi,
          run: () async => SourceResult<int>.empty(source: DataSource.webApi),
        ),
        SourceAttempt(
          source: DataSource.officialApi,
          run: () async {
            officialCalled += 1;
            return SourceResult<int>.success(2, source: DataSource.officialApi);
          },
        ),
      ]);
      expect(result.isEmpty, isTrue);
      expect(officialCalled, 0);
    });

    test('failure falls back to the next source', () async {
      final result = await SourceCoordinator.tryInOrder([
        SourceAttempt(
          source: DataSource.webApi,
          run: () async =>
              SourceResult<int>.failed('boom', source: DataSource.webApi),
        ),
        SourceAttempt(
          source: DataSource.officialApi,
          run: () async =>
              SourceResult<int>.success(2, source: DataSource.officialApi),
        ),
      ]);
      expect(result.isSuccess, isTrue);
      expect(result.value, 2);
    });

    test('unsupported skips to the next source', () async {
      final result = await SourceCoordinator.tryInOrder([
        SourceAttempt(
          source: DataSource.webApi,
          supported: false,
          run: () async => SourceResult<int>.empty(source: DataSource.webApi),
        ),
        SourceAttempt(
          source: DataSource.officialApi,
          run: () async =>
              SourceResult<int>.success(2, source: DataSource.officialApi),
        ),
      ]);
      expect(result.isSuccess, isTrue);
      expect(result.value, 2);
    });
  });
}
