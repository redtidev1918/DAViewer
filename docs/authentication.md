# 认证与会话恢复

语言 / Language：中文 · [English](en/authentication.md)

DAViewer 只有一个用户身份：官方 DeviantArt OAuth 会话。应用既不接收也不存储 DeviantArt、Google、Apple、Facebook 或 Mac 的密码。凭据与各服务商的安全校验都留在 DeviantArt 官方页面，应用只在自己的内嵌 WebView 中展示该页面。

## 登录与常见问题

选择「登录或创建账号」，在应用内嵌的 DeviantArt 官方页面完成授权。一次正常登录同时建立 OAuth 和网页会话；应用不会保存账号密码。

| 情况 | 处理方式 |
| --- | --- |
| 登录页打不开或卡住 | 关闭登录页后重开；在设置中检查代理并运行连通性测试 |
| 官方页面要求验证码或账号确认 | 在当前页面完成校验，应用会等待授权回调 |
| 推荐提示恢复，但每日精选可用 | 网页会话与 OAuth 状态不同；按推荐页提示恢复网页会话 |
| macOS 提示钥匙串权限 | 允许应用访问账号存储；更新后的授权表现受签名环境影响 |
| 成人内容被隐藏或模糊 | 打开「设置 → DeviantArt 账号设置 → 成人内容设置」，检查网站账号偏好 |
| 需要更换账号 | 先登出，再登录；Cookie 导入不允许混用账号 |

代理覆盖范围见 [网络与代理](networking.md)。下面说明会话实现与恢复规则。

## Android 恢复事务（2026-10-12 修正）

v0.5.13 的 Android 原始故障仍未通过实机验收。源码确认 HTTP 解析失败被归类为匿名、Headless 在只有 CSRF 时提前结束；`rfy-4` 的实际废弃原因仍需要候选版日志验证，不能从现有日志确定。

`WebSessionStatusController` 是恢复事务协调器：冷启动、响应信号、前台恢复和 Feed 的上下文刷新共享 single-flight。它管理 `recoveryId`、`accountEpoch` 和 generation；账号变化使旧结果失效。Cookie 恢复归并并保留现有有效 Cookie，不以 Cookie、OAuth 或 CSRF 单独授予健康状态。

后台及可见 WebView 使用 `BrowserSessionObserver`：加载、历史导航和有界采样收集同源页面身份，20 秒总预算不随事件延长。CSRF 已有但身份尚未初始化时继续观察；只有页面明确 `anonymous` 才是匿名证据，缺失/解析失败为不确定。首个 anonymous 样本不直接定论：探测会 reload 一次做佐证，且复核结论必须来自严格更新的已提交主文档代际（SPA History 不算新文档）（reload 尚未落地时同文档的重读不完成探测，回落 unavailable）；只有复核后仍是 anonymous 才完成匿名结论（重定向中间态、匿名壳页不会单样本登出）。confirmed 样本仍立即完成，真实登出不受延迟影响。人工恢复停止隐藏浏览器，使用共享原生 Cookie Store 和显式首页导航；没有宣称原生实例转换已在 Android 验证。可见页面的用户导航可以打开新的有界观察窗口。

推荐的请求所有权在 `ArtworkFeedController`；明确区分初次加载、会话恢复、用户刷新、前台刷新、凭据上下文变化和分页。RFY 调用 DAKit 公共 fetcher 的可取消、单次请求接口，禁用隐式 HTTP CSRF 重试。成功响应只有在账号 epoch、请求所有者和健康状态仍有效时才能接受；已确认的同账号恢复可以接收非通用旧响应。**同代际**的 Cookie/CSRF 轮换只有在判决链确认过轮换后的凭据集（`verifiedCredentialFingerprint` 匹配，例如本应用同会话探测导航并确认了新 Cookie）时才采纳在途响应；未经确认的轮换保持 `credentials_changed` 保守废弃——"没有观察到账号变化"本身不构成轮换安全的证明。跨代际与跨账号的守卫全部保留。

