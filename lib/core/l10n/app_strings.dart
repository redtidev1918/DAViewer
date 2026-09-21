import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_preferences.dart';

/// Supported UI languages.
enum AppLanguage { zh, en }

/// A minimal localization controller. UI strings live in [AppStrings], which
/// selects a language based on [AppLanguageController.current].
final class AppLanguageController extends StateNotifier<AppLanguage> {
  AppLanguageController([super.state = AppLanguage.zh]);

  void set(AppLanguage language) {
    state = language;
    unawaited(AppPreferences.saveLanguage(language.name));
  }
}

final appLanguageProvider =
    StateNotifierProvider<AppLanguageController, AppLanguage>(
      (ref) => AppLanguageController(),
    );

/// Returns the active localized string table.
AppStrings strings(AppLanguage language) => AppStrings.of(language);

/// Localized strings for the app. Add new keys here as the UI grows.
final class AppStrings {
  const AppStrings._(this._lang);

  factory AppStrings.of(AppLanguage language) =>
      language == AppLanguage.zh ? zh : en;

  final AppLanguage _lang;

  static const AppStrings zh = AppStrings._(AppLanguage.zh);
  static const AppStrings en = AppStrings._(AppLanguage.en);

  String get appTitle => _lang == AppLanguage.zh ? 'DA 查看器' : 'DA Viewer';
  String get home => _lang == AppLanguage.zh ? '推荐' : 'For you';
  String get daily => _lang == AppLanguage.zh ? '每日精选' : 'Daily';
  String get following => _lang == AppLanguage.zh ? '关注动态' : 'Watched';
  String get search => _lang == AppLanguage.zh ? '搜索' : 'Search';
  String get gallery => _lang == AppLanguage.zh ? '画廊' : 'Gallery';
  String get favourites => _lang == AppLanguage.zh ? '收藏' : 'Favourites';
  String get downloads => _lang == AppLanguage.zh ? '下载' : 'Downloads';
  String get notifications => _lang == AppLanguage.zh ? '通知' : 'Notifications';
  String get history => _lang == AppLanguage.zh ? '历史' : 'History';
  String get noHistory =>
      _lang == AppLanguage.zh ? '暂无访问历史' : 'No visit history.';
  String get noNotifications =>
      _lang == AppLanguage.zh ? '暂无通知' : 'No notifications.';
  String get settings => _lang == AppLanguage.zh ? '设置' : 'Settings';
  String get logout => _lang == AppLanguage.zh ? '退出登录' : 'Logout';
  String get signedOut => _lang == AppLanguage.zh ? '已登出' : 'Signed out';
  String get localLogoutHint => _lang == AppLanguage.zh
      ? '退出 DAViewer；会一并退出 App 内的 DeviantArt 网站会话。'
      : 'Sign out of DAViewer. This also signs out the DeviantArt website session in the app.';
  String get login => _lang == AppLanguage.zh ? '登录' : 'Login';
  String get signInWelcomeTitle =>
      _lang == AppLanguage.zh ? '登录 DeviantArt' : 'Sign in to DeviantArt';
  String get signInWelcomeBody => _lang == AppLanguage.zh
      ? '这次登录会同时完成两件事：官方授权（OAuth）与网页会话 Cookie。Cookie 是 DeviantArt 识别网页身份的数据，个性化推荐依赖它。请完成整个流程后再关闭页面。'
      : 'This login completes two things at once: OAuth authorization and the web-session Cookie. The Cookie is how DeviantArt identifies the browser, and personalized recommendations depend on it. Keep the page open until it finishes.';
  String get signInOrRegister =>
      _lang == AppLanguage.zh ? '登录或注册' : 'Sign in or create an account';
  String get verificationHint => _lang == AppLanguage.zh
      ? '如页面出现人机验证，请按页面提示完成，随后会自动继续登录。'
      : 'If a human-verification challenge appears, complete it and sign-in continues automatically.';
  String get notLoggedIn => _lang == AppLanguage.zh ? '未登录' : 'Not signed in';
  String get loginFirst =>
      _lang == AppLanguage.zh ? '请先登录。' : 'Please sign in.';

