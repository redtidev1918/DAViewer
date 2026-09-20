# DAViewer 架构说明

> English: [DAViewer architecture](/en/architecture.md)

本文界定在处理信息流、详情页、认证、媒体与发版问题最容易模糊的那几条边界。

## SDK 与应用的分界

- **DAKit** 负责 OAuth、官方 DeviantArt API 传输与 DTO 映射、领域模型、凭据安全存储与后台传输；可选的 `dakit_web` 包承载通用私有网页协议解析。
- **DAViewer** 负责 WebView 会话采集/刷新/持久化、能力路由、原生导航与手势、UI 状态，以及宿主侧缓存。
- 网页响应一律先映射为 DAKit 领域模型，再进入业务代码。业务层不得维护第二套作品模型。

在给应用层加绕行方案之前，先确认是不是官方响应被映射错了。映射与传输契约的问题在 DAKit 修；数据源组合、稀疏数据补全、缓存与展示的问题在 DAViewer 修。

## 作品数据流

```text
官方 / 网页列表数据源
        ↓（可能是稀疏的 Artwork）
ArtworkStore.putAll
        ↓
信息流卡片 → 详情路由 → artworkDetailProvider
                            ↓ 缺少仅详情页才有的字段
                  deviation/metadata 适配器
                            ↓
                    ArtworkStore.setTags
```

列表接口合法地省略 tags 之类的字段，而 `deviation/{id}` 并不总能补回来。因此在专用端点 `deviation/metadata` 确认之前，空列表**不能**证明作品没有标签。`ArtworkStore` 单独记录这次解析结果（包括「确认无标签」这一结论），并在后续信息流刷新带回稀疏对象时保留已补全的标签。

规则：

1. 不要让每个信息流都急切拉取全部详情；只补当前可见界面真正需要的字段。
2. 没有合并规则时，不要用稀疏的列表对象替换缓存中的完整对象。
3. 把「确认无标签」的结果也缓存，避免真正无标签的作品每次访问都重新请求。
4. 补全失败可以隐藏该可选区块，但不得让作品详情页整体不可用。

## 能力路由与下载计划

数据源组合由 `SourceCoordinator` + `CapabilityPolicy` 表达，而不是散落在 provider 里。每个能力声明主源和可选备用源；结果必须区分 `success`、`empty`、`failed`、`unsupported` 和 `unknown`。确认的空结果是终态，不会自动触发回退；失败、不支持或未知才允许尝试下一个源。

作品补全用 `HydrationStatus.unknown / resolved / confirmedEmpty`，`mergeArtwork` 是稀疏列表、详情补全和刷新的唯一切入点。下载入口先走 `DownloadPlan`：它根据原图探测结果和当前展示媒体决定可下载资产；图片才允许降级到最高质量展示图，视频海报不得伪装成可下载。

### 预览卡片呈现

所有作品信息流共用 `ArtworkCard` 与预览宽高比辅助函数。卡片是纵向结构：图片保持自身宽高比（手机宽度视口下超宽媒体上限 1.6:1，桌面 2:1，用 `BoxFit.cover` 裁掉外侧边缘，保证缩略图尺寸下主体仍可辨认），标题与作者作为普通卡片区块渲染在图片**下方**，绝不叠在作品之上。新的信息流界面必须复用该卡片，不得恢复固定高度的覆盖层。GIF / 多图角标仍定位在图片本身上。

## 相关内容状态

网站推荐数据有两种受支持的服务端渲染形态：当前的流式 `window.__RCACHE__.relatedContent` 负载，以及旧的归一化 `window.__INITIAL_STATE__` metadata/entities。流式缓存完整时优先使用，否则解析回退到旧状态。缺少 `currentBiMetadata` 条目或缺少归一化实体属于**无法判定**，不等于「确认没有相关推荐」。只有当网站解析与官方回退都无错误地结束，才展示空结果。

相关**作品**在可用时取自网页数据源（它可能与旧预览不同），并回退到官方 `browse/morelikethis` 预览。精选/推荐**合集**只存在于官方预览中，因此 `moreLikeThisProvider` 总是请求官方结果并与网页作品合并（`mergeMoreLikeThisResult`）；这样合集栏目能稳定展示，而不会因为网页数据源偶尔返回作品就整体消失。

刷新相关内容是一次可等待的操作。期间已有卡片保持可见，结束时必须报告三种结果之一：已变化、未变化、仍为空。数据源失败要保留其网络、会话、服务或页面格式分类，不能被空回退掩盖。

Provider/解析器名称与原始异常信息属于诊断数据。用户可见文案只描述结果与下一步（检查中、已更新、未变化、无结果、请登录、检查网络、稍后再试）。

## 合集内容与作者发现

**合集完整内容**（`WebCollectionContentsFetcher`）：官方 API 只接受 UUID 形式的 `folderid`，而预览暴露的是数字 id，因此不存在官方完整内容通道。当有网页会话（Cookie + CSRF）时，DAViewer 读取网站自身的 `_puppy/dashared/gallection/contents` JSON 接口；否则回退到服务端渲染页面（`deviantart.com/{username}/favourites/{folderId}?page=N`，公开、无需会话）。两者作品结构相同，因此映射复用 `WebDeviationMapper.mapDeviation`。界面先立即展示预览里的作品，就绪后替换为完整列表，并提供「在网页中打开」作为兜底。

**合集封面**：「More Like This」预览只有时携带合集缩略图。未携带时，合集卡片通过 `gallection/contents` 惰性解析封面（`collectionCoverProvider`），避免卡片长期空白；文件夹图标占位只是最后手段。