诊断页的导出按钮合并最近 20 次启动日志，每次最多 512 KiB，标明截断并脱敏；界面上的最后 120 行仍只是一段预览。每次启动独立文件不覆盖旧日志。日志及时串行刷盘，但不能保证突然断电/强杀瞬间的最后一条写入。日志带 buildRevision；候选 APK 的签名和该 SHA 必须核验后才用于覆盖升级。

状态对应：unknown=尚未恢复，healthy=verified，unverified/unavailable=inconclusive，anonymous=明确匿名，locked=blocked。恢复中与人工交互属于事务阶段，保留已有 UI 状态契约。流程与验收见 [REG-021](regressions/021-android-session-recovery.md)。

## 单入口登录契约

Android 使用 DAKit 的 `app_links` 回调源，Manifest 关闭
`flutter_deeplinking_enabled`，避免同一回调进入 Flutter 路由并提前移除登录页。
WebView 和原生回调交给同一个 PKCE 事务消费；网页显示首页本身不代表 OAuth 成功。

OAuth 与账号加载成功后，如果 Web 身份观察到期，页面解除同步遮罩并显示
推荐会话尚未确认。账号和 Cookie 保留；刷新可启动新的有界观察窗口。
旧窗口的迟到采样不能关闭页面或触发推荐请求。

Token、PKCE 和网页协议解析由 DAKit 负责。TokenStore 写入、世代复核和过期清理
处于同一个串行事务；调用者超时不释放尚未完成的原生 I/O 队列。同一世代的有效
迟到写入被保留，超时本身不是登出。应用同步启动 SDK 登出隔离，不等待宿主 I/O，
也不在旧清理失败后再次登出新账号。RFY 使用 SDK 公共 fetcher 的 `CancelToken`
和 `retryInvalidCsrf: false`，替代应用独立的 Dio/DTO 解析绕行。

应用只暴露一个 **登录或创建账号** 操作，它打开内嵌登录界面：

1. DAKit 创建一个 OAuth/PKCE 事务。
2. DAViewer 以内嵌 WebView 加载官方登录页；Android 保留系统 WebView User-Agent，桌面平台使用桌面 User-Agent。
3. 账号登录、注册、找回密码以及当前提供的全部服务商（DeviantArt、Google、Apple、Facebook）都由 DeviantArt 页面负责。应用内没有单独的「社交登录」路径。
4. `dakit://oauth/callback` 在 WebView 内被拦截并完成同一事务。WebView 保留其 Cookie 与 CSRF token，因此这一次登录同时建立了后续个性化 `rfy` 信息流与合集适配器所需的网页会话，不再要求第二次登录。

每次打开内嵌登录页都会取消上一次遗留的陈旧 OAuth 事务并新建 PKCE 事务，
避免用户在“上一次登录已挂在 isLoggingIn”的状态下只刷新了网页 Cookie，
随后官方 API 页面仍然显示未登录。

应用不模拟服务商按钮点击、不内嵌密码表单、不从系统浏览器拷贝 Cookie。浏览器只收集挑战/锁定状态以解释恢复结果，不尝试绕过校验。Google、Apple、Facebook 仍可能展示账号选择或 CAPTCHA，须由用户完成。

## 会话角色

- **OAuth 会话**（安全存储）驱动官方 API：每日作品、作品查询、收藏、关注与下载，以及搜索结果中的用户列表。
- **网页会话**（WebView 的 Cookie 加 CSRF token 与登录态，本地持久化并在启动时恢复）驱动仅网页可用的适配器：个性化 `rfy/deviations` 信息流、合集内容，以及搜索结果中的作品列表（优先网页端点 `_puppy/dabrowse/search/deviations`，官方 `browse/home?q=` 作为回退）。已登录 Cookie 会快照进应用自身存储，并在冷启动时平台 WebView 存储丢失（例如跨界应用更新）后重新注入，从而不必重新登录也能保住个性化信息流。

