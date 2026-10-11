# DAViewer 恢复任务验收报告

分支：`recovery/daviewer-local-edits`（基线 `6c0ecd4` = v0.5.12，未覆盖 `main`）
实现提交：`2c4b365`（依赖 pin：`7932954`）
环境：本机 Debian 13 / Flutter 3.47.7 stable，镜像 `pub.flutter-io.cn`

## 1. Root Cause

| 现象（Android 日志） | 已证实根因 |
|---|---|
| `user/whoami=200`、10 个 Cookie 已恢复，Dio `WebSessionVerifier` 仍返回 `anonymous` → `unverified` | Headless WebView 在**挑战页首次 `onLoadStop`** 即采样并销毁，未等待挑战通过后的 JavaScript 跳转与有效首页加载 |
| 进入可见 WebView 经一次挑战跳转后才 `healthy` | 同上：判据取自中间态页面 |
| RFY 成功后 Provider 由 id=1 重建为 id=2，第一页重复请求 | `web_login_screen.dart` 登录确认后显式 `ref.invalidate(personalizedFeedProvider)`，与健康转变恢复（`recoverInitialPage`）及会话身份 select 重建叠加；`refresh()` 无所有权概念，同一事务可重复发起 |
| Widget 测试 `A Timer is still pending even after the widget tree was disposed`；`explicit retry` 期望 1 实际 2；下拉刷新测试失败 | 首屏请求被缓存水合阻塞（fake-async 下文件 I/O 不返回）＋ `getApplicationSupportDirectory().timeout(3s)` 留下挂起定时器；自动恢复与显式刷新各发一次请求 |

## 2. Implementation

- `lib/core/auth/web_session_refresher.dart`：`WebSessionProbeObservation`；`onLoadStop` 结论不成立则继续等待跳转，上限 `_maxInconclusiveStops = 3`，到顶返回 unavailable（→ unverified），绝不返回 anonymous。
- `lib/core/feed/artwork_feed_controller.dart`：新增 `sessionContextKey`、`_firstPageFetched` / `_firstPageContextKey`；`refresh()` 幂等（合并在飞请求；当前页仍属同一 CSRF+Cookie 上下文则不动），新增 `forceRefresh()`；成功记录上下文、失败释放所有权。
- `lib/features/home/home_providers.dart`：新增 `feedCacheDirectoryProvider`；首屏请求立即发起、缓存水合并行且仅在列表为空时补种；移除 `timeout(3s)`；新增 `feedSessionContextKey()`（sha256，不落明文）。
- `lib/features/home/home_screen.dart`：重试按钮与下拉刷新走 `forceRefresh()`，保留「恢复已拥有请求时不重复发起」守卫。
- `lib/features/web_login/web_login_screen.dart`：移除登录确认后的 `ref.invalidate(personalizedFeedProvider)`。
- `lib/core/feed/artwork_feed_cache.dart`（新增）：账号分桶、`formatVersion = 1`、最多 60 条、临时文件 + rename 原子写、损坏/过期视为无缓存。
- `lib/shared/widgets/artwork_feed_grid.dart`：保留旧数据的刷新失败提示带上次成功加载时间。
- `pubspec.yaml`：`dependency_overrides: html: 0.15.6`（见下）。

恢复包 `recovery_ops.json` 的 27 条编辑全部精确匹配并重放（6 改 1 增），本次在其之上完成缺陷修复。

## 3. Tests

```
dart format --output=none --set-exit-if-changed lib test   # 0 changed
flutter analyze                                            # No issues found!
flutter test                                               # 410 tests, all passed
```

- 恢复前：4 个测试失败 + 11 个测试文件**无法加载**（`flutter_html 3.0.0` 与 `html 0.15.7` 的 `matches` 签名不兼容；镜像导致 `PUB_HOSTED_URL` 变化 → pub 重新解析，偏离基线 lock 的 `html 0.15.6`）。已用显式 pin 修好，属于环境解析问题，不是恢复代码的缺陷。
- 新增测试：`artwork_feed_controller_test.dart` 的 `first-page ownership (session context)`（4 条：同上下文重复刷新不重取、上下文轮换重取、`forceRefresh()` 总是重取、失败后重试重取）；`home_refresh_no_probe_test.dart` 的「无缓存目录仍只发一次实时请求、无残留 Timer」。
- 未修改任何断言数字来使测试通过；原有的重试/下拉刷新/分页契约保持原样并通过。

## 4. Documentation

- 新增 `docs/regressions/018-headless-webview-second-navigation.md`、`019-first-page-request-ownership.md`、`020-personalized-feed-cache.md`。
- `docs/regressions/README.md`：新增 R24–R26 与需真机补充的证据清单。
- `docs/authentication.md` 与 `docs/en/authentication.md`：冷启动契约补充导航收敛判据、首屏请求所有权、缓存定位（双语同步）。

## 5. Release

- 未在本机执行正式 Release：本机没有 Android SDK/JDK，构建 APK 需要下载数 GB（用户对代理流量敏感，已明确禁止未经确认的大流量动作）。
- 仓库使用 release-please 自动发版（`flutter test` 由 CI 在 GitHub runner 上构建产物，零本地流量）。合并本分支到 `main` 后由 CI 流程产出正式版本与 APK/AAB。
- `CHANGELOG.md` / `RELEASE_NOTES.md` 由 release-please 依据约定式提交生成，因此本分支不手改。

## 6. Deployment

- GitHub Pages 与下载页当前仍指向 `v0.5.12`（`6c0ecd4`）。版本、Release、下载链接的一致性依赖第 5 步的正式发版，未发版前不做手工改动，避免站点版本与 Release 不一致。

## 7. Pending（无 Android 真机，不得声明 Production Verified）

以下必须在真机正式安装包上验证，本次标记 **Pending**：

1. 已登录冷启动与强制停止后重启：`rfy/deviations` 首屏请求应恰好 1 次（`request=rfy-1`，无第二条 `reason=initial_or_refresh`）。
2. WebView 挑战后自动恢复：日志应出现 `waiting for redirect stop=n/3` 后确认有效会话，而非 `anonymous`。
3. 前后台切换、手动刷新、代理中断与恢复。
4. 缓存展示早于首屏响应（冷启动先出旧推荐，再被实时结果替换）、缓存损坏/过期/账号切换。
5. 验收命令（真机 + 本机同网段）：
   ```
   flutter build apk --release --dart-define=DAVIEWER_VERSION=<manifest 版本>
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   adb logcat -s flutter | grep -E 'personalized feed fetch|personalized feed accepted|waiting for redirect|web session state'
   ```
   预期：单次 `personalized feed fetch ... request=rfy-1`、随后 `personalized feed accepted ... generation=1`；不得出现两次首屏 `request=rfy-*`。

## 8. Blocked / 已知限制

- 旧工作区 `D:\Code\DAViewer`（ue-win）关机不可访问，本分支由恢复包重建，**未在真机验证**。
- 无 Android 真机与签名环境：APK/AAB 版本、签名与升级兼容性未在本机验证（交由 CI）。
- 本分支未合并 `main`，等待审阅与真机验收后由 CI 流程发版。