  String get contentSettings =>
      _lang == AppLanguage.zh ? '成人内容设置' : 'Mature content settings';
  String get devartSettings => _lang == AppLanguage.zh
      ? 'DeviantArt 账号设置'
      : 'DeviantArt account settings';
  String get loginSuccess => _lang == AppLanguage.zh ? '登录成功' : 'Signed in';
  String get syncingAfterLogin =>
      _lang == AppLanguage.zh ? '正在同步登录状态…' : 'Syncing your session…';
  String loginFailed(String detail) =>
      _lang == AppLanguage.zh ? '登录失败：$detail' : 'Sign-in failed: $detail';
  String get loginRecoveryStorageUnavailable => _lang == AppLanguage.zh
      ? '系统暂时无法保存授权恢复信息。请保持 DAViewer 开启并重新尝试登录。'
      : 'Authorization recovery storage is temporarily unavailable. Keep DAViewer open and try signing in again.';
  String get loginSessionStorageUnavailable => _lang == AppLanguage.zh
      ? '官方授权已返回，但系统无法安全保存登录。请重新启动 DAViewer 后再试，这不是账号或网络错误。'
      : 'Authorization returned, but the system could not securely save the session. Restart DAViewer and try again; this is not an account or network error.';
  String get loginCallbackTimeout => _lang == AppLanguage.zh
      ? '没有收到登录回传。请稍后重新尝试。'
      : 'No sign-in callback arrived. Try again shortly.';
  String get loginBrowserOpenFailed => _lang == AppLanguage.zh
      ? '无法打开官方登录页。请检查网络后重试。'
      : 'Could not open the official sign-in page. Check the network and try again.';
  String get loginNetworkFailure => _lang == AppLanguage.zh
      ? '授权服务暂时无法连接。请在设置中检查网络代理后重试。'
      : 'The authorization service is temporarily unreachable. Check the proxy in Settings and try again.';
  String get loginUnexpectedFailure => _lang == AppLanguage.zh
      ? '登录流程没有完成，请取消后重新尝试。'
      : 'Sign-in did not finish. Cancel it and try again.';
  String get noArtworks =>
      _lang == AppLanguage.zh ? '暂无作品' : 'No artworks found.';
  String get noRecommendations =>
      _lang == AppLanguage.zh ? '暂无推荐' : 'No recommendations yet.';
  String get recommendedSignInHint => _lang == AppLanguage.zh
      ? '个性化推荐需要 DeviantArt 网页会话 Cookie。当前会话没有 Cookie，推荐只会显示通用内容；点击登录，在 App 内网页完成一次登录以获取 Cookie。'
      : 'Personalized recommendations need the DeviantArt web-session Cookie. Without it the feed shows only generic content; tap Login and finish one web sign-in inside the app to restore the Cookie.';
  String get recommendedFeedLoadFailure => _lang == AppLanguage.zh
      ? '推荐内容暂时无法加载。请下拉刷新，或在设置中检查网络代理。'
      : 'Recommendations could not load. Pull to refresh or check the proxy in Settings.';
  String get noImage => _lang == AppLanguage.zh ? '暂无图片' : 'No image';
  String get imageLoadFailed =>
      _lang == AppLanguage.zh ? '图片加载失败' : 'Failed to load';
  String get previousArtwork =>
      _lang == AppLanguage.zh ? '上一个作品' : 'Previous artwork';
  String get nextArtwork => _lang == AppLanguage.zh ? '下一个作品' : 'Next artwork';
  String get videoLoadFailed =>
      _lang == AppLanguage.zh ? '视频加载失败' : 'Video failed to load';
  String get byPrefix => _lang == AppLanguage.zh ? '作者：' : 'by ';
  String get publishedLabel => _lang == AppLanguage.zh ? '发布于' : 'Published';
  String get updatedLabel => _lang == AppLanguage.zh ? '更新于' : 'Updated';
  String get recommendedTags =>
      _lang == AppLanguage.zh ? '为你推荐' : 'Recommended for you';
  String get noDaily =>
      _lang == AppLanguage.zh ? '暂无每日推荐' : 'No daily deviations.';
  String get noWatched => _lang == AppLanguage.zh
      ? '你还没有关注任何用户。关注喜欢的创作者后，他们的新作品会出现在这里。'
      : 'You are not watching anyone yet. Follow creators to see their new artwork here.';
  String get watchedFeedLoadFailure => _lang == AppLanguage.zh
      ? '关注动态暂时无法加载，请稍后重试。'
      : 'Your watched feed is temporarily unavailable. Try again later.';
  String get noFavourites =>
      _lang == AppLanguage.zh ? '暂无收藏' : 'No favourites.';
  String get noDownloads => _lang == AppLanguage.zh ? '暂无下载' : 'No downloads.';
  String get storedInApp =>
      _lang == AppLanguage.zh ? '已保存在应用内' : 'Stored in the app';
  String get deleteFinishedDownloads =>
      _lang == AppLanguage.zh ? '删除已结束下载' : 'Delete finished downloads';
  String get deleteFinishedDownloadsTitle =>
      _lang == AppLanguage.zh ? '删除已结束的下载？' : 'Delete finished downloads?';
  String deleteFinishedDownloadsMessage(int count) {
    if (_lang == AppLanguage.zh) {
      return '将删除 $count 条已结束的下载记录及其本地文件（如有）。此操作无法撤销。';
    }
    final record = count == 1 ? 'record' : 'records';
    return 'This will permanently delete $count finished download $record and any local files. This cannot be undone.';
  }

