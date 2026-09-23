# 认证与会话恢复

> English: [Authentication and session recovery](/en/authentication.md)

DAViewer 只有一个用户身份：官方 DeviantArt OAuth 会话。应用既不接收也不存储 DeviantArt、Google、Apple、Facebook 或 Mac 的密码。凭据与各服务商的安全校验都留在 DeviantArt 官方页面，应用只在自己的内嵌 WebView 中展示该页面。

## 单入口登录契约

应用只暴露一个 **登录或创建账号** 操作，它打开内嵌登录界面：

1. DAKit 创建一个 OAuth/PKCE 事务。
2. DAViewer 以内嵌 WebView 加载官方登录页，并使用桌面 User-Agent —— 因为 DeviantArt 的移动登录页不提供桌面页上的一键 Google/Apple 按钮。
3. 账号登录、注册、找回密码以及当前提供的全部服务商（DeviantArt、Google、Apple、Facebook）都由 DeviantArt 页面负责。应用内没有单独的「社交登录」路径。
4. `dakit://oauth/callback` 在 WebView 内被拦截并完成同一事务。WebView 保留其 Cookie 与 CSRF token，因此这一次登录同时建立了后续个性化 `rfy` 信息流与合集适配器所需的网页会话，不再要求第二次登录。

每次打开内嵌登录页都会取消上一次遗留的陈旧 OAuth 事务并新建 PKCE 事务，
避免用户在“上一次登录已挂在 isLoggingIn”的状态下只刷新了网页 Cookie，
随后官方 API 页面仍然显示未登录。

应用不模拟服务商按钮点击、不内嵌密码表单、不从系统浏览器拷贝 Cookie，也不探测人机验证的 DOM。它只设置桌面 User-Agent，以便返回完整的桌面登录页。Google、Apple、Facebook 仍可能在自己的页面内展示账号选择或 CAPTCHA 校验；那属于服务商页面，应用不去绕过。

## 会话角色

- **OAuth 会话**（安全存储）驱动官方 API：每日作品、搜索、作品查询、收藏、关注与下载。
- **网页会话**（WebView 的 Cookie 加 CSRF token 与登录态，本地持久化并在启动时恢复）驱动仅网页可用的适配器：个性化 `rfy/deviations` 信息流与合集内容。已登录 Cookie 会快照进应用自身存储，并在冷启动时平台 WebView 存储丢失（例如跨界应用更新）后重新注入，从而不必重新登录也能保住个性化信息流。

一次内嵌登录同时建立两种会话。WebView 只在 OAuth 回调回到 DeviantArt 首页之后才上报网页会话（CSRF token 与 `userinfo` Cookie），因此应用不会把匿名登录页的未登录状态记录为网页会话。

持久化的 Cookie 快照保留每个 Cookie 的完整元数据（域名、路径、过期时间、
Secure/HttpOnly），而不是折叠成 `name→value` 表：同名的 `.deviantart.com` 与
`.www.deviantart.com` Cookie 不会互相覆盖，恢复时按原元数据写回 WebView，从而
避免应用更新后平台 Cookie 存储丢失导致被迫重新登录。旧的 `name→value` 快照在
读取时自动迁移。服务端验证（`check`）合并并发调用、共享同一次在途校验，并用
代际计数丢弃迟到的匿名/失败结果，防止旧校验覆盖更新一次的登录成功状态。

**只有 OAuth 已登录（或刚完成）时，服务端确认的网页会话才会让登录界面关闭。**
首次登录时网页 Cookie 先确认也绝不提前关闭，登录页会等 OAuth 完成；仅重建
网页会话（OAuth 已登录）时仍会自动关闭，不会再次索要授权。

等待期间用户可以取消并重新打开。取消或开启新尝试都会清除待处理事务，避免过期回调吞掉后续登录。设置、代理、诊断、更新、关于、语言与外观在登录前均可达。

只要应用进程存活，内存中的 PKCE 事务就是权威。它的安全存储副本只用于进程重启后恢复回调：写入、读取或清除该恢复副本失败，绝不能推翻仍在进行的授权结果。token 存储不同，它才是硬提交点——只有新 token 已安全存储，登录才被判定成功。

