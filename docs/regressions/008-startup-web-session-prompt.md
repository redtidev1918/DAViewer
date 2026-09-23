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
- **（2026-09 修订）** 裸 HTTP 首页探测与 `rfy/deviations` 成功都不是健康证据：
  匿名 Cookie 同样能拿到 rfy HTTP 200 + 通用内容。匿名探测必须由真实 headless
  WebView（与登录相同的 Cookie 栈）仲裁，见 `009`；
- 探测结果只允许在代际仍然最新时覆盖状态；迟到的匿名/不可用结果必须被丢弃。

## 修复

- Splash 显示恢复状态并异步执行 `ProxyController.testConnection`；代理变化时重新检测；
- 中文/英文文案区分 no proxy、direct blocked、proxy unreachable 与 proxy ready；
- ~~个性化 rfy 请求成功后，把 web session 标记为 healthy~~（v0.5.4 引入、v0.5.5
  撤销：rfy 200 无法证明登录态，见 `009`）；
- 测试确认拉取刷新不引入首页探测。

## Regression

- `test/home_refresh_no_probe_test.dart`：rfy 拉取刷新路径无首页探测；
- ~~rfy 成功后 `webSessionStatusProvider.isHealthy` 为 true~~（已被 `009` 的
  新契约取代：rfy 成功不改变状态）；
- `test/app_strings_test.dart`：锁定启动文案的中文/英文关键语义；
- Real-device cold-start without proxy and with proxy should be captured before calling
  the runtime path fully closed.