  String get deleteAction => _lang == AppLanguage.zh ? '删除' : 'Delete';
  String deleteFinishedDownloadsFailed(String detail) =>
      _lang == AppLanguage.zh ? '删除失败：$detail' : 'Delete failed: $detail';
  String get noResults =>
      _lang == AppLanguage.zh ? '无搜索结果' : 'No results found.';
  String get retry => _lang == AppLanguage.zh ? '重试' : 'Retry';
  String get refresh => _lang == AppLanguage.zh ? '刷新' : 'Refresh';
  String get done => _lang == AppLanguage.zh ? '完成' : 'Done';
  String get pause => _lang == AppLanguage.zh ? '暂停' : 'Pause';
  String get resume => _lang == AppLanguage.zh ? '继续' : 'Resume';
  String get cancel => _lang == AppLanguage.zh ? '取消' : 'Cancel';
  String get language => _lang == AppLanguage.zh ? '语言' : 'Language';
  String get chinese => _lang == AppLanguage.zh ? '中文' : '中文 (Chinese)';
  String get english => _lang == AppLanguage.zh ? '英文' : 'English';
  String get appearance => _lang == AppLanguage.zh ? '外观' : 'Appearance';
  String get themeSystem => _lang == AppLanguage.zh ? '跟随系统' : 'System';
  String get themeLight => _lang == AppLanguage.zh ? '浅色' : 'Light';
  String get themeDark => _lang == AppLanguage.zh ? '深色' : 'Dark';
  String get clearCache => _lang == AppLanguage.zh ? '清除缓存' : 'Clear cache';
  String get cacheCleared =>
      _lang == AppLanguage.zh ? '缓存已清除' : 'Cache cleared';
  String get checkUpdates =>
      _lang == AppLanguage.zh ? '检查更新' : 'Check for updates';
  String get upToDate => _lang == AppLanguage.zh ? '已是最新版本' : 'Up to date';
  String newVersionAvailable(String version) => _lang == AppLanguage.zh
      ? '发现新版本 $version'
      : 'New version $version available';
  String updateDetails(String version) =>
      _lang == AppLanguage.zh ? '$version 更新内容' : "What's new in $version";
  String get noUpdateNotes => _lang == AppLanguage.zh
      ? '（暂无更新说明，可在下载页查看）'
      : '(No release notes here — see the download page.)';
  String get downloadUpdate => _lang == AppLanguage.zh ? '去下载' : 'Download';
  String get markAllRead => _lang == AppLanguage.zh ? '全部已读' : 'Mark all read';
  String get proxy => _lang == AppLanguage.zh ? '网络代理' : 'Proxy';
  String get diagnostics => _lang == AppLanguage.zh ? '日志与诊断' : 'Diagnostics';
  String get reportProblem =>
      _lang == AppLanguage.zh ? '报告问题' : 'Report a problem';
  String get reportPreviewTitle =>
      _lang == AppLanguage.zh ? '报告内容预览' : 'Review report';
  String get reportPreviewBody => _lang == AppLanguage.zh
      ? '将在你的浏览器中打开 GitHub Issue，只包含下方内容（不含账号、令牌或 Cookie）。提交前可自行编辑。'
      : 'This opens a GitHub issue in your browser with only the content below (no account, tokens, or cookies). You can edit it before submitting.';
  String get includeLog => _lang == AppLanguage.zh
      ? '附带日志片段（已脱敏）'
      : 'Include a redacted log excerpt';
  String get openReport => _lang == AppLanguage.zh ? '打开报告页' : 'Open report';
  String get crashDetectedHint => _lang == AppLanguage.zh
      ? '上次运行似乎异常退出。可在下方查看日志或报告问题。'
      : 'The previous run ended unexpectedly. Review the log or report the issue below.';
  String get downloadOriginal =>
      _lang == AppLanguage.zh ? '下载原图' : 'Download original';
  String get original => _lang == AppLanguage.zh ? '原图' : 'Original';
  String get description => _lang == AppLanguage.zh ? '作品描述' : 'Description';
  String get about => _lang == AppLanguage.zh ? '关于' : 'About';
  String get githubRepository =>
      _lang == AppLanguage.zh ? 'GitHub 仓库' : 'GitHub repository';
  String get releases => _lang == AppLanguage.zh ? '版本发布' : 'Releases';
  String get close => _lang == AppLanguage.zh ? '关闭' : 'Close';
  String get open => _lang == AppLanguage.zh ? '打开' : 'Open';
  String get openFolder => _lang == AppLanguage.zh ? '打开文件夹' : 'Open folder';

  // --- artwork detail ---
  String get artworkDetail =>
      _lang == AppLanguage.zh ? '作品详情' : 'Artwork detail';
  String get linkCopied => _lang == AppLanguage.zh ? '链接已复制' : 'Link copied';
  String get copyLink => _lang == AppLanguage.zh ? '复制链接' : 'Copy link';
  String get openInBrowser =>
      _lang == AppLanguage.zh ? '在浏览器打开' : 'Open in browser';
  String get share => _lang == AppLanguage.zh ? '分享' : 'Share';
  String get shareFailedCopied => _lang == AppLanguage.zh
      ? '无法打开系统分享，链接已复制'
      : 'The share sheet could not open. The link was copied.';
  String get favourite => _lang == AppLanguage.zh ? '收藏' : 'Favourite';
  String get unfavourite => _lang == AppLanguage.zh ? '取消收藏' : 'Unfavourite';
  String get favouritedToast => _lang == AppLanguage.zh ? '已收藏' : 'Favourited';
  String get unfavouritedToast =>
      _lang == AppLanguage.zh ? '已取消收藏' : 'Removed from favourites';
  String get bodyText => _lang == AppLanguage.zh ? '正文' : 'Text';
  String get originalStatusPrefix =>
      _lang == AppLanguage.zh ? '原图：' : 'Original: ';
  String get sizeLabel => _lang == AppLanguage.zh ? '大小：' : 'Size: ';
  String get fallbackDownloadNotice => _lang == AppLanguage.zh
      ? '原图不可下载，但可以保存当前展示的最高画质图片。'
      : 'The original is unavailable, but the highest-quality displayed image can be saved.';
  String get downloadUnavailableReason =>
      _lang == AppLanguage.zh ? '不能下载的原因' : 'Why downloading is unavailable';
  String get checkingDownloadAvailability => _lang == AppLanguage.zh
      ? '正在确认当前账号的下载权限…'
      : 'Checking download access for this account…';
  String get downloadAvailabilityCheckFailed => _lang == AppLanguage.zh
      ? '暂时无法确认下载权限，可能是网络、登录会话或服务异常。请重试。'
      : 'Download permission could not be verified. Check the network/session and retry.';
  String get retryDownloadCheck =>
      _lang == AppLanguage.zh ? '重新检查下载权限' : 'Check again';
  String get downloadLimitReached => _lang == AppLanguage.zh
      ? '当前账号的免费下载次数已用完。'
      : 'This account has reached its free-download limit.';
  String get creatorDisabledDownload => _lang == AppLanguage.zh
      ? '作者没有开放这件作品的原图下载。'
      : 'The creator has not enabled original downloads for this artwork.';
  String providerDownloadReason(String reason) => _lang == AppLanguage.zh
      ? 'DeviantArt 返回的原因：$reason'
      : 'DeviantArt says: $reason';
  String downloadFailed(String reason) =>
      _lang == AppLanguage.zh ? '下载失败：$reason' : 'Download failed: $reason';
  String get downloadFailureNetwork => _lang == AppLanguage.zh
      ? '网络连接中断或请求超时，请检查网络后重试。'
      : 'The connection failed or timed out. Check your network and retry.';
  String get downloadFailurePermission => _lang == AppLanguage.zh
      ? '当前账号或登录会话没有下载权限，请重新登录或检查作品限制。'
      : 'This account or session is not allowed to download the file.';
  String get downloadFailureNotFound => _lang == AppLanguage.zh
      ? '下载源已失效、被删除或不再提供。'
      : 'The source file expired, was removed, or is no longer offered.';
  String get downloadFailureStorage => _lang == AppLanguage.zh
      ? '无法写入本地文件，请检查存储空间和文件夹权限。'
      : 'The file could not be written. Check free space and folder permissions.';
  String get downloading => _lang == AppLanguage.zh ? '正在下载…' : 'Downloading…';
  String get downloadImage =>
      _lang == AppLanguage.zh ? '下载图片' : 'Download image';
  String get confirmImageDownloadTitle =>
      _lang == AppLanguage.zh ? '下载这张图片？' : 'Download this image?';
  String get confirmImageDownloadMessage => _lang == AppLanguage.zh
      ? '确认后会将当前图片保存到系统下载目录。'
      : 'The current image will be saved to the system Downloads folder.';
  String get savedToPrefix => _lang == AppLanguage.zh ? '已保存到 ' : 'Saved to ';
  String get zoomIn => _lang == AppLanguage.zh ? '放大' : 'Zoom in';
  String get zoomReset => _lang == AppLanguage.zh ? '重置缩放' : 'Reset zoom';

