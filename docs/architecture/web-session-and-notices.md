# 网页会话与提醒架构

## 问题

网页会话状态被多个页面各自判断：Home provider、登录页 WebView、Cookie 恢复、
服务端检查互相独立，导致重复请求、重复横批、WAF 挑战计数被打满。

同一原因造成第二个问题：Cookie 真正失效的时刻没有人负责判断。只有在启动、
进入登录页或某个页面恰好自己发现异常时才会校验，所以“该提醒时没提醒”反复出现。

## 原则

1. 会话状态只有一个来源：`WebSessionStatusProvider`。
2. 服务端确认有 TTL 缓存与指数退避，UI 重建不触发验证请求。
3. 提醒只由 `AppNoticeController` 驱动，页面不再各自写横批；渲染 host 挂在
   router 之上，任何路由都能立即看到恢复入口。
4. 登录页只接受手动刷新，App 不自动刷新挑战页。
5. Release 更新文本由每版本中文 notes 保证，并由 CI 校验。
6. 判断会话失效的入口只有一个：`WebSessionCoordinator`。页面与仓库层只上报
   信号或读取状态，不得自行下结论。
7. 只有 `WebSessionStatusController.applyVerification` 能写入结论，任何触发路径
   都不能绕过代际保护。

## 结构

```text
core/auth/web_session_status.dart      状态机 + TTL + 退避
core/auth/web_session_coordinator.dart 触发点：响应信号、周期、前后台切换
core/auth/media_session_signal.dart    媒体桥：非共享 Dio 栈的 401/403 上报
core/notice/app_notices.dart           统一通知模型
shared/widgets/app_notice_host.dart    提醒 overlay；传入 child 时覆盖整个路由
app/app.dart                           AppLifecycleListener 驱动 pause/resume，并包裹 router
features/web_login/...                 只消费状态、手动刷新、挑战锁定
features/home/...                      只消费状态，不直接打服务端验证
```

## 触发拓扑

`WebSessionCoordinator` 在共享 `runtimeProvider.dio` 上安装一个拦截器，并持有
一个周期定时器。所有触发都汇入同一条验证链，因此“什么时候检查”不再取决于
哪个页面碰巧发现异常。

| 触发 | 来源 | 语义 |
| --- | --- | --- |
| `web-http-401` / `web-http-403` | 任意 `deviantart.com` 网页请求 | 网页接口明确拒绝 |
| `web-login-redirect` | 请求最终落到 `/users/login` | 服务器把请求送回登录页 |
| `web-mature-loggedout` | 响应 JSON 中嵌套的 `blockReasons`/`block_reasons` 含 `mature_loggedout` | 成年内容因未登录被降级 |
| `content-restriction` | 作品访问解析判定受限 | 媒体层发现的限制 |
| `media-image-403` / `media-preview-403` / `media-fullscreen-403` | 图片错误回调（`CachedNetworkImage`、`Image.network`） | 图片栈的 401/403 |
| `media-video-403` | 视频播放器初始化失败 | 播放器错误文本含 401/403 |
| `media-transfer-403` | 后台下载失败 | 下载失败码含 401/403 |
| `periodic` | 每 1 分钟 | Cookie 已死但接口仍返回 200 的兜底 |
| `app-resume` | 前台恢复 | 回到前台立即重新确认，绕过健康缓存 |

被排除的流量：CDN／图片主机（403 属于内容限制，不是会话证据）、验证用的首页
探针（避免验证链观察自己的回声）、OAuth 端点（拒绝原因在 API token，不在 Cookie）。

触发本身很便宜，结论很贵，所以触发层只做合并与节流：`shouldVerify` 要求已声明
登录且当前不是 `needsLogin`；强制触发共享 30 秒窗口并复用进行中的检查；周期触发
走 `check()`，沿用 5 分钟健康缓存与退避，前台恢复与响应信号一样强制复核。任何触发
异常都被记录后吞掉，不会打断业务请求。

不经过共享 Dio 的媒体栈由 `MediaSessionSignal` 桥接：图片错误回调、
视频播放器失败与后台下载失败里“看起来像 401/403”的错误（缓存管理器的
`HttpExceptionWithStatus`，或错误文本中含 401/403 的平台异常）被上报到同一条
验证链。被拉黑的成熟/付费主机地址只是信号——验证链会在服务端复核后才判定
Cookie 失效，真正付费的作品永远不会触发登录提醒。桥同样遵守闸门：未声明登录、
`needsLogin`、`locked` 或退避期内一律静默；没有 `ProviderScope` 祖先的组件
（例如脱离 App 的错误组件）静默丢弃，不抛异常。

仍然无法触发的情况只剩内嵌 WebView（登录页与挑战刷新）自身的流量；媒体请求
已能通过桥即时触发，不再依赖后续网页请求、周期检查或前台恢复兜底。

## 状态

`unknown → healthy | anonymous | stale | locked | unavailable`

- `healthy`：DeviantArt 首页服务端确认 Cookie 属于当前账号，推荐页可用；
- `anonymous`：服务端明确返回匿名/过期，需要 App 内网页会话并更新 Cookie；
- `stale`：存在本地 Cookie，但服务端不再识别；
- `locked`：WAF 挑战上限，停止自动请求；
- `unavailable`：验证请求被 WAF/网络拦截且处于退避期，不误判为匿名。
- `unverified`：本地已有确认过的 WebView 会话，但一次纯 HTTP 探针无法确认，
  不是登出信号。

服务端验证由 `WebSessionVerifier` 读取首页 `@publicSession.user.username`，
返回 `signedIn / anonymous / unavailable` 三态：只有首页确认了登录用户名才进入
`healthy`；WAF 或非 200 响应进入 `unavailable` 并走退避，不会伪装成登录提醒。
纯 HTTP 探针返回匿名而本地声明已登录时，改用真实浏览器探针（`web_session_refresher`）
仲裁，避免把 WAF 的假阴性变成登出。本地存在 Cookie 只代表有机会验证，不代表
会话有效。

只有 `healthy` 允许推荐请求。忘记验证结果由 `WebSessionStatusProvider`
统一管理；任何页面都不得直接调用服务端验证。

## 提醒与恢复

`AppNoticeController` 持有业务提醒并去重；会话提醒直接派生自
`WebSessionStatusProvider`。`AppNoticeHost` 用底部 overlay 展示，避免覆盖
AppBar 与内容；关闭状态由 host 自己持有，不再复用业务提醒控制器。

提醒必须出现在用户当前所在的页面。host 需要 ambient `Overlay` 与 router
祖先，所以不能挂在 Navigator 之上：`AppShell` 与作品详情页把 `AppNoticeHost`
放在各自页面的 `Stack` 里；其余被 push 的路由（作者页、作品集、设置、代理/诊断、
Watching、通知、历史、标签）在 `router.dart` 用 `NoticeOverlay` 包裹，由它补一个
底部 `Positioned` 的 host。三种入口渲染的是同一个 provider 派生的同一条提醒。

恢复路径是闭环的：

```text
触发 → 验证链得出结论 → needsLogin → AppNoticeHost 显示登录入口
  → /web-login 完成登录 → markHealthy → 作废受影响数据 → 重新请求
```

登录成功后 `web_login_screen.dart` 调用 `markHealthy`、作废个性化信息流，并在
首次确认时调用 `artworkSessionRecoveryProvider`，让已经失败的详情与媒体请求重新
发起。`healthy` 期间关闭过的提醒视为已过期：回到 `needsLogin` 会再次出现。

## Release notes

每个版本在 `.github/release-notes/<version>.md` 提供中文说明，CI 检查发布正文
包含中文字符与“本次更新”小节。
