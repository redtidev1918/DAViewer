# REG-011 Web Session 职责边界重构（行为等价）

v0.5.5 之后连续两次生产事故（REG-009、REG-010）都指向同一个结构问题：
OAuth 身份、Cookie 存储、会话验证、业务使用方互相越权写状态。本次是
小型、受控、行为等价的重构，不引入新框架。

## 职责边界（重构后）

| 组件 | 唯一职责 |
|---|---|
| `AuthController` | OAuth 身份（官方 API / Daily / 账号资料） |
| `WebSessionController` | Cookie/CSRF 存储与恢复 + 登录 WebView 显式事件 |
| `WebSessionRefresher` | headless 浏览器观察者：只轮转 CSRF、返回探测结果 |
| `resolveWebSessionVerdict` | 纯状态转移策略（证据 → 判定决定） |
| `WebSessionStatusController.applyVerification` | 唯一的 verdict 写入口（代际保护 + 日志） |
| `PersonalizedFeed` / `AppNoticeHost` | 只读消费者 / 渲染器 |

## 硬规则

- 只有 Verification 层能产生 verdict；feed 成功/失败、Cookie 持久化、
  网络故障、UI 都不能；
- 后台探测只能 `updateCsrf`，永不写身份或 verdict；
- bare anonymous + 已声明登录 → 必须升级到真实浏览器仲裁；
- 真实浏览器 anonymous 才是权威登出；unavailable 一律 unverified；
- 陈旧代际的证据永远丢弃并记录 `reason=stale`；
- `AppNoticeHost` 不再发起 `check()`，首次验证由启动流程触发；
- `webSessionReadyProvider` 语义收敛为"启动 readiness"，不等于 healthy。

## Regression

- `test/web_session_verdict_policy_test.dart`：bare/real-browser/webLogin/
  localState × confirmed/anonymous/unavailable 全矩阵 + 登出判定权威性；
- 既有 298 个测试保持通过（含 `web_session_status_test` 仲裁三态、
  `home_pagination_no_auth_damage_test` 分页不污染认证）。