  String get availabilityAvailable =>
      _lang == AppLanguage.zh ? '可下载' : 'Available';
  String get availabilityLoginRequired =>
      _lang == AppLanguage.zh ? '需要登录' : 'Login required';
  String get availabilityPurchaseRequired =>
      _lang == AppLanguage.zh ? '需要购买' : 'Purchase required';
  String get availabilityRestricted =>
      _lang == AppLanguage.zh ? '受限' : 'Restricted';
  String get availabilityUnavailable =>
      _lang == AppLanguage.zh ? '不可下载' : 'Unavailable';
  String get availabilityMissing =>
      _lang == AppLanguage.zh ? '已删除或不存在' : 'Deleted or unavailable';

  String get hintLoginRequired => _lang == AppLanguage.zh
      ? '该作品需要登录后才能下载原图。'
      : 'Sign in to download the original.';
  String get hintPurchaseRequired => _lang == AppLanguage.zh
      ? '该作品需要付费订阅才能下载原图。'
      : 'A paid subscription is required to download the original.';
  String get hintRestricted => _lang == AppLanguage.zh
      ? '该作品的原图下载受限。'
      : 'Downloading the original is restricted.';
  String get hintUnavailable => _lang == AppLanguage.zh
      ? '该作品不提供原图下载。'
      : 'The original is not available for download.';
  String get hintMissing => _lang == AppLanguage.zh
      ? '作品或原始文件已删除、不存在，或下载链接已经失效。'
      : 'The artwork or original file was removed, is missing, or its link expired.';

  // --- home open-link dialog ---
  String get openLinkTooltip => _lang == AppLanguage.zh ? '打开链接' : 'Open link';
  String get openLinkTitle =>
      _lang == AppLanguage.zh ? '打开 DeviantArt 链接' : 'Open DeviantArt link';
  String get openLinkHint => _lang == AppLanguage.zh
      ? '粘贴作品或作者链接，例如\nhttps://www.deviantart.com/xxx/art/xxx-123456789'
      : 'Paste an artwork or author link, e.g.\nhttps://www.deviantart.com/xxx/art/xxx-123456789';

