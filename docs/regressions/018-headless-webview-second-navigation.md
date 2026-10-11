# REG-018 Headless WebView 二次导航

## 症状

已登录且 OAuth `user/whoami=200`、Cookie 恢复成功的前提下，Dio 端
`WebSessionVerifier` 仍返回 `anonymous`，状态落到 `unverified`。用户进入可见
WebView 后经过一次挑战页跳转才被确认成 `healthy`。冷启动因此先经历一次
”会话不可用“，推荐页空转。

## 根因

`web_session_refresher.dart` 的 Headless WebView 在**挑战页的第一次
`onLoadStop`** 就采样页面并上报结论，随即销毁 WebView。挑战页本身不含账号
信息与 CSRF，于是观察结果被判为 `anonymous`，而真正承载会话的首页（挑战
通过后由 JavaScript 跳转加载）从未被观察。

## 错误架构

- 把”某一次 `onLoadStop` 的页面内容“当作会话证据；
- 没有区分”加载结束但结论不成立“与”已确认匿名“；
- 采样早于导航收敛，等价于用中间态页面判定身份。

## 正确架构

- 探测区分**不确定**与**确证匿名**：挑战页/空页面只累计
  `_inconclusiveStops`，不写结论；
- 允许后续导航继续观察，直到出现可判定页面或达到
  `_maxInconclusiveStops = 3` 上限；
- 只有明确读到账号信息（`healthy`）或确证无账号的终态才写结论；
- 观测结果统一经由 `WebSessionStatusController.applyVerification`
  的 generation 守卫写入，后台探测永远不降级已有判定。

## 修复

- `lib/core/auth/web_session_refresher.dart`：新增
  `WebSessionProbeObservation`，`onLoadStop` 改为”不成立则继续等待跳转“，
  上限 3 次后返回不可用（`unverified`），不返回 `anonymous`。
- 日志新增 `waiting for redirect stop=n/3`，便于从生产日志区分此路径。

## Regression

- `web_session_refresher_probe_test.dart`：挑战页首次 `onLoadStop` 不给结论，
  第二次导航后才确认；超过上限只报不可用，绝不冒充匿名。
- `home_refresh_no_probe_test.dart`：真实浏览器判定的 `anonymous` 才展示恢复
  入口；rfy 返回 200 本身不构成会话证据（见 `009`、`010`、`016`）。