**合集关注未实现。** 官方 API 能关注**用户**（`user/watch`），不能关注某个合集/文件夹；合集关注只存在于未公开的网页接口。在其被逆向（属网页会话工作，不在 DAKit 范围）之前，合集卡片可以原生打开合集，但不提供关注操作。

**更多来自这位作者**（`MoreFromArtistSection`）：读取作者在官方 `gallery/{username}` 首页的其他近期作品。这是干净可用的「作者发现」路径。

**相似作者**（`SimilarArtistsSection`）：DeviantArt 没有公开的相似作者接口——官方 API 只有 `browse/morelikethis`（作品 + 合集），而网站 `biMetadata` 里 `type: "artist"` 是 BI 埋点（作者的账号类型），不是推荐负载。真正的「相似用户」列表来自补全后的未公开接口流式返回（在 `__INITIAL_STATE__`、`__RCACHE__` 与 `dadeviation/init` 中都找不到）。因此 DAViewer 从「More Like This」作品作者推导相似作者（`similarArtistsFrom`）：推荐引擎认定为相关的作品，其作者就是诚实的等价物。未来若有专用数据源，那属于网页会话逆向工作，必须留在 DAKit 之外。

## 手势归属

作品浏览与图片平移共享水平位移，因此归属取决于状态：

- 1x 缩放时，外层查看器可以识别水平作品切换手势。
- 缩放大于 1x 时，外层所有水平回调必须为 `null`；哪怕只注册一个 cancel 回调，也会引入竞争的识别器并可能抢走移动端的平移。
- 多图翻页优先消费位移。只有在内部首页/末页继续向边缘滑动时，才开始作品切换。
- 手势测试必须同时断言「预期位移发生」与「未触发意外的作品切换回调」。

## 认证边界

应用只有一个用户身份：OAuth，用于首页、收藏、关注、画廊、下载以及其他一切官方 API。未登录是引导状态，不是信息流错误。每次可见的尝试都独占一个 OAuth/PKCE 事务，并在应用内嵌 WebView 中打开官方登录页（使用桌面 User-Agent）。账号选择、密码、注册、社交登录与安全校验都由 DeviantArt 的页面负责。`dakit://oauth/callback` 在 WebView 内被拦截并完成同一事务。同一 WebView 会话同时提供仅网页适配器所需的 Cookie 与 CSRF token，因此不需要第二次登录。

WebView 的网页会话（Cookie 与 CSRF）属于基础设施状态，不是认证。它绝不能阻塞首页或弹出登录提示；失败时降级为官方 API 回退或重试。

会话恢复只读取当前的安全项（`DAViewer Account`）。0.2.139 之前预览版产生的临时 Keychain 项永不查询、也不自动迁移，因此无法访问的历史记录不会索要 Mac 密码或阻塞授权。临时的网络、上游、解析或安全存储失败都保留既有可用路由；只有凭据缺失/被吊销或用户显式登出，才进入未登录状态。隐藏的浏览器刷新可能轮换匿名 CSRF。页面不完整永远不等于已登出；与 OAuth 账号不一致的历史 Cookie 用户名会被清除。

设置、代理、诊断、更新与关于属于公开的恢复路径，必须在登录页也可达。

## 发布契约

- `pubspec.yaml` 是发布流程唯一编辑的版本来源。Flutter 通过 `FLUTTER_BUILD_NAME` 暴露给应用。
- 每个 tag 必须在 `RELEASE_NOTES.md` 中有对应的顶层章节；CI 用该章节作为 GitHub Release 正文。
- CI 执行 analyze、格式检查、测试，并构建 Android、macOS 与 Windows。
- Android 发版需要已配置的上传密钥库。macOS 产物使用私有稳定的自签名预览身份以保持 Keychain 连续性，但仍不是 Apple 签名、也未公证；在具备 Developer ID 签名与公证之前，保留 `macos-unsigned-preview` 标记。
- 发布只保留最新的 GitHub Release 可见。Git tag 作为源码历史记录保留，发布任务不会删除它们。

## 应用本地状态

部分状态刻意只保留在客户端，永不同步到 DeviantArt：

- **通知已读状态**（`NotificationReadStore`）：DeviantArt 没有公开的「标记已读」接口，因此未读圆点是叠加在服务端 `isNew` 标记之上的本地状态。它只本地持久化，不假装同步。
- **用户偏好**（`core/settings/AppPreferences`）：语言、主题模式、可选手动代理、OAuth 会话证据与更新提醒状态（上次检查时间、已忽略版本）存放在 application-support 目录下的一个小 JSON 文件中。它们在首帧之前完成恢复，避免应用闪现默认值。
- **搜索兴趣**（`core/search/InterestStore`）：轻量的持久化标签浏览计数，用于跨重启驱动搜索页的个性化「推荐标签」。
- **网页会话 Cookie 快照**（`core/auth/WebSessionStore`）：已登录的 deviantart.com Cookie 与 CSRF/用户名状态一起快照，并在冷启动时平台 WebView 存储丢失（例如跨界应用更新）后重新注入。这能在不重新登录的前提下维持个性化 `rfy` 信息流；快照被限定在当前 OAuth 账号，不构成第二个身份。
- **主题模式**（`core/theme/ThemeModeController`）：跟随系统 / 浅色 / 深色，注入 MaterialApp 并与上述偏好一起持久化。

这些叠加层必须保持本地：一旦加入「同步到服务器」的行为，就越过了官方 API 边界，应属 DAKit 而非应用。