  // --- settings ---
  String get signedInWithDA => _lang == AppLanguage.zh
      ? '已通过 DeviantArt 登录'
      : 'Signed in with DeviantArt';
  String get loginHint => _lang == AppLanguage.zh
      ? '登录后可使用关注与收藏功能'
      : 'Login to use following and favourites';
  String get directProxy => _lang == AppLanguage.zh ? '未使用代理（直连）' : 'Direct';
  String get viewLogs => _lang == AppLanguage.zh ? '查看运行日志与错误记录' : 'View logs';
  String get accountCookies =>
      _lang == AppLanguage.zh ? '账号 Cookie' : 'Account cookies';
  String get accountCookiesSubtitle => _lang == AppLanguage.zh
      ? '查看、复制导出或导入 DeviantArt 网站会话 Cookie'
      : 'View, export, or import the DeviantArt web session cookies';
  String get cookiesWarning => _lang == AppLanguage.zh
      ? 'Cookie 等同于你的登录凭证，请勿泄露或发送给他人。'
      : 'Cookies are your login credentials. Never share or send them to anyone.';
  String get copyCookies =>
      _lang == AppLanguage.zh ? '复制 Cookie（JSON）' : 'Copy cookies (JSON)';
  String get cookiesCopied => _lang == AppLanguage.zh
      ? 'Cookie 已复制到剪贴板'
      : 'Cookies copied to clipboard';
  String get noCookies =>
      _lang == AppLanguage.zh ? '当前没有会话 Cookie。' : 'No session cookies yet.';
  String get noCookiesHint => _lang == AppLanguage.zh
      ? '可以登录，或粘贴 Cookie 直接导入会话。'
      : 'Sign in, or paste cookies to import a session.';
  String get importCookies =>
      _lang == AppLanguage.zh ? '导入 Cookie' : 'Import cookies';
  String get importCookiesTitle =>
      _lang == AppLanguage.zh ? '导入 Cookie' : 'Import cookies';
  String get importCookiesHint => _lang == AppLanguage.zh
      ? '粘贴导出的 JSON、浏览器插件导出的 Cookie 列表，或 name=value; … 格式的 Cookie。只能导入与当前账号一致的会话；切换账号请先退出登录。'
      : 'Paste exported JSON, a browser-extension cookie list, or a name=value; … Cookie header. Only a session matching the current account can be imported; sign out first to switch accounts.';
  String get cookiesPasteLabel =>
      _lang == AppLanguage.zh ? 'Cookie 内容' : 'Cookie contents';
  String get importAction => _lang == AppLanguage.zh ? '导入' : 'Import';
  String get importing => _lang == AppLanguage.zh ? '正在导入…' : 'Importing…';
  String cookiesImported(String username) => _lang == AppLanguage.zh
      ? 'Cookie 已导入，会话账号：$username'
      : 'Cookies imported. Session account: $username';
  String cookieImportNeedsOAuthTitle(String username) => _lang == AppLanguage.zh
      ? '会话已导入：$username'
      : 'Session imported: $username';
  String get cookieImportNeedsOAuthBody => _lang == AppLanguage.zh
      ? '推荐流已经可以使用。但关注、通知、收藏操作和原图下载等功能还需要官方授权登录一次；内嵌登录页会识别刚导入的会话，无需再输入账号密码。现在去登录吗？'
      : 'Your recommendations already work. But following, notifications, favourites, and original downloads still need one official authorization. The embedded sign-in page recognizes the imported session — no password needed. Sign in now?';
  String get signInNow => _lang == AppLanguage.zh ? '去登录' : 'Sign in now';
  String get notNow => _lang == AppLanguage.zh ? '暂不' : 'Not now';
  String get cookieImportUnrecognized => _lang == AppLanguage.zh
      ? '没有识别出有效 Cookie，请粘贴导出的 JSON 或完整 Cookie。'
      : 'No valid cookies recognized. Paste exported JSON or a full cookie.';
  String get cookieImportAnonymous => _lang == AppLanguage.zh
      ? '这些 Cookie 不包含已登录的 DeviantArt 会话（缺少 userinfo）。'
      : 'These cookies contain no signed-in DeviantArt session (no userinfo).';
  String cookieImportConflict(String account) => _lang == AppLanguage.zh
      ? '导入的会话属于 $account，与当前登录账号不同。切换账号请先退出登录，不能同时登录两个账号。'
      : 'The imported session belongs to $account, a different account. Sign out first to switch accounts — two accounts cannot be signed in at once.';
  String get cookieImportVerifyFailed => _lang == AppLanguage.zh
      ? 'Cookie 未被 DeviantArt 接受，可能已过期或无效；已恢复原会话。'
      : 'DeviantArt did not accept these cookies — they may be expired or invalid. The previous session was restored.';
  String get cookieImportUnavailable => _lang == AppLanguage.zh
      ? '当前无法写入会话（网页环境未就绪），请稍后重试。'
      : 'The session store is not ready yet. Try again shortly.';
  String get aboutDAViewer =>
      _lang == AppLanguage.zh ? '关于 DAViewer' : 'About DAViewer';
  String get aboutDescription => _lang == AppLanguage.zh
      ? '一个基于 DAKit 的第三方 DeviantArt 客户端。'
      : 'A third-party DeviantArt client built on DAKit.';

