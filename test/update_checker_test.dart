import 'package:daviewer/core/updates/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compareVersions orders semantic versions', () {
    expect(compareVersions('0.2.145', '0.2.144'), greaterThan(0));
    expect(compareVersions('0.2.144', '0.2.145'), lessThan(0));
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('0.2.10', '0.2.9'), greaterThan(0));
  });

  test('isSemver rejects non-release build names', () {
    expect(isSemver('0.2.144'), isTrue);
    expect(isSemver('development'), isFalse);
    expect(isSemver('0.2.144-beta'), isFalse);
  });

  test('parseLatestRelease extracts version and notes', () {
    final info = parseLatestRelease(<String, Object?>{
      'tag_name': 'v0.2.166',
      'body': '## 0.2.166\n\n- 修复了问题。\n',
    });

    expect(info?.version, '0.2.166');
    expect(info?.notes, '## 0.2.166\n\n- 修复了问题。');
  });

  test('extractUserReleaseNotes drops the downloads section (zh)', () {
    const body = '''
## 问题修复

- 修复：web session on flaky-network cold start

## 下载

| 平台 | 文件 | 大小 | 下载 |
|---|---|---|---|
| Android | `DAViewer-v0.2.186.apk` | 62.4 MB | [下载](url) |

下载后可用本 Release 资产中的 `SHA256SUMS` 校验完整性。
''';
    expect(
      extractUserReleaseNotes(body),
      '## 问题修复\n\n- 修复：web session on flaky-network cold start',
    );
  });

  test('extractUserReleaseNotes drops the downloads section (en)', () {
    const body = '''
## Fixes

- Fixed the flaky-web-session login prompt.

## Downloads

| Platform | File | Size | Download |
|---|---|---|---|
| Android | `app.apk` | 62 MB | [download](url) |

Verify your download against `SHA256SUMS`.
''';
    expect(
      extractUserReleaseNotes(body),
      '## Fixes\n\n- Fixed the flaky-web-session login prompt.',
    );
  });

  test('extractUserReleaseNotes keeps bodies without a downloads section', () {
    expect(
      extractUserReleaseNotes('## 0.2.166\n\n- 修复了问题。'),
      '## 0.2.166\n\n- 修复了问题。',
    );
  });

  test('extractUserReleaseNotes returns null for downloads-only or empty', () {
    expect(extractUserReleaseNotes('## 下载\n\n| a | b |\n'), isNull);
    expect(extractUserReleaseNotes('   '), isNull);
  });

  test('parseLatestRelease strips the downloads section from notes', () {
    final info = parseLatestRelease(<String, Object?>{
      'tag_name': 'v0.2.186',
      'body': '## 问题修复\n\n- 修复了问题。\n\n## 下载\n\n| a | b |\n',
    });

    expect(info?.version, '0.2.186');
    expect(info?.notes, '## 问题修复\n\n- 修复了问题。');
  });

  test('parseLatestRelease trims and tolerates missing notes', () {
    final withNotes = parseLatestRelease(<String, Object?>{
      'tag_name': 'v0.2.165',
      'body': '  line one\n  ',
    });
    expect(withNotes?.notes, 'line one');

    final noNotes = parseLatestRelease(<String, Object?>{
      'tag_name': 'v0.2.165',
      'body': '   ',
    });
    expect(noNotes?.notes, isNull);
  });

  test('parseLatestRelease rejects unexpected payloads', () {
    expect(parseLatestRelease('not a map'), isNull);
    expect(
      parseLatestRelease(<String, Object?>{'tag_name': 'latest'}), // not semver
      isNull,
    );
    expect(parseLatestRelease(<String, Object?>{'body': 'notes only'}), isNull);
  });

  test('versionFromReleaseUri reads version without GitHub API', () {
    expect(
      versionFromReleaseUri(
        Uri.parse(
          'https://github.com/redtidev1918/DAViewer/releases/tag/v0.4.10',
        ),
      ),
      '0.4.10',
    );
    expect(
      versionFromReleaseUri(
        Uri.parse('https://github.com/redtidev1918/DAViewer/releases/latest'),
      ),
      isNull,
    );
  });
}
