# Android 回调所有权与启动验证 — 43fe8bf 联合候选(模拟器)

日期: 2026-10-12 · 执行: 接管会话(自动化,非人工复核)

## 范围与环境

- 目的: 检验「回调所有权完备」——SDK 独占消费 `dakit://` OAuth 回调,Flutter 内建深链路由不再以 `route_removed` 掩盖错误(3d7d2d7 修复)。
- 产物: joint candidate run **38243805269**(PR #97 head 43fe8bf,DAKit 2590cbe)Linux artifact。
- 设备: API36 x86_64 模拟器(emulator-5554,软件渲染)。**模拟器证据,非真机**;无真实账号,OAuth happy-path 未在设备上执行(Original Incident 验收仍需真机+保留账号)。
- 时钟: 模拟器时钟为 GMT(`adb shell date` 实测比本地 +0800 慢整 8 小时),本文所引设备日志时间戳均为模拟器 GMT 时钟,对应本地时间 +8h(如 12:48 GMT = 20:48 +0800)。

## 1. 产物与静态核验

- 文件: `D:\Android\setup\joint-43fe8bf-candidate\DAViewer-v0.5.13.apk`(67,445,346 bytes)
- SHA256: `7720B79CAFAFDC1C001D2FFA57DC5F5C15D65F26793090218A83EAA68420F63B`
- provenance: `daviewer_sha=43fe8bf635a842801d0b9edd06b06b2b8deb930f, dakit_sha=2590cbec59e0193d231addc73b3373cbe2b9b88e, candidate_only=true, packages=dakit_core/api/web/flutter`
- `aapt dump badging`(build-tools 36.0.0): `app.daviewer` versionName 0.5.13 versionCode 225,minSdk 24,targetSdk 36
- `aapt dump xmltree AndroidManifest.xml`: MainActivity activity 内 meta-data **`flutter_deeplinking_enabled = 0x0`(false)已嵌入** ✓(3d7d2d7 修复落地于构建产物)
- `apksigner verify --print-certs`(JDK21): Signer `CN=DAViewer, O=redtidev1918, C=CN`; **SHA-256 `686474b39fd91d20c1db3ce5bf6216ed8ab05ec7638f904251e0d108a34e7141` = 正式发布证书**,与事故机升级路径签名兼容。
  - 更正: 早前推测「PR 触发 candidate 无签名密钥只能产 debug 未签名 APK」不成立——candidate job 条件为 `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`,同仓 PR(本例)有签名 secrets;未签名路径仅限 fork PR。

## 2. 安装与启动冒烟

- `adb install -r`: Success(exit 0)。
- 冷启动 `am start -W -n app.daviewer/.MainActivity`: Status ok,LaunchState COLD,**TotalTime 2364ms**;进程存活(pid 8410);焦点 `app.daviewer/app.daviewer.MainActivity`。
- 启动日志关键行:
  - `[startup] route=/splash target=/web-login ready=true oauth=signedOut` → `[startup] route=/web-login target=stay ready=true oauth=signedOut`(signedOut 显式状态驱动路由,非 unknown 兜底)
  - `[auth] recovery created/completed recoveryId=recovery-1/2`(会话恢复协调器正常)
  - `[oauthCallback] oauth.transaction.cancelled`(重开登录先取消遗留 PKCE 事务)→ 新事务 `oauth.transaction.created` + `oauth.callback.waiting`
  - WebView 真实联网加载 DeviantArt:`challenge check passed`、join 页 `csrfPresent=false→true`、`[proxy] connectivity check: 200 in 3929ms`
- 无 FATAL / AndroidRuntime 崩溃。

## 3. 设置与诊断页

- 登录页顶栏「设置」可入;设置页完整渲染: 语言/外观/网络代理/日志与诊断/清除缓存/检查更新(DAViewer · 0.5.13)/DeviantArt 账号设置/关于。
- 「日志与诊断」进入成功: `route=/settings/diagnostics`;页面内启动日志显示 **`buildRevision=43fe8bf635a842801d0b9edd06b06b2b8deb930f`**(精确源 SHA 已嵌入 Android 构建);提示「本次运行记录到 3 个错误」= 第 4 节故意注入的 state_mismatch 错误,诊断页如实计数;导出(Export recent launch logs)/报告问题/刷新按钮可用。
- 证据截图与 UI dump 已归档至 `docs/agent-tasks/session-recovery/audits/android-emulator-43fe8bf/`:screen-weblogin.png / screen-settings.png / screen-diagnostics.png + ui-weblogin.xml / ui-settings.xml / ui-diagnostics.xml + sdk-integration-provenance.json。

## 4. 深链回调所有权(核心检验)

### 4.1 热态(应用前台 /web-login,PKCE 事务进行中,事务创建于 12:48:23)

```
adb shell am start -W -a android.intent.action.VIEW -d "dakit://oauth/callback?code=wrong-code&state=invalid-state-123" app.daviewer
→ 已运行实例收到 intent(Warning: delivered to currently running top-most instance)
→ [ERROR] [oauthCallback] oauth.callback.state_mismatch [123038ms] failure_code=oauth.callback.state_mismatch
→ [ERROR] [auth] OAuth login failed: oauth.callback.state_mismatch | error=DAKitException(oauth.callback.state_mismatch): The OAuth callback state is missing or invalid.
→ [INFO] [startup] route=/web-login target=stay ready=true oauth=signedOut
```

- SDK app_links 源消费回调并对活事务做 state 校验 → **state_mismatch 以明确错误呈现给用户**;
- **无 `route_removed`、无 `/callback→/` 导航重定向、无 login dispose,路由保持 `/web-login`**——修复前 Flutter 内建深链路由同时重定向并 dispose login(reason=`route_removed`)掩盖 SDK 错误的路径不复存在。

### 4.2 冷态(force-stop 后以 VIEW intent 启动)

```
adb shell am force-stop app.daviewer
adb shell am start -W -a android.intent.action.VIEW -d "dakit://oauth/callback?code=cold-code&state=persisted-state-abc" app.daviewer
→ LaunchState COLD, TotalTime 1247ms, 新 pid 8665
→ [auth] login: starting OAuth authorize → oauth.transaction.created(新 PKCE)
→ [ERROR] [oauthCallback] oauth.callback.state_mismatch [3ms]  ← 旧回调对新事务,正确拒绝
→ [ERROR] [auth] OAuth login failed: …
→ [startup] route=/web-login target=stay … 应用继续正常登录流程,WebView 继续加载 join 页
```

### 4.3 启动窗口韧性(诊断页启动日志所见)

```
stage=oauth_restore event=start → [DEBUG] oauth.callback.waiting → [ERROR] oauth.callback.state_mismatch [1ms]
→ [WARNING] [auth] initialize: persisted session temporarily unavailable; preserving signed-in state
→ stage=oauth_restore event=complete → stage=cookie_restore complete → ready=true reason=restore_finished
```

启动期注入的错误回调被立即消费并拒绝,未卡死、未崩溃;启动链按 deadline 正常收口(`splash created deadlineMs=12000`,restore_finished)。

## 5. 结论(检验范围内)

- 「回调所有权完备」在以下范围内得到支持: 43fe8bf 候选(正式签名 release APK)、API36 模拟器、错误 state 回调三种时序(热态活事务 / 冷态新事务 / 启动窗口)。
- SDK 独占消费 `dakit://` 回调;state 校验失败以 `oauth.callback.state_mismatch` 如实呈现;Flutter 内建深链路由不再干预(manifest flag 已验嵌入构建产物)。
- 未验证(如实记录): 真机行为;真实账号 OAuth happy-path(需真实 DeviantArt 授权,属 Original Incident 真机验收);正确 state 回调完成授权(无真实 code/state 无法在设备构造;路径已由 DAKit authorization_coordinator_test.dart / merged_callback_source_test.dart 等单元覆盖)。

## 6. 证据文件

- 本文档;`docs/agent-tasks/session-recovery/audits/android-emulator-43fe8bf/`(provenance json 副本、截图×3、UI dump×3);候选 APK 本体(67,445,346 bytes)与 provenance 原件保留于 `D:\Android\setup\joint-43fe8bf-candidate\`(体积原因不入库);logcat 关键行已摘录于上。