  // --- proxy settings ---
  String get proxyCurrentDirect =>
      _lang == AppLanguage.zh ? '当前生效：直连 DIRECT' : 'Current: Direct';
  String proxyCurrentConfigured(String hostPort) => _lang == AppLanguage.zh
      ? '当前生效：PROXY $hostPort'
      : 'Current: PROXY $hostPort';
  String get proxyHint => _lang == AppLanguage.zh
      ? '如果当前网络能直连 DeviantArt，请保持自动检测，无需填写。连接失败时，可填写代理软件实际显示的 HTTP 或 Mixed 监听地址；设置会保存并覆盖全 App。'
      : 'Leave auto-detect enabled when DeviantArt is directly reachable. If it is not, enter the HTTP or Mixed listener shown by your proxy app; the saved setting applies throughout DAViewer.';
  String get proxyAddressLabel =>
      _lang == AppLanguage.zh ? 'HTTP 代理地址' : 'HTTP proxy address';
  String get proxyAddressExample => _lang == AppLanguage.zh
      ? '例如：127.0.0.1:你的代理端口'
      : 'Example: 127.0.0.1:YOUR_PORT';
  String get proxyAddressMobileHelp => _lang == AppLanguage.zh
      ? '端口不是固定的，请以代理 App 显示的 HTTP/Mixed 端口为准。代理运行在本手机时用 127.0.0.1；运行在电脑或路由器时，请填写其局域网 IP，并在代理端开启“允许局域网”。'
      : 'The port is not fixed—use the HTTP/Mixed port shown by your proxy app. Use 127.0.0.1 only when the proxy runs on this phone. For a computer/router proxy, use its LAN IP and enable LAN access.';
  String get proxyAddressDesktopHelp => _lang == AppLanguage.zh
      ? '端口不是固定的，请填写代理软件实际显示的 HTTP/Mixed 端口；127.0.0.1 仅表示代理运行在本机。'
      : 'The port is not fixed. Use the HTTP/Mixed port shown by your proxy app; 127.0.0.1 means the proxy runs on this device.';
  String get apply => _lang == AppLanguage.zh ? '应用' : 'Apply';
  String get restoreAutoDetect =>
      _lang == AppLanguage.zh ? '恢复自动检测' : 'Restore auto-detect';
  String get restoredAutoDetect =>
      _lang == AppLanguage.zh ? '已恢复自动检测' : 'Restored auto-detect';
  String get invalidProxyFormat => _lang == AppLanguage.zh
      ? '格式应为 host:port 或 http://host:port；端口请填写你的代理软件实际显示值'
      : 'Use host:port or http://host:port, with the actual port shown by your proxy app';
  String invalidProxyPort(String port) =>
      _lang == AppLanguage.zh ? '端口无效：$port' : 'Invalid port: $port';
  String appliedProxy(String hostPort) =>
      _lang == AppLanguage.zh ? '已应用代理 $hostPort' : 'Applied proxy $hostPort';
  String get proxySourceManual =>
      _lang == AppLanguage.zh ? '来源：App 手动设置' : 'Source: App setting';
  String get proxySourceSystem =>
      _lang == AppLanguage.zh ? '来源：系统代理' : 'Source: System proxy';
  String get proxySourceEnvironment => _lang == AppLanguage.zh
      ? '来源：环境变量（all_proxy / https_proxy）'
      : 'Source: Environment (all_proxy / https_proxy)';
  String get proxySourceBuild =>
      _lang == AppLanguage.zh ? '来源：构建参数' : 'Source: Build setting';
  String get proxySourceDirect =>
      _lang == AppLanguage.zh ? '来源：未检测到代理' : 'Source: No proxy detected';
  String get testConnection => _lang == AppLanguage.zh
      ? '测试 DeviantArt 连接'
      : 'Test DeviantArt connection';
  String get saveAndTest => _lang == AppLanguage.zh ? '保存并测试' : 'Save and test';
  String get testingConnection =>
      _lang == AppLanguage.zh ? '正在测试…' : 'Testing…';
  String proxyTestSucceeded(int milliseconds) => _lang == AppLanguage.zh
      ? '连接成功（${milliseconds}ms），App 内的 API、图片、下载和登录页都将使用此网络路径。'
      : 'Connected (${milliseconds}ms). In-app API, image, download, and sign-in traffic will all use this route.';
  String get proxyTestFailed => _lang == AppLanguage.zh
      ? '连接失败。请确认代理软件已启动、端口正确，并允许局域网/本机连接。'
      : 'Connection failed. Check that the proxy is running, the port is correct, and local connections are allowed.';
  String get directConnectionReady => _lang == AppLanguage.zh
      ? 'DeviantArt 直连可用，无需设置代理。'
      : 'DeviantArt is directly reachable; no proxy is needed.';
  String proxyConnectionReady(String address) => _lang == AppLanguage.zh
      ? '已通过 $address 连接 DeviantArt。'
      : 'DeviantArt is reachable through $address.';
  String get connectionNeedsAttention => _lang == AppLanguage.zh
      ? '当前无法连接 DeviantArt。如果你的网络无法直连，请设置自己的 HTTP 代理后重试。'
      : 'DeviantArt is not reachable right now. If your network blocks direct access, configure your own HTTP proxy and retry.';
  String get savedButTestFailed => _lang == AppLanguage.zh
      ? '代理已保存，但测试失败。请核对代理 App 的 HTTP/Mixed 端口；跨设备时还要核对局域网 IP 和“允许局域网”。'
      : 'The proxy was saved, but the test failed. Check the HTTP/Mixed port; for another device also check its LAN IP and LAN-access setting.';
  String get proxyMacLegacyHint => _lang == AppLanguage.zh
      ? 'macOS 12/13 无法将 App 内手动代理注入网页；请改用 macOS 系统代理。登录在内嵌网页中完成，遵循同一网络路径。'
      : 'On macOS 12/13, an app-only proxy cannot be injected into web views; use the macOS system proxy. Sign-in happens in the embedded web view on the same network path.';

  // --- diagnostics ---
  String get noLogFile =>
      _lang == AppLanguage.zh ? '（暂无日志文件）' : '(No log file yet)';
  String logReadFailed(Object error) =>
      _lang == AppLanguage.zh ? '读取日志失败：$error' : 'Failed to read log: $error';
  String get noErrorsThisRun =>
      _lang == AppLanguage.zh ? '本次运行无错误' : 'No errors this run';
  String errorsThisRun(int count) => _lang == AppLanguage.zh
      ? '本次运行记录到 $count 个错误'
      : 'Logged $count errors this run.';
  String logDirectory(String dir) =>
      _lang == AppLanguage.zh ? '日志目录：\n$dir' : 'Log directory:\n$dir';

  // --- folders ---
  String get emptyFolder => _lang == AppLanguage.zh ? '空画集' : 'Empty folder';
  String get folder => _lang == AppLanguage.zh ? '画集' : 'Folder';
  String get permissionDeniedWatch => _lang == AppLanguage.zh
      ? '权限不足，请退出登录后重新登录以获取关注权限。'
      : 'Permission denied. Please sign out and sign in again to get watch permission.';

  // --- notifications ---
  String get unknownUser => _lang == AppLanguage.zh ? '未知用户' : 'Unknown user';
  String get notifPermissionError => _lang == AppLanguage.zh
      ? '登录授权已过期或缺少「通知」权限，请退出登录后重新登录一次。'
      : 'Your login is missing the notifications permission. Please log out and log back in once.';

  String notificationTypeLabel(String type) {
    final zh = _lang == AppLanguage.zh;
    return switch (type) {
      'watched' || 'watch' => zh ? '关注了你' : 'watched you',
      'deviation' ||
      'new_deviation' ||
      'posted' => zh ? '更新了作品' : 'posted new work',
      'deviation_faved' ||
      'faved' ||
      'favourited' => zh ? '收藏了你的作品' : 'favourited your work',
      'deviation_comment' ||
      'comment_deviation' ||
      'comment' => zh ? '评论了你的作品' : 'commented on your work',
      'mention' || 'mention_deviation' => zh ? '提到了你' : 'mentioned you',
      'collection' || 'added_to_collection' =>
        zh ? '把你的作品加入收藏集' : 'added your work to a collection',
      'journal' || 'journal_faved' => zh ? '发布了日志' : 'posted a journal',
      'gift' => zh ? '送了你礼物' : 'sent you a gift',
      'note' => zh ? '给你发了私信' : 'sent you a note',
      'llama' => zh ? '送你一个 Llama' : 'gave you a Llama',
      'status' || 'status_update' => zh ? '更新了状态' : 'updated their status',
      _ => zh ? '更新了动态' : 'posted an update',
    };
  }

