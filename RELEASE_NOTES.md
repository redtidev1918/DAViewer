# 发布说明 / Release notes

这里只写下载者需要知道的变化，一行一条。内部实现、协议与调试细节请见
`CHANGELOG.md`。

## 0.5.0

- 修复首页推荐下拉刷新过慢：下拉直接刷新推荐流，不再先做一次 WAF 敏感的首页探测（每次省约 1.5 秒）；失效会话仍会明确提示重新登录。
- 修复订阅/付费作品的锁标丢失：推荐流与详情的合并不再用缺少访问信息的后续数据覆盖已确认的订阅锁，卡片锁标与详情订阅提示稳定保留。
- 修复网页登录 challenge 循环：人机验证尝试超限后停止自动重载，不再无限重试触发验证。
- 新增网页会话未确认提示：会话未经服务端确认时首页明确提醒登录并刷新 Cookie，不再静默匿名。
- 新增推荐请求耗时与每页锁定作品计数诊断日志。

- Fixes slow pull-to-refresh on the recommendation feed: refresh goes straight to the rfy request instead of a WAF-sensitive home-page probe first.
- Fixes lost subscription locks: feed-to-detail merging no longer overwrites a confirmed subscription gate with later payloads lacking access metadata.
- Fixes the web-login challenge loop: the page stops auto-reloading after the bot-check attempt limit is exceeded.
- Adds an explicit "web session not yet confirmed" reminder on Home instead of silently going anonymous.
- Adds diagnostic logs with request timing and a per-page count of gated artworks.

## 0.4.16

- 增加 Cookie 生命周期诊断：登录、分页、启动恢复和服务端验证前后记录数量/名称/domain/fingerprint，不记录 Cookie 值。

- Adds Cookie lifecycle diagnostics (counts, names, domains, SHA-256 fingerprints only) around login, pagination, startup restore and server verification.

## 0.4.14

- 锁定/需要订阅的作品在预览卡显示锁图标，详情页标题下方明确提示查看受限原因，不再与 NSFW 打码混淆。
- 修复更新 APK 后偶发黑屏：代理、WebView、OAuth/网页会话恢复超时后仍会进入主界面。

- Locked or subscription-gated artwork now shows a lock badge and an explicit detail-page reason, separate from NSFW blur.
- Fixes occasional black screen after an APK update with bounded startup budgets.

## 0.4.15

- 修复更新 APK 后 Cookie 恢复完成前被误判为匿名：恢复完成后会自动重新服务端验证并刷新首页推荐。

- Fixes cookie loss after an APK update: the restored web session is re-verified with the server and the home feed refreshes automatically.

## 0.4.13

- 修复“有更新但暂无更新说明”：GitHub API 正常时读取 Release 正文；API 限流时改用 HTML 重定向确认版本，并从仓库 `RELEASE_NOTES.md` 读取对应版本说明。

- Fixes “update available but no release notes”: uses the GitHub API body first, then falls back to the release redirect plus `RELEASE_NOTES.md`.

## 0.4.12

- 修复“登录成功但设置/每日精选/关注仍显示未登录”：重新打开登录页会取消陈旧 OAuth 事务并新建流程；首次登录不会在只确认网页 Cookie 时提前关闭。
- 首页个性化推荐的网页会话改为 DeviantArt 首页服务端验证；匿名或过期 Cookie 会明确提示登录并更新 Cookie。
- 显式退出登录后不会再被遗留 token 复活；进入网页登录页会先校验 OAuth 是否仍有效。
- 登录成功后 OAuth 状态统一收敛，每日精选/关注/收藏/通知等依赖账号的页面会自动重新拉取数据；旧账号加载无法在登出后恢复 signedIn。