`dakit` scheme 由内嵌 WebView 持有，它拦截 OAuth 回调且从不离开应用。只有在没有注册 WebView 监听器作为回退时，以及「内容设置」跳转 DeviantArt 浏览偏好时，才使用系统浏览器。

## 冷启动契约

1. 没有冷启动 OAuth 回调时，跳过待处理事务存储，只读取当前 OAuth token。
2. 只有凭据缺失或被吊销才判定为未登录。临时性的网络、上游、超时、解析与 Keychain 不可用故障都保留既有会话。
3. 只有在安全存储成功读写 token 之后，才记录非敏感的会话证据。这能避免首次运行的网络错误把匿名用户送进首页，同时保住老用户的离线恢复能力。
4. 显式登出会清除当前 OAuth 存储、会话证据与 WebView Cookie。

`oauthSessionKnown=false` 是显式登出的权威证据：即使清理 token 时安全存储失败，
下次冷启动也不会因为遗留 token 重新进入 `signedIn`。
网页 Cookie 的可用性也由 DeviantArt 首页服务端验证
（`@publicSession.user.username`），本地存在 Cookie 不等于会话有效。裸 HTTP
首页探测可能被 WAF 干扰，但 `rfy/deviations` 成功**同样不是**健康证据：匿名
Cookie 也能拿到 HTTP 200 的通用内容。匿名探测结果由真实 headless WebView
（与登录相同的 Cookie 栈）仲裁：确认同一账号 → healthy；真实浏览器也匿名 →
anonymous 并提示重新登录；真实浏览器无法作答（挑战/网络）→ 保持 unverified，
绝不静默降级。

职责边界（见 `regressions/011`）：只有验证层能产生 verdict；Cookie 存储、
后台探测（只轮转 CSRF）、feed 成功/失败、UI 都没有写权限。所有 verdict
变更经由 `WebSessionStatusController.applyVerification` 单一入口，带代际
保护与 source 日志；`webSessionReadyProvider` 只表示启动 readiness，不等于
会话健康。

## 认证事务生命周期

所有登录入口（首页、设置、每日精选、关注动态、收藏、通知）最终都进入同一个
`AuthController` 登录事务：

1. 打开登录页先终结上一次遗留的 OAuth 事务（`cancelLogin`），再新建 PKCE 事务，
   防止旧的 `isLoggingIn`、Pending transaction 或回调阻塞新登录。
2. OAuth 回调/token 写入成功后，账号资料加载完成才把全局状态收敛为 `signedIn`。
3. 网页 Cookie 由 `WebSessionVerifier` 读取 DeviantArt 首页进行服务端验证；
   只有 OAuth 与 Web Session 都满足契约，登录页才自动关闭。
4. 每次登出、取消或新建登录都会递增认证代际；旧的在途账号加载/回调不能把状态
   改回 `signedIn`。
5. 依赖 OAuth 的 Provider（每日精选、关注动态、收藏、通知）统一 watch
   `AuthController` 的账号身份；身份变为 `signedIn` 后自动 invalidate 并重新拉取，
   不依赖任何页面手动刷新或空状态残留。

状态语义：

- `signedOut`：OAuth 不存在/被明确吊销，或者用户显式登出；
- `signedIn`：OAuth token 与账号资料已收敛，服务端 API 可用；
- `anonymous`：网页 Cookie 被 DeviantArt 明确判定为匿名/过期，只影响网页推荐，
  不把有效 OAuth 误杀；
- `unavailable`：WAF 拦截、HTTP 非预期响应或网络错误，走退避，
  不等同于未登录，不触发重复登录提示；
- `signingIn / signingOut`：登录/登出进行中。

macOS 预览版使用同一个私有稳定的 CI 签名身份。该身份是自签名的，不被 Apple 信任也未公证，但它能避免每次更新后变化的 ad-hoc cdhash 索要 Mac 密码。token 与恢复存储使用 `DAViewer Account` Keychain 服务；更早的 ad-hoc 项永不查询，因此无法访问的历史记录不会阻塞授权。