  String relativeTime(DateTime? time) {
    if (time == null) return '';
    final zh = _lang == AppLanguage.zh;
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return zh ? '刚刚' : 'now';
    if (diff.inHours < 1) {
      return zh ? '${diff.inMinutes} 分钟前' : '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return zh ? '${diff.inHours} 小时前' : '${diff.inHours}h ago';
    }
    if (diff.inDays < 30) {
      return zh ? '${diff.inDays} 天前' : '${diff.inDays}d ago';
    }
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month-$day';
  }

  // --- transfers / downloads ---
  String get viewDetail => _lang == AppLanguage.zh ? '查看详情' : 'View details';
  String get transferDone => _lang == AppLanguage.zh ? '已完成' : 'Done';
  String get transferDownloading =>
      _lang == AppLanguage.zh ? '下载中' : 'Downloading';
  String get transferPaused => _lang == AppLanguage.zh ? '已暂停' : 'Paused';
  String get transferFailed => _lang == AppLanguage.zh ? '失败' : 'Failed';
  String get transferNotFound =>
      _lang == AppLanguage.zh ? '源文件失效' : 'Source unavailable';
  String get transferCancelled => _lang == AppLanguage.zh ? '已取消' : 'Cancelled';
  String get transferQueued => _lang == AppLanguage.zh ? '排队中' : 'Queued';

  // --- watching ---
  String get watching => _lang == AppLanguage.zh ? '关注用户' : 'Watching';
  String get noWatchedUsers =>
      _lang == AppLanguage.zh ? '尚未关注任何用户' : 'No watched users';
  String get watchListPermissionError => _lang == AppLanguage.zh
      ? '获取关注列表失败：权限不足。\n请退出登录后重新登录，以获取最新权限。'
      : 'Permission denied. Please sign out and sign in again.';

  // --- artist ---
  String get watchStateOn => _lang == AppLanguage.zh ? '已关注' : 'Following';
  String get watchStateOff => _lang == AppLanguage.zh ? '关注' : 'Watch';
  String get journal => _lang == AppLanguage.zh ? '文章' : 'Journal';
  String get artistWorks => _lang == AppLanguage.zh ? '作品' : 'Works';
  String get artistSavedWorks =>
      _lang == AppLanguage.zh ? '收藏作品' : 'Saved works';
  String get folders =>
      _lang == AppLanguage.zh ? '画集与收藏夹' : 'Sets & collections';
  String get galleryFolders => _lang == AppLanguage.zh
      ? '画集 · 作者自己的作品分类'
      : 'Sets · the artist’s own work';
  String get favouriteFolders => _lang == AppLanguage.zh
      ? '收藏夹 · 作者收藏的他人作品'
      : 'Collections · work saved by the artist';
  String get noJournals => _lang == AppLanguage.zh ? '暂无文章' : 'No journals';
  String get noFolders => _lang == AppLanguage.zh ? '暂无分类' : 'No folders';
  String get emptyFolderBadge => _lang == AppLanguage.zh ? '空画集' : 'Empty';
  String folderArtworkCount(int count) =>
      _lang == AppLanguage.zh ? '$count 作品' : '$count artworks';
  String artistStats(int deviations, int favourites, [int? watchers]) {
    final base = _lang == AppLanguage.zh
        ? '$deviations 作品 · $favourites 收藏'
        : '$deviations deviations · $favourites favourites';
    if (watchers == null) return base;
    return _lang == AppLanguage.zh
        ? '$base · $watchers 关注者'
        : '$base · $watchers watchers';
  }

  String artistJoinDate(DateTime date) =>
      _lang == AppLanguage.zh ? '加入于 ${date.year}' : 'Joined ${date.year}';

  String get searchInGallery =>
      _lang == AppLanguage.zh ? '搜索该作者的作品' : 'Search this gallery';

  String get noGallerySearchResults =>
      _lang == AppLanguage.zh ? '没有匹配的作品' : 'No matching works';

  String get clearSearch => _lang == AppLanguage.zh ? '清除搜索' : 'Clear search';

  // --- search ---
  String get searchHint => _lang == AppLanguage.zh
      ? '搜索作品 / 用户，或用 #标签 搜标签'
      : 'Search artworks, users, or #tags';
  String get clear => _lang == AppLanguage.zh ? '清空' : 'Clear';
  String get clearHistory => _lang == AppLanguage.zh ? '清除' : 'Clear';
  String get artworks => _lang == AppLanguage.zh ? '作品' : 'Artworks';
  String get users => _lang == AppLanguage.zh ? '用户' : 'Users';
  String get sort => _lang == AppLanguage.zh ? '排序' : 'Sort';
  String get sortDefault => _lang == AppLanguage.zh ? '默认' : 'Default';
  String get sortNewest => _lang == AppLanguage.zh ? '最新' : 'Newest';
  String get sortPopular => _lang == AppLanguage.zh ? '热门' : 'Popular';
  String get popularTags => _lang == AppLanguage.zh ? '热门标签' : 'Popular tags';
  String get discover => _lang == AppLanguage.zh ? '去发现' : 'Discover';
  String get discoverArtists =>
      _lang == AppLanguage.zh ? '发现并关注' : 'Find creators';
  String get popularTagsHint =>
      _lang == AppLanguage.zh ? '点击标签浏览该标签下的作品' : 'Tap a tag to browse it';
  String get searchIdleHint => _lang == AppLanguage.zh
      ? '输入关键词搜索作品，或输入 #标签 浏览标签。'
      : 'Search artworks, or type #tag to browse a tag.';
  String get recent => _lang == AppLanguage.zh ? '搜索记录' : 'Recent';
  String get noUsersFound =>
      _lang == AppLanguage.zh ? '无搜索结果' : 'No users found';