- Fixes “login succeeded but Settings / Daily / Watched still show signed out”: reopening the login screen starts a fresh OAuth flow and waits for OAuth before closing.
- Personalized home recommendations now verify the web session against the DeviantArt home page.
- An explicit logout can no longer be undone by a leftover local token on the next launch.
- OAuth success now propagates through AuthController so account-backed pages refetch together, and stale account loads cannot resurrect sign-in after logout.

## 0.4.10

- 修复首页推荐会话恢复：登录成功后再也不要求重登，冷启动不再被验证请求卡成无限刷新。
- 登录页只在 DeviantArt 跳转登录后首页后关闭，失效 Cookie 会让推荐流明确报错而不是假登录。
- macOS 支持鼠标/触控板拖动多图与横向作品排布。
- “更多画师作品”改为专用紧凑卡片，修复竖图 overflow 与空白。
- 首页重试按钮现在真正重新发起服务端会话检查和推荐请求。
- 更新检查不再依赖匿名 GitHub API，避免限流导致“已是最新版本”。

- Fixes homepage recommendation session restore: no forced re-login after a confirmed login, and cold start no longer freezes on verification.
- Login closes only after DeviantArt redirects to the signed-in home page; expired cookies surface as an explicit feed error.
- Adds macOS mouse/trackpad drag support for multi-image paging and horizontal artwork rails.
- Replaces the More From Artist rail with a dedicated compact card, fixing portrait overflow and blank space.
- Home Retry now really re-runs session verification and reloads recommendations.
- Update checks no longer depend on the anonymous GitHub API, so rate limits cannot cause a false “already up to date”.

## 0.4.0

- 新增本地访问历史：最近浏览的作品自动去重记录，最多保留 200 条；历史只保存在本机，不上传或同步。
- 访问历史从底部导航改为搜索页右上角入口，底部导航保留更常用的页面。

- Adds local artwork visit history: recently viewed artworks are deduplicated and capped at 200 entries. History stays on-device and is never uploaded or synced.
- Visit history now opens from the Search app bar instead of occupying a bottom-navigation slot.

## 0.3.0

- 集中下载规划；作品补全状态更明确；新增来源协调器和策略化搜索路由；升级 DAKit 1.0.0。
- 移除应用内重复网页协议解析，统一使用 `dakit_web`；WebView 登录和会话仍由 DAViewer 负责。

- Centralizes download planning, clarifies artwork hydration states, adds a source coordinator with policy-driven search routing, and upgrades to DAKit 1.0.0.
- Removes duplicated in-app web-protocol parsing by reusing `dakit_web`; WebView sign-in and sessions remain owned by DAViewer.

## 0.2.184

- 同步底层 DAKit 到最新版（API/Core 0.2.0、Flutter 适配包 0.1.13），修复多图作品附加页原图的获取与下载，应用本身界面无变化。

- Updated the underlying DAKit SDK to the latest version (API/Core 0.2.0, Flutter bridge 0.1.13); this fixes fetching and downloading original files for the extra pages of multi-image works. No visible interface changes.

## 0.2.183

- 设置新增「账号 Cookie」：可以查看当前登录会话 Cookie、一键复制导出，也可以把 Cookie 粘贴导入，在新设备或重新安装后直接恢复登录，不用重新走登录流程。
- 导入只接受与当前账号一致的会话：切换账号需要先退出登录，应用绝不会把两个不同账号的登录态混在一起；无效或过期的 Cookie 会被拒绝并自动恢复原状。
- 仅导入 Cookie 后推荐流即可使用；关注、通知、收藏和下载原图等功能仍需要官方授权登录一次，应用会在导入后主动引导，登录页会识别已导入的会话，通常无需再输入账号密码。

- Settings has a new “Account cookies” entry: view your current session cookies, copy/export them with one tap, or paste cookies to restore your sign-in on a new device or after a reinstall — no need to sign in again.
- Import only accepts a session matching the current account: switching accounts still requires signing out first, and the app never mixes two different accounts together; invalid or expired cookies are rejected and the previous session is restored automatically.
- Cookies alone power your recommendations; following, notifications, favourites, and original downloads still need one official authorization. The app offers it right after import, and the sign-in page recognizes the imported session — usually without asking for a password.