网页会话的 Cookie、CSRF 和账号信息使用平台安全存储，独立于 OAuth token。升级时自动迁移应用支持目录内旧的 `web_session.json`：写入安全存储并读回验证后才删除旧文件。存储不可用或数据损坏时保留原凭据供重试，不回退到明文写入。迁移成功前，旧文件仍等同于登录凭据，请勿复制或公开。

网页身份可以先于 OAuth 账号到达；账号加载后会重新采样当前文档，避免等待不会再发生的导航。CSRF 和 Cookie 本身不是健康证据，旧账号世代的观察不能覆盖新状态。

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

只要应用进程存活，内存中的 PKCE 事务就是权威。它的安全存储副本只用于进程重启后恢复回调：写入、读取或清除该恢复副本失败，绝不能推翻仍在进行的授权结果。只有新 token 已安全存储，登录才被判定成功。

`dakit` scheme 由内嵌 WebView 持有，它拦截 OAuth 回调且从不离开应用。只有在没有注册 WebView 监听器作为回退时，以及「内容设置」跳转 DeviantArt 浏览偏好时，才使用系统浏览器。

## 冷启动契约

1. 没有冷启动 OAuth 回调时，跳过待处理事务存储，只读取当前 OAuth token。
2. 只有凭据缺失或被吊销才判定为未登录。临时性的网络、上游、超时、解析与 Keychain 不可用故障都保留既有会话。
3. 只有在安全存储成功读写 token 之后，才记录非敏感的会话证据。这能避免首次运行的网络错误把匿名用户送进首页，同时保住老用户的离线恢复能力。
4. 显式登出会清除当前 OAuth 存储、会话证据与 WebView Cookie。

