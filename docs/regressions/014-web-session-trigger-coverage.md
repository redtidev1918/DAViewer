# REG-014 会话失效的提醒时机不受控

## 用户报告

Cookie 到期后应用经常不提醒，只有重启、进入登录页或恰好打开某个出错页面才发现；同一问题反复出现。

## 已确认的代码路径

会话判断分散在四处，彼此都不知道对方看到了什么：

- Cookie 存储与恢复只在启动和登录流程里读写，不产生“该提醒了”的结论；
- CSRF 刷新（`web_session_refresher`）只写回 CSRF，不代表服务端仍认识该 Cookie；
- 服务端验证只在启动页、设置页的手动检查和创作详情页的可疑媒体回退时触发；
- 提示条挂在 `AppNoticeHost` 上，只能被动等待状态变化。

因此“在使用中失效”这一最常见的时刻没有任何触发点。两个具体后果：

1. 首页请求失败后只刷新 CSRF，不重新验证 Cookie；
2. Cookie 已失效时 `rfy/deviations` 仍可能返回 HTTP 200 的通用推荐，只监听请求错误无法发现失效（见 [REG-009](009-rfy-200-generic-content.md)）。

## 修复

- 新增 `lib/core/auth/web_session_coordinator.dart`：在共享 `runtimeProvider.dio` 上安装唯一拦截器，把网页响应的失败信号（401/403、落到 `/users/login` 的重定向、嵌套的 `mature_loggedout`）统一上报给状态机；同时持有周期定时器，并在应用回到前台时立即复核。
- 触发层只触发，不判定：`shouldVerify` 要求已声明登录且当前不是 `needsLogin`；强制触发共享 30 秒窗口并复用进行中的检查；周期触发走 `check()`，沿用健康缓存与退避，前台恢复强制复核。结论仍然只能由 `applyVerification` 写入（见 [REG-011](011-session-boundary-refactor.md)）。
- `recheckAfterContentRestriction()` 改为 `recheckAfterWebSignal(source)` 的薄封装，让内容限制与 HTTP 信号走同一条路径，并在日志中记录触发来源。
- `lib/app/app.dart` 用 `AppLifecycleListener` 驱动协调器的 `pause`/`resume`；后台不轮询，回到前台强制复核（缓存的健康结论不能掩盖离开期间失效的 Cookie）。
- 排除 CDN／图片主机、验证用的首页探针与 OAuth 端点，避免内容限制和验证链自回声变成会话证据。
- 提醒覆盖被 push 的路由：新增 `NoticeOverlay`（`app_notice_host.dart`），在 `router.dart` 包裹作者页、作品集、设置及其子页、Watching、通知、历史、标签；host 必须在 Navigator 内（需要 ambient `Overlay` 和 router 祖先），不能挂在 router 之上。

恢复路径保持闭环：确认匿名 → `AppNoticeHost` 显示登录入口 → `/web-login` 完成登录 → `markHealthy` → `artworkSessionRecoveryProvider` 作废并重取受影响数据。

关闭提醒的记录由 `webSessionNoticeDismissalProvider` 共享。同一次故障在切换页面后
保持关闭；确认恢复后清空记录，即使当时没有任何 host 挂载，下一次失效仍会提醒。
回归测试包含页面替换、登录页期间恢复，以及恢复和再次失效发生在两次绘制之间的情况。

## 验证与范围

`test/web_session_coordinator_test.dart`（15 个用例）覆盖：三类信号（含嵌套与下划线两种 `blockReasons` 写法、直接登录页请求与重定向）、排除规则（CDN、首页探针、OAuth、深度上限）、成功与失败响应的触发、`shouldVerify` 关断、周期触发、回前台强制触发、`pause`/`resume`、`dispose` 摘除拦截器且不再触发、触发异常不外泄，以及 provider 在共享 Dio 上的挂载与摘除、未登录时完全不启动验证链。`test/app_notice_host_test.dart` 新增 `NoticeOverlay` 用例，验证被 push 的页面上也能出现登录提醒。全量 353 个测试通过，`flutter analyze` 与格式检查通过。

未覆盖：真实失效 Cookie 下的实机时序、WAF 挑战期间的触发抑制效果，以及
iOS/Android 后台挂起时定时器被系统冻结的实际行为。周期每分钟触发一次，但健康
结论缓存 5 分钟；无网络故障、应用持续在前台时，一般会在上次确认后约 5–6 分钟
复核。后台挂起、验证耗时和失败退避会延长时间，不能保证一分钟内提醒。响应信号与
前台恢复可绕过健康缓存，但仍遵守 30 秒节流和失败退避。自动化测试使用构造响应，
实际行为需要实机日志确认。