## 0.2.182

- 原图不可下载时，详情页只显示一行原因说明，不再出现会误认为按钮的大块「不能下载」面板；可保存展示图时显示带文字的下载按钮。
- 长按图片下载前会先确认，避免误触；确认后仍会提示实际保存位置。

- When the original file cannot be downloaded, details now show a one-line reason instead of a large "cannot download" panel that looks like a button; a labeled download button appears when a saveable image is available.
- Long-pressing an image asks for confirmation before downloading, and the saved-location message still appears afterwards.

## 0.2.181

- 下载按钮缩小为简洁图标，减少对作品详情页面的视觉干扰。
- 图片保存到系统下载目录后会显示完成提示和保存位置。

- The download action is now a compact icon that keeps artwork details visually clean.
- A completion message now shows the saved location after the image reaches the system Downloads folder.

## 0.2.180

- 全屏查看图片时，现在可以长按当前图片单独下载；多图作品可逐张选择。
- 重复长按会显示已有下载状态，失败或取消的任务可直接重新下载。

- Long-press the current image in the full-screen viewer to download it individually, including a selected page from a multi-image work.
- Repeated long-presses now show the existing transfer state, while failed or cancelled transfers can be downloaded again.

## 0.2.179

- 修复详情页视频在退出或跳转到其他页面后仍在后台播放的问题，不再空耗流量和电量；返回该页面时视频会自动继续播放。

- Fixed the detail-page video keeping playing in the background after exiting or navigating to another page; returning to the page resumes playback automatically.

## 0.2.178

- 作品详情页现在显示发布时间和更新时间（相对时间），编辑过的作品会标出「更新于」。
- 关注动态刷新后按作品最新更新时间排序，刚更新或新发布的作品排在最前。
- 详情页视频现在自动播放并循环。

- Artwork details now show the publish and update times as relative timestamps; edited works are marked with an "Updated" row.
- The Watched feed is ordered by latest update time after each refresh, so newly updated or posted work comes first.
- Videos on the detail page now autoplay and loop.

## 0.2.177

- 修复查看作品详情后返回推荐页时列表突然刷新、阅读位置丢失的问题。
- 自动刷新现在只会在应用离开较久、推荐页可见且位于顶部附近时静默执行；查看详情、浏览其他标签或深度滚动时保持当前内容。

- Fixed the recommendation feed unexpectedly refreshing and losing its reading position after returning from artwork details.
- Automatic refresh now runs silently only after a longer absence when Recommendations is visible and near the top; viewing details, using another tab, or browsing deeper keeps the current content intact.

## 0.2.176

- 修复多图作品点开大图后无法左右翻页的问题；详情页、多图预览和全屏大图现在各自拥有明确的滑动手势，不再互相抢占。
- 到达多图首尾页后，需要再次向外滑动才会切换作品，避免一次手势误触发两层导航。
- 大图中的返回、缩放和翻页控件会自动隐藏，轻点画面可重新显示；图片放大后滑动只用于平移。
- 收藏夹与通知入口现在会保留完整浏览顺序，上一件/下一件作品导航保持一致。
- 加固更新后的登录 Cookie 恢复：临时读取失败不再覆盖有效备份，快照采用原子写入。

- Fixed multi-image works not paging after opening the full-screen viewer. Detail navigation, inline media paging, and full-screen paging now have explicit, non-competing gesture ownership.
- Reaching the first or last image now requires a separate outward swipe to change artworks, preventing one gesture from triggering two navigation layers.
- Full-screen back, zoom, and paging controls auto-hide and return on tap; panning a zoomed image never changes pages.
- Collection and notification entry points now preserve their complete browsing sequence for consistent previous/next navigation.
- Hardened post-update cookie recovery: transient reads no longer overwrite a valid backup, and snapshots are written atomically.