`oauthSessionKnown=false` 是显式登出的权威证据：即使清理 token 时安全存储失败，
下次冷启动也不会因为遗留 token 重新进入 `signedIn`。
网页 Cookie 的可用性也由 DeviantArt 首页服务端验证
（`@@publicSession.isLoggedIn` + `@@publicSession.user.username`），本地存在 Cookie 不等于会话有效。裸 HTTP
首页探测可能被 WAF 干扰，但 `rfy/deviations` 成功**同样不是**健康证据：匿名
Cookie 也能拿到 HTTP 200 的通用内容。匿名探测结果由真实 headless WebView
(与登录相同的 Cookie 栈）仲裁：确认同一账号 → healthy；真实浏览器**经复核确认**
匿名 → anonymous 并提示重新登录；真实浏览器无法作答（挑战/网络）→ 保持
unverified，绝不静默降级。本地空 Cookie 与瞬时读取失败在已登录账号下同样只产生
unavailable，不产生匿名结论。

headless 探测使用共享观察器的有界窗口，不再靠三次加载停止计数结束。
挑战页、缺失身份和初始化中的页面均不产生匿名结论；导航完成后继续采样。
首个 anonymous 样本触发一次 reload 佐证，复核仍匿名才返回 anonymous；
截止时仍无可信身份则返回 unavailable（→ unverified），**绝不返回 anonymous**。

个性化推荐的首屏请求有明确所有权（见
[REG-019](regressions/019-first-page-request-ownership.md)）：验证恢复与显式重试
属于同一事务，只发一次请求；`refresh()` 在当前页仍属于同一会话上下文
（CSRF + Cookie 指纹）时是幂等的，上下文轮换（Cookie/CSRF 变化）则必须重新取；
用户手势（下拉刷新、重载）走 `forceRefresh()`，总是重新请求。登录确认**不再**
`invalidate` 推荐 Provider——恢复由健康转变监听与会话身份 select 接管。
推荐缓存只是冷启动预览（见
[REG-020](regressions/020-personalized-feed-cache.md)）：按账号隔离、带版本与原子写，
缓存不可用或失败都不得阻塞或破坏实时推荐请求。

职责边界（见 [REG-011](regressions/011-session-boundary-refactor.md)）：只有验证层能产生 verdict；Cookie 存储、
后台探测（只轮转 CSRF）、feed 成功/失败、UI 都没有写权限。所有 verdict
变更经由 `WebSessionStatusController.applyVerification` 单一入口，带代际
保护与 source 日志；`webSessionReadyProvider` 只表示启动 readiness，不等于
会话健康。

## 使用中发现 Cookie 失效

会话失效的触发点只有一个：`WebSessionCoordinator`。它在共享 HTTP 客户端上观察网页响应——HTTP 401/403、最终落到 `/users/login` 的重定向、响应中嵌套的 `mature_loggedout`——并每分钟复核一次、在应用回到前台时立即复核，因此 Cookie 已死但接口仍返回 HTTP 200 的情况也能被发现。CDN／图片主机、验证用的首页探针与 OAuth 端点不作为会话证据。触发层只上报信号，不产生结论：明确的网页登录限制或原因不明的模糊预览会绕过最近成功的五分钟缓存请求复核，明确的纯付费限制不单独触发 Cookie 校验。同一批卡片共享在途校验，后续触发间隔至少 30 秒，并遵守网络和验证页面的退避状态。模糊图本身不能证明 Cookie 失效；仍由上述服务端验证链判断。拓扑与排除规则见 [网页会话与提醒](architecture/web-session-and-notices.md)。

确认匿名后，主页面和作品详情页均显示重新登录入口。网络错误或验证页面不会被报成 Cookie 过期。登录页确认会话恢复后，会清除作品媒体的旧解析标记，并重新加载详情、附加图片、原图查询和更多推荐。

更多推荐中的可疑预览还会通过官方 OAuth 详情接口核对同一作品。官方查询失败时，可回退到完整网页详情。作者与作品路径匹配、返回明确媒体或访问限制后，才更新缓存；真实付费限制继续保留。两种来源都无法确认时保留服务端预览，不修改模糊图 URL。详细状态规则见 [作品访问状态](architecture/artwork-access.md)，回归记录见 [REG-013](regressions/013-mature-related-preview.md)。

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

token 与恢复存储使用 `DAViewer Account` Keychain 服务；更早的 ad-hoc 项不查询，避免历史记录阻塞授权。当前 macOS 构建脚本没有导入稳定预览证书或公证步骤，因此更新后仍可能出现系统钥匙串授权提示。

本地 `ad-hoc / 无 TeamIdentifier` 是接受的环境限制，不因缺少付费 Developer ID 签名阻止发布；应用自身重复读写、删除或创建 Keychain 项仍需排查。发布验收见 [发布门禁](release-gate.md)。

首页 **推荐 / For you** 标签是网站的个性化 `rfy/deviations` 信息流，使用 WebView 的 Cookie 与 CSRF token 拉取。它需要已登录的网页会话；网页会话缺失、正在恢复或被权威判定匿名时，该标签展示登录/恢复提示，**绝不静默渲染匿名 Cookie 拿到的通用内容**，也绝不自动切到 **每日精选 / Daily** 标签（该标签使用官方 OAuth API，不依赖网页会话，只在用户主动切换时显示）。产品上不得把这两个数据源表述为等价。

推荐页先取得五分钟内的服务端登录确认。确认匿名时提示登录；网络或挑战页面导致
无法确认时停止加载，并提供网页登录入口，不会直接宣布 Cookie 过期。

网页登录有效也不代表推荐内容一定经过个性化确认。历史上记录过 `vespa_content_group=2`
游标与通用回退内容的关联（REG-009/022），但该信号**未经协议确认**：服务端确认
已登录的会话同样会收到它。因此疑似通用批次会照常显示，绝不写入个性化冷启动
缓存，也**不单独**构成登录问题或用户可见的降级告警（REG-024 RC1，仅记录诊断
日志）；真正的会话失效仍由权威判决链识别并展示恢复入口。

## 检查应用更新

应用启动、回到前台及前台持续使用时会检查正式 Release；成功结果缓存五分钟。
有新版时首页显示更新条，点开会在浏览器中打开 Releases 页面，由用户自行下载安装——应用只做检查，不会自动下载或安装更新。关闭后不再提醒同一版本，设置中的
「检查更新」仍可使用，并可查看当前版本说明。获取失败会明确显示检查失败。

如果旧版未显示更新条，请通过设置手动检查，或打开 [Releases](https://github.com/redtidev1918/DAViewer/releases)
下载。0.5.10 修复了部分旧发布包没有向应用传入版本号、导致自动检查跳过的问题；
这项修复需要安装新版才能生效。

## 公开网页适配器

少数详情页功能需要未公开的公开网页数据，例如数字 id 解析与合集内容。内嵌 WebView 的网页会话（Cookie 与 CSRF token）按需提供这些能力。这些公开详情适配器不要求单独登录；不可用时按能力规则重试、使用预览或官方 API 回退。首页个性化推荐的会话要求见上文。

历史浏览器 Cookie 仅为兼容公开适配器而接受。若它们暴露的用户名与 OAuth 账号不同，会被清除，以防混账号数据。

## Cookie 查看、导出与导入

设置 → **账号 Cookie** 以缩进 JSON 展示当前的 deviantart.com 网页会话 Cookie，并可复制到剪贴板，便于用户查看或备份网页会话。优先使用 WebView 的实时 Cookie；WebView 存储不可读时回退到已持久化的快照。该对话框明确警告这些 Cookie 等同于登录凭据。导出是用户主动的手动复制：应用不会把任何内容发送到别处，诊断/报告输出也从不包含 Cookie。

同一对话框也支持粘贴导入：导出的 JSON、浏览器扩展 Cookie 数组（非 DeviantArt 域名会被忽略），或 `name=value; …` 形式的 Cookie 头。导入是应用中最敏感的写入操作，遵循严格的一账号规则（`evaluateCookieImportIdentity`）：

1. 导入的 Cookie 必须带有已登录的 `userinfo` 用户名；匿名粘贴会被拒绝。
2. 若已登录 OAuth 账号，导入的用户名必须与之一致。
3. 若 WebView 已有已登录网页会话，导入的用户名必须与之一致。
4. 冲突会在**写入任何 Cookie 之前**被拒绝。应用不把一个账号的会话叠加到另一个账号上。要切换账号需先登出。
5. 注入完成后会从 Cookie 存储回读用户名。若 DeviantArt 不认可所声称的会话（Cookie 过期/无效），则恢复原有 Cookie，不持久化任何内容。

导入校验通过后，快照会被持久化、网页会话状态被更新，并触发一次 CSRF 刷新，使网页适配器使用新会话。仅网页的导入会话（无 OAuth 账号）可驱动网页适配器与个性化信息流，但官方 API 功能仍需 OAuth 登录。因此导入之后，应用会再提供一次常规内嵌登录：DeviantArt 页面会识别导入的 Cookie，通常无需输入密码即可完成，用户也可以关闭该提示（网页功能继续可用；官方 API 功能在使用时再次要求登录）。官方 API 会话只能通过 OAuth/PKCE 流程建立；导入 Cookie 后仍需完成 OAuth 登录。

## 成人内容

`mature_content: true` 只是一个请求标记。DeviantArt 的账号浏览偏好仍具权威性，可能隐藏或模糊成人内容。设置中直接链接到 DeviantArt 的浏览偏好；应用不绕过账号限制。

## 面向用户的错误策略

原始端点名、解析器错误、HTTP 负载、包标识与服务商内部信息属于「诊断」。用户界面只说明失败原因与下一步可用操作。认证错误提供重试、重新打开、取消、代理与设置路径，但不会把服务商的挑战页面说成「应用网络故障」。安全存储错误绝不显示为原始的 “Unable to access”；token 存储失败与恢复记录清理告警会被区分开，避免把已完成的授权误报为网络或账号故障。
