import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const en = AppStrings.en;
  const zh = AppStrings.zh;

  test('notificationTypeLabel maps known types (English)', () {
    expect(en.notificationTypeLabel('watched'), 'watched you');
    expect(en.notificationTypeLabel('deviation'), 'posted new work');
    expect(en.notificationTypeLabel('favourited'), 'favourited your work');
    expect(en.notificationTypeLabel('comment'), 'commented on your work');
    expect(en.notificationTypeLabel('mention'), 'mentioned you');
    expect(
      en.notificationTypeLabel('collection'),
      'added your work to a collection',
    );
    expect(en.notificationTypeLabel('journal'), 'posted a journal');
    expect(en.notificationTypeLabel('gift'), 'sent you a gift');
    expect(en.notificationTypeLabel('note'), 'sent you a note');
    expect(en.notificationTypeLabel('llama'), 'gave you a Llama');
    expect(en.notificationTypeLabel('status'), 'updated their status');
  });

  test('notificationTypeLabel has a default and Chinese works', () {
    expect(en.notificationTypeLabel('unknown'), 'posted an update');
    expect(zh.notificationTypeLabel('watched'), '关注了你');
  });

  test('folderArtworkCount formats count', () {
    expect(en.folderArtworkCount(3), '3 artworks');
    expect(zh.folderArtworkCount(3), '3 作品');
  });

  test('artistStats formats stats', () {
    expect(en.artistStats(10, 5), '10 deviations · 5 favourites');
    expect(zh.artistStats(10, 5), '10 作品 · 5 收藏');
  });

  test('relativeTime uses the right bucket', () {
    final now = DateTime.now();
    expect(en.relativeTime(null), isEmpty);
    expect(en.relativeTime(now.subtract(const Duration(seconds: 5))), 'now');
    expect(en.relativeTime(now.subtract(const Duration(minutes: 5))), '5m ago');
    expect(en.relativeTime(now.subtract(const Duration(hours: 2))), '2h ago');
    expect(en.relativeTime(now.subtract(const Duration(days: 3))), '3d ago');
  });

  test('login strings are localized', () {
    expect(zh.signInOrRegister, '登录或注册');
    expect(en.signInOrRegister, 'Sign in or create an account');
    expect(zh.signInWelcomeBody, contains('网页会话 Cookie'));
    expect(zh.loginFailed('网络错误'), '登录失败：网络错误');
    expect(en.loginFailed('Network error'), 'Sign-in failed: Network error');
    expect(zh.signInWelcomeBody, contains('OAuth'));
    expect(zh.localLogoutHint, contains('一并退出'));
    expect(zh.home, '推荐');
    expect(en.home, 'For you');
  });

  test('download deletion warning states that local files are removed', () {
    expect(zh.deleteFinishedDownloadsTitle, '删除已结束的下载？');
    expect(zh.deleteFinishedDownloadsMessage(2), contains('本地文件'));
    expect(zh.deleteFinishedDownloadsMessage(2), contains('无法撤销'));
    expect(
      en.deleteFinishedDownloadsMessage(1),
      contains('1 finished download record'),
    );
    expect(
      en.deleteFinishedDownloadsMessage(2),
      contains('2 finished download records'),
    );
    expect(zh.deleteFinishedDownloadsFailed('无权限'), '删除失败：无权限');
    expect(en.moreLikeThisLoadFailed, 'Could not load similar artwork');
    expect(zh.noMoreLikeThis, contains('稍后再检查'));
    expect(zh.checkSuggestions, '检查更新');
    expect(zh.moreLikeThisStillEmpty, contains('已检查最新推荐'));
    expect(zh.reloadSuggestions, '重新加载');
    expect(en.moreLikeThisNetworkFailure, contains('network'));
    expect(zh.moreLikeThisSessionFailure, contains('登录会话'));
    expect(en.videoLoadFailed, 'Video failed to load');
  });

  test('empty watched feed guides users without exposing API details', () {
    final zh = strings(AppLanguage.zh);
    final en = strings(AppLanguage.en);

    expect(zh.noWatched, contains('关注喜欢的创作者'));
    expect(zh.discoverArtists, '发现并关注');
    expect(zh.watchedFeedLoadFailure, isNot(contains('results')));
    expect(en.noWatched, contains('Follow creators'));
    expect(en.noWatched.toLowerCase(), isNot(contains('api')));
    expect(en.watchedFeedLoadFailure.toLowerCase(), isNot(contains('api')));
  });

  test('similar artwork copy does not expose website parser details', () {
    final zh = strings(AppLanguage.zh);
    final en = strings(AppLanguage.en);

    expect(zh.moreLikeThisFormatFailure, isNot(contains('页面结构')));
    expect(zh.noMoreLikeThis, isNot(contains('备用来源')));
    expect(
      en.moreLikeThisFormatFailure.toLowerCase(),
      isNot(contains('format')),
    );
    expect(en.noMoreLikeThis.toLowerCase(), isNot(contains('source')));
  });
}