## 0.2.175

- 全屏大图查看器新增**左右翻页箭头按钮**——不依赖手势系统，始终可见可点击。

- Full-screen viewer now has visible left/right arrow buttons — always tappable, not gesture-dependent.

## 0.2.174

- 修复多图作品在全屏查看器中缩放后无法返回翻页模式的问题。
- 全屏查看器完整支持多图翻页与滑动切换作品的组合操作。

- Fixed multi-image works losing PageView after zooming in the full-screen viewer.
- Full-screen viewer now supports multi-image paging combined with swipe-to-navigate.

## 0.2.173

- 全屏大图查看器新增滑动诊断日志（如仍有滑动问题可通过日志与诊断页导出定位）。

- Full-screen viewer now logs swipe diagnostics to help pinpoint any remaining navigation issues.

## 0.2.172

- 修复全屏查看大图时左右滑动无反应的问题：滑动现在可以正常切换到上一个/下一个作品。

- Fixed the full-screen viewer not responding to horizontal swipes: swiping left/right now correctly navigates to the previous or next artwork.

## 0.2.171

- 首页右上角新增通知铃铛：未读消息显示数字角标，点击进入消息中心（未读红点 + 本地已读）。

- A notification bell on the Home screen shows an unread badge and opens the message center (unread dot + local mark-as-read).

## 0.2.170

- 兑现文档承诺：登录页右上角新增设置入口，登录异常时也可进入语言、网络代理、日志与诊断、检查更新和关于。

- Documented promise fulfilled: the login screen now has a settings entry, so language, proxy, diagnostics, updates, and About stay reachable even when sign-in is broken.

## 0.2.169

- 登录成功后自动返回应用，无需再点「完成」。
- 修复部分网络下官方接口请求无限转圈的问题：请求超时会明确提示，不再一直加载。

- After signing in, the app returns automatically — no need to tap Done.
- Fixed official-API requests hanging forever on some networks: they now time out with a clear error.

## 0.2.168

- 修复更新 App 后「推荐」消失、需要重新登录的问题：登录 Cookie 现在会保存并在更新后自动恢复。

- Fixed the personalized feed disappearing after an app update: your sign-in cookies are now saved and restored automatically — no re-login needed.

## 0.2.167

- 更新提醒现在会展示更新内容：点一下首页的更新横幅即可查看本次更新说明，再决定是否下载。
- 更新检查失败后不再等一小时，下次启动或回到前台会自动重试。

- Update reminders now show what's new: tap the Home banner to read the release notes before downloading.
- A failed update check retries on the next launch or foreground resume instead of waiting an hour.

## 0.2.166

- 移除画师页的 Scraps 标签（官网画师导航没有 Scraps，且大部分画师不使用）。

- Removed the artist Scraps tab (the official artist navigation has no Scraps, and most artists never use it).

## 0.2.165

- 画师页的 Scraps 标签移到最后一个位置（大部分画师不使用 Scraps）。

- The artist Scraps tab moved to the last position (most artists never use it).

## 0.2.164

- 修复画师页 Scraps 在网页会话缺失或过期时显示为空的问题（现在会自动刷新会话并重试）。
- 画集内搜索在会话失效时同样会自动恢复。

- Fixed the artist Scraps tab showing empty when the web session is missing or stale (the session is now refreshed and retried).
- Gallery search recovers the same way when the web session is stale.

## 0.2.163

- 搜索现在返回真实的 DeviantArt 搜索结果（官方 API 已移除搜索接口）。
- 画师页新增 Scraps 标签。
- 画师页可以搜索该作者自己的作品。
- 画师资料显示关注者数与加入时间。

- Search now returns real DeviantArt results (the official API removed its search endpoint).
- Artist page: new Scraps tab.
- Artist page: keyword search over the artist's own gallery.
- Artist profile shows watcher count and join date.

