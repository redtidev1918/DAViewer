# REG-009 rfy 200 的通用内容冒充个性化推荐

## 症状

冷启动后 OAuth 恢复成功、本地 Web Cookie 快照也恢复，首页推荐 tab 显示的内容
变成“每日精选”风格的通用内容，且没有任何登录/恢复提示。日志里
`personalized feed success ... items=24` 连续成功，verifier 却报
`classification=anonymous`，用户无法判断是 Cookie 失效还是应用 bug。

## 根因

1. `rfy/deviations` 对匿名 Cookie 同样返回 HTTP 200 与通用内容（分页 cursor 的
   `vespa_content_group:2` 即通用内容组），rfy 200 从来不能证明网页会话有效；
2. v0.5.4 的 “rfy 成功 → markHealthy” 用伪造的健康状态压制了登录提醒；
3. 每日精选与推荐分属两个数据源，但 UI 没有任何区分提示，通用内容被当推荐渲染。

## 正确架构

- rfy 成功不得作为 web session healthy 的证据；
- 裸 HTTP verifier 报 anonymous 且本地声明已登录时，必须由真实 headless WebView
  （与登录相同的 Cookie 栈）仲裁：
  - 确认同账号 → healthy（裸探测是 WAF 误报）；
  - 真实浏览器也匿名 → anonymous，显示登录/恢复提示；
  - 真实浏览器无法作答 → unverified，绝不触发登录提示；
- 权威 anonymous verdict 下，推荐 tab 不得发起 rfy 请求、不得渲染返回内容，
  必须显示恢复界面；任何认证状态变化都不得自动切换 tab。

## 修复

- `WebSessionRefresher.refresh()` 返回 `WebSessionProbeResult`
  （csrf + 真实页面渲染的 username）；
- `WebSessionStatusController` 匿名分支改为真实浏览器仲裁；
- 撤销 “rfy 成功 → markHealthy”（v0.5.4 引入）；
- 推荐 tab 在 anonymous verdict 下显示恢复界面并拒绝 rfy 请求。

## Regression

- `test/web_session_status_test.dart`：裸匿名探测 + 真实浏览器确认 → healthy；
  真实浏览器匿名 → anonymous/needsLogin 且身份保留；真实浏览器失败 → unverified；
- `test/home_refresh_no_probe_test.dart`：rfy 成功不再置 healthy；anonymous
  verdict 下推荐 tab 显示恢复 UI、不发起 rfy 请求。