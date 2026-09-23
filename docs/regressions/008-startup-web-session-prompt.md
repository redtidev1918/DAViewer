# REG-008 Startup spinner hides proxy/network failure and probe false negative

## 症状

在无法直连 DeviantArt 的网络下冷启动，启动页只有转圈。用户无法判断是“当前网络不通”还是
“未开代理/代理配置错误”。打开代理后应用进入首页，，但 rfy 已成功，另一条首页探测
仍可能返回 anonymous，造成“已有 Cookie 却提示刷新网页会话”的误解；部分用户只能重启应用。

## 根因

1. Splash 没有任何连接状态输出；OAuth 恢复失败被有意保留为可恢复状态，但用户看不到原因。
2. `WebSessionVerifier` 对 `www.deviantart.com/` 的裸 HTTP 请求不是真实浏览器上下文。
   WAF / PerimeterX 可能对合法 Cookie 返回匿名页。`unverified` 本身不触发登录提示，
   但如果健康确认晚于探测结果到达，旧探测仍可能覆盖状态。

## 正确架构

- 启动页必须区分“未检测到代理/直连失败”与“代理地址不可达”，并说明这是应用侧路由探测；
- 真实业务请求的成功证据强于独立首页探测：`rfy/deviations` 用同一 Cookie + CSRF 成功返回
  即确认 web session healthy；
- 探测结果只允许在代际仍然最新时覆盖状态；业务请求确认健康后，迟到的匿名/不可用结果必须
  被丢弃。

## 修复

- Splash 显示恢复状态并异步执行 `ProxyController.testConnection`；代理变化时重新检测；
- 中文/英文文案区分 no proxy、direct blocked、proxy unreachable 与 proxy ready；
- 个性化 rfy 请求成功后，把 web session 标记为 healthy，并避免同账号重复刷新状态；
- 测试确认 rfy 成功即 healthy，且不引入首页探测。

## Regression

- `test/home_refresh_no_probe_test.dart`：rfy 成功后 `webSessionStatusProvider.isHealthy`
  为 true，且首页探测次数为 0；
- `test/app_strings_test.dart`：锁定启动文案的中文/英文关键语义；
- Real-device cold-start without proxy and with proxy should be captured before calling
  the runtime path fully closed.