## 0.2.162

- 网络异常时不再把已登录状态误显示为未登录。
- 标签排序「最新 / 热门」现在真正生效（之前返回相同结果）。
- 搜索页：最近搜索移到最上面，并改为紧凑的标签样式。
- 「为你推荐」标签会记住你看过的作品，重启后仍然可用。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Sign-in is no longer shown as signed-out when the network is unavailable.
- Tag sorting (Newest / Popular) now actually differs.
- Search: recent searches moved to the top as compact chips.
- “Recommended for you” tags persist your viewing interests across restarts.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.161

- 搜索页「为你推荐」标签也显示作品预览图，按你的兴趣排序（最感兴趣的在最前）。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- “Recommended for you” tags on the search page now show artwork previews, ordered by your interests.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.160

- 更新提醒更灵敏：新版本发布后能更快看到提示（每小时检查 + 回到前台时检查）。
- 搜索页热门标签现在带作品预览图（Pixiv 风格）。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Update reminders appear sooner (hourly + on return to foreground).
- Popular tags on the search page now show an artwork preview (Pixiv style).

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.159

- 标签页新增「最新 / 热门」排序；搜索结果新增「最新优先」排序。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Tag pages now sort by Newest or Popular; search results can be ordered newest-first.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.158

- 作品卡片的标题和作者名移到图片下方，不再遮挡图片。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Artwork card titles and author names now sit below the image instead of covering it.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.157

- 修复通过链接打开作品报错的问题（数字链接现在能正常打开详情，含 R18）。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed opening artworks from pasted links (numeric links now load the detail page, including R18).

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.156

- 修复通过链接打开 R18 作品时报错「api endpoint not found」的问题。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed “api endpoint not found” when opening an R18 artwork from a pasted link.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.155

- 关注动态顶部会显示更多关注用户，不再只有零星几个。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- The Watched tab now surfaces many more watched artists at the top.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.154

- 登录成功后立即显示「登录成功」界面（正在同步登录状态），不再停留在登录页让首次用户困惑。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Shows a “Signed in — syncing your session” screen right after sign-in instead of lingering on the login page.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.153

- 修复登录状态偶尔在重启后丢失、又要重新登录的问题。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed the sign-in occasionally being lost after a restart (no more forced re-login).

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.152

- 进一步优化登录页弹出键盘时的卡顿。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Further reduced sign-in page lag when the keyboard opens.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.151

- 登录成功时显示「登录成功」提示。
- 登录失败时在登录页显示具体原因，不再静默失败。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Shows a “Signed in” toast after a fresh sign-in.
- Sign-in failures now display the reason on the login page instead of failing silently.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.150

- 修复重启后又要重新登录的问题：登录状态现在会在下次打开时恢复。
- 推荐流在登录会话过期时会自动刷新并重试，不再一直转圈。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed having to sign in again after restarting the app; the session is restored on the next launch.
- Recommendations now refresh their session and retry instead of spinning forever.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.149

- 修复登录完成后出现黑屏的问题。
- 登录页增加提示：如页面出现人机验证，请按页面提示完成。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed the black screen appearing after sign-in completes.
- Sign-in now shows a hint when a human-verification challenge appears.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.148

- 修复登录后「推荐」不显示、点击登录一直跳回首页的问题。
- 修复从「关注动态」等标签页登录后没有回到原页面的问题。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed recommendations not appearing after sign-in (tapping sign-in kept bouncing back to Home).
- Fixed sign-in from the Watched tab returning to the wrong page.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.147

- 修复登录页弹出键盘时卡顿、掉帧的问题。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed the sign-in page lagging and dropping frames when the keyboard opens.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.146

