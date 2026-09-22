# 网页会话与提醒架构

## 问题

网页会话状态被多个页面各自判断：Home provider、登录页 WebView、Cookie 恢复、
服务端检查互相独立，导致重复请求、重复横批、WAF 挑战计数被打满。

## 原则

1. 会话状态只有一个来源：`WebSessionStatusProvider`。
2. 服务端确认有 TTL 缓存与指数退避，UI 重建不触发验证请求。
3. 提醒只由 `AppNoticeController` 驱动，页面不再各自写横批。
4. 登录页只接受手动刷新，App 不自动刷新挑战页。
5. Release 更新文本由每版本中文 notes 保证，并由 CI 校验。

## 结构

```text
core/auth/web_session_status.dart  状态机 + TTL + 退避
core/notice/app_notices.dart      统一通知模型
shared/widgets/app_notice_host.dart 全局 MaterialBanner 渲染
app/app_shell.dart                挂载 AppNoticeHost
features/web_login/...            只消费状态、手动刷新、挑战锁定
features/home/...                 只消费状态，不直接打服务端验证
```

## 状态

`unknown → healthy | anonymous | stale | locked | unavailable`

- `healthy`：DeviantArt 首页服务端确认 Cookie 属于当前账号，推荐页可用；
- `anonymous`：服务端明确返回匿名/过期，需要 App 内网页会话并更新 Cookie；
- `stale`：存在本地 Cookie，但服务端不再识别；
- `locked`：WAF 挑战上限，停止自动请求；
- `unavailable`：验证请求被 WAF/网络拦截且处于退避期，不误判为匿名。

服务端验证由 `WebSessionVerifier` 读取首页 `@publicSession.user.username`，
返回 `signedIn / anonymous / unavailable` 三态：只有首页确认了登录用户名才进入
`healthy`；WAF 或非 200 响应进入 `unavailable` 并走退避，不会伪装成登录提醒。
本地存在 Cookie 只代表有机会验证，不代表会话有效。

只有 `healthy` 允许推荐请求。忘记验证结果由 `WebSessionStatusProvider`
统一管理；任何页面都不得直接调用服务端验证。

## 提醒

`AppNoticeController` 持有业务提醒并去重；会话提醒直接派生自
`WebSessionStatusProvider`。`AppNoticeHost` 用底部 overlay 展示，避免覆盖
AppBar 与内容；关闭状态由 host 自己持有，不再复用业务提醒控制器。

## Release notes

每个版本在 `.github/release-notes/<version>.md` 提供中文说明，CI 检查发布正文
包含中文字符与“本次更新”小节。