  // --- tag ---
  String get relatedTags => _lang == AppLanguage.zh ? '相关标签' : 'Related tags';
  String get moreLikeThis =>
      _lang == AppLanguage.zh ? '更多类似作品' : 'More like this';
  String get featuredInCollections =>
      _lang == AppLanguage.zh ? '已被收录' : 'Featured in collections';
  String get suggestedCollections =>
      _lang == AppLanguage.zh ? '建议收藏集' : 'Suggested collections';
  String get collectionOpenOnWeb =>
      _lang == AppLanguage.zh ? '在网页查看收藏集' : 'Open collection on the web';
  String get collectionEmpty => _lang == AppLanguage.zh
      ? '这个收藏集还没有可显示的作品。'
      : 'This collection has no artwork to show yet.';
  String get collectionLoadFailed => _lang == AppLanguage.zh
      ? '收藏集加载失败，请检查网络后重试。'
      : 'Could not load the collection. Check your network and retry.';
  String moreFromArtist(String username) =>
      _lang == AppLanguage.zh ? '更多 · $username' : 'More from $username';
  String get similarArtists =>
      _lang == AppLanguage.zh ? '相似画师' : 'Similar artists';
  String get multiImageBadge => _lang == AppLanguage.zh ? '多图' : 'MULTI';
  String get collectionBadge => _lang == AppLanguage.zh ? '收藏集' : 'COLLECTION';
  String get moreLikeThisLoadFailed =>
      _lang == AppLanguage.zh ? '更多类似作品加载失败' : 'Could not load similar artwork';
  String get moreLikeThisLoading =>
      _lang == AppLanguage.zh ? '正在寻找更多类似作品…' : 'Finding more similar artwork…';
  String get noMoreLikeThis => _lang == AppLanguage.zh
      ? '暂时没有找到更多类似作品。你可以稍后再检查，推荐结果可能会更新。'
      : 'No more similar artwork was found yet. Check again later as recommendations may update.';
  String get checkSuggestions =>
      _lang == AppLanguage.zh ? '检查更新' : 'Check again';
  String get moreLikeThisChecking =>
      _lang == AppLanguage.zh ? '正在检查…' : 'Checking…';
  String get moreLikeThisStillEmpty => _lang == AppLanguage.zh
      ? '已检查最新推荐，目前没有新结果。'
      : 'The latest recommendations were checked; there are no new results.';
  String get moreLikeThisUnchanged => _lang == AppLanguage.zh
      ? '已重新检查，当前类似作品没有变化。'
      : 'Checked again; suggestions are unchanged.';
  String moreLikeThisUpdated(int count) => _lang == AppLanguage.zh
      ? '已更新，找到 $count 个类似作品。'
      : 'Updated with $count similar artwork${count == 1 ? '' : 's'}.';
  String get moreLikeThisRecovering => _lang == AppLanguage.zh
      ? '相关推荐暂时中断，正在自动恢复…'
      : 'Suggestions were interrupted. Recovering automatically…';
  String get moreLikeThisNetworkFailure => _lang == AppLanguage.zh
      ? '网络连接失败，自动重试后仍无法加载。请检查代理或网络。'
      : 'The network failed after an automatic retry. Check your connection or proxy.';
  String get moreLikeThisSessionFailure => _lang == AppLanguage.zh
      ? 'DeviantArt 登录会话已失效，重新登录后即可恢复。'
      : 'Your DeviantArt session expired. Sign in again to restore suggestions.';
  String get moreLikeThisServiceFailure => _lang == AppLanguage.zh
      ? 'DeviantArt 暂时不可用或限制了请求，作品详情本身不受影响。'
      : 'DeviantArt is temporarily unavailable or limiting requests. Artwork details still work.';
  String get moreLikeThisFormatFailure => _lang == AppLanguage.zh
      ? '相关推荐暂时加载不完整，稍后再试即可。作品详情不受影响。'
      : 'Similar artwork did not finish loading. Try again later; artwork details are unaffected.';
  String get moreLikeThisUnknownFailure => _lang == AppLanguage.zh
      ? '相关推荐暂时不可用，作品详情本身仍可正常浏览。'
      : 'Suggestions are temporarily unavailable. Artwork details still work.';
  String get reloadSuggestions => _lang == AppLanguage.zh ? '重新加载' : 'Reload';

  // --- OAuth configuration errors (developer-facing) ---
  String get oauthClientIdMissing => _lang == AppLanguage.zh
      ? 'OAuth 登录需要配置 DAKIT_CLIENT_ID。'
      : 'OAuth login requires DAKIT_CLIENT_ID.';
  String get oauthClientIdInvalid => _lang == AppLanguage.zh
      ? 'DAKIT_CLIENT_ID 无效或未在 DeviantArt 注册。\n'
            '请在 deviantart.com/settings/applications 注册一个 '
            'Public OAuth 应用，并把 client_id 通过 '
            '--dart-define=DAKIT_CLIENT_ID=你的ID 传入。'
      : 'DAKIT_CLIENT_ID is invalid or not registered with DeviantArt.\n'
            'Register a Public OAuth app at deviantart.com/settings/applications '
            'and pass the client_id via --dart-define=DAKIT_CLIENT_ID=YOUR_ID.';
}