- 修复 Android 版本点击后闪退、打不开的问题（包名变更后主界面类未同步迁移）。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Fixed the Android build crashing on launch (the entry activity wasn't moved to the new package name).

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.145

- 首页新增轻量更新提醒：有新版本时显示可关闭的提示条，被忽略的版本不再打扰。
- 「日志与诊断」页新增「报告问题」：在你的浏览器里打开预填好的 GitHub Issue，可选附带脱敏日志；App 不会自动上传任何数据。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Home now shows a slim, dismissible banner when a newer version is available; ignored versions won't nag again.
- Diagnostics gains “Report a problem”: opens a pre-filled GitHub issue in your browser with an optional redacted log; the app never uploads anything automatically.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.144

- 首页「推荐」恢复为网页版个性化推荐流，与官网推荐一致。
- 清理登录与网络设置中残留的“系统浏览器”旧文案。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Home “For you” is back to the website's personalized recommendation feed.
- Removed stale “system browser” wording from sign-in and network settings.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.143

- 作者主页、画廊分组、收藏集和标签页现在都能直接分享。
- 修复退出登录或切换账号后，首页、收藏和通知仍显示上一账号内容的问题。
- 登录失败时给出可执行的提示，不再显示 “Unable to access” 之类的内部错误。
- 已登录用户误入登录页时会自动回到首页。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Share is now available from the artist, gallery folder, collection, and tag screens.
- Fixed stale content from a previous account remaining after logout or account switch.
- Login failures now show actionable guidance instead of internal errors like “Unable to access”.
- A signed-in user who lands on the login screen is sent back to Home.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.142

- 登录回到应用内网页：打开官方登录页一次即可，Google、Apple 等入口都在页面上。
- 支持分享作品、画师、画廊分组、收藏集和标签的公开链接。
- 首页「推荐」更正为「发现」：这是官方通用发现流。
- 应用标识改为中性名称：需卸载旧版后重新安装，并重新登录一次。

> macOS 测试版未走 Apple 官方审核流程，首次启动请在 Finder 中右键图标选择「打开」；App 不上传任何数据。

- Sign-in is back in-app: open the official login page once — Google, Apple, and other options are right on the page.
- Share public links for artworks, artists, gallery folders, collections, and tags.
- Home “For you” is renamed “Discover”: it is the official generic discovery feed.
- The app identifier is now neutral: uninstall the old build, reinstall, and sign in again.

> The macOS build is a community preview that has not gone through Apple's review (which requires a paid developer account). macOS may block the first launch — right-click the app icon in Finder and choose Open. The app never uploads or collects any data.

## 0.2.141

- 支持分享作品、画师、画廊分组、收藏集和标签；首页「推荐」更正为「发现」。

- Share public links for artworks, artists, gallery folders, collections, and tags; Home “For you” renamed “Discover”.

## 0.2.139

- 登录回到应用内网页：一次登录即可用于首页、收藏、关注和下载。

- Sign-in is back in-app: one sign-in covers Home, favourites, watch, and downloads.

## 0.2.138

- 登录改为单个入口，页面提供 Google、Apple、Facebook；登录一次即可用于首页、收藏、关注和下载。
- 失效登录自动恢复为未登录状态；网络设置区分 App 代理与系统浏览器代理。
- macOS 修复旧钥匙串弹出密码框的问题（升级后需重新登录一次）。

- Sign-in is now a single action with Google, Apple, and Facebook on the page; one sign-in covers Home, favourites, watch, and downloads.
- Expired sessions return to signed-out; network settings separate app and browser proxies.
- macOS no longer triggers the legacy Keychain password prompt (sign in again once after upgrade).

## 0.2.137

- 登录页入口去重；修复 Google 登录白屏、需登录两次和返回后一直等待的问题。
- 网络设置区分 App 代理与系统浏览器代理；修复 Windows 浏览器登录后无法返回客户端的问题。

- Deduplicated the sign-in actions; fixed Google sign-in showing a blank page, requiring a second attempt, or leaving the app waiting.
- Network settings distinguish app and browser proxies; fixed the Windows app not reopening after browser sign-in.