项目**不购买 Apple Developer Program**，也不要求付费开发者签名。本地
`ad-hoc / 无 TeamIdentifier` 是接受的环境限制；稳定签名与公证明确不在本项目的
发布范围内，不作为 Keychain 验收或 Release Gate 的阻塞项。

首页 **推荐 / For you** 标签是网站的个性化 `rfy/deviations` 信息流，使用 WebView 的 Cookie 与 CSRF token 拉取。它需要已登录的网页会话；网页会话缺失、正在恢复或被权威判定匿名时，该标签展示登录/恢复提示，**绝不静默渲染匿名 Cookie 拿到的通用内容**，也绝不自动切到 **每日精选 / Daily** 标签（该标签使用官方 OAuth API，不依赖网页会话，只在用户主动切换时显示）。产品上不得把这两个数据源表述为等价。

## 公开网页适配器

少数详情页功能需要未公开的公开网页数据，例如数字 id 解析与合集内容。内嵌 WebView 的网页会话（Cookie 与 CSRF token）按需提供这些能力。它属于基础设施状态，不是第二个用户身份：绝不阻塞首页、绝不要求用户再次登录，不可用时必须降级为重试或官方 API 回退。

历史浏览器 Cookie 仅为兼容公开适配器而接受。若它们暴露的用户名与 OAuth 账号不同，会被清除，以防混账号数据。

## Cookie 查看、导出与导入

设置 → **账号 Cookie** 以缩进 JSON 展示当前的 deviantart.com 网页会话 Cookie，并可复制到剪贴板，便于用户查看或备份网页会话。优先使用 WebView 的实时 Cookie；WebView 存储不可读时回退到已持久化的快照。该对话框明确警告这些 Cookie 等同于登录凭据。导出是用户主动的手动复制：应用不会把任何内容发送到别处，诊断/报告输出也从不包含 Cookie。

同一对话框也支持粘贴导入：导出的 JSON、浏览器扩展 Cookie 数组（非 DeviantArt 域名会被忽略），或 `name=value; …` 形式的 Cookie 头。导入是应用中最敏感的写入操作，遵循严格的一账号规则（`evaluateCookieImportIdentity`）：

1. 导入的 Cookie 必须带有已登录的 `userinfo` 用户名；匿名粘贴会被拒绝。
2. 若已登录 OAuth 账号，导入的用户名必须与之一致。
3. 若 WebView 已有已登录网页会话，导入的用户名必须与之一致。
4. 冲突会在**写入任何 Cookie 之前**被拒绝——应用绝不把一个账号的会话叠加到另一个账号上。要切换账号需先登出。
5. 注入完成后会从 Cookie 存储回读用户名。若 DeviantArt 不认可所声称的会话（Cookie 过期/无效），则恢复原有 Cookie，不持久化任何内容。

导入校验通过后，快照会被持久化、网页会话状态被更新，并触发一次 CSRF 刷新，使网页适配器使用新会话。仅网页的导入会话（无 OAuth 账号）可驱动网页适配器与个性化信息流，但官方 API 功能仍需 OAuth 登录。因此导入之后，应用会再提供一次常规内嵌登录：DeviantArt 页面会识别导入的 Cookie，通常无需输入密码即可完成，用户也可以关闭该提示（网页功能继续可用；官方 API 功能在使用时再次要求登录）。Cookie 永不替代 OAuth token —— 官方 API 会话只能通过 OAuth/PKCE 流程建立。

## 成人内容

`mature_content: true` 只是一个请求标记。DeviantArt 的账号浏览偏好仍具权威性，可能隐藏或模糊成人内容。设置中直接链接到 DeviantArt 的浏览偏好；应用不绕过账号限制。

## 面向用户的错误策略

原始端点名、解析器错误、HTTP 负载、包标识与服务商内部信息属于「诊断」。用户界面只说明失败原因与下一步可用操作。认证错误提供重试、重新打开、取消、代理与设置路径，但不会把服务商的挑战页面说成「应用网络故障」。安全存储错误绝不显示为原始的 “Unable to access”；token 存储失败与恢复记录清理告警会被区分开，避免把已完成的授权误报为网络或账号故障。
