# 网页适配器 —— 兼容性契约

> English: [Web adapter — compatibility contract](/en/web_adapter.md)

DAViewer 与两个 DeviantArt 表面通信：

- **官方 OAuth API**（稳定、有版本、由 DAKit 负责）。
- **网站私有 JSON/HTML 接口**（不稳定、未公开），用于官方 API 未暴露的少数详情功能：数字 id 解析、相关作品区块、合集完整内容、真正的作品搜索、画廊关键词搜索，以及个人资料事实（关注者数/加入日期）。

本文是第二个私有表面的兼容性契约。它的目标不是阻止 DeviantArt 变更——那不在我们控制之内——而是让任何变更**易于发现、易于修复**。

## 代码位置

通用私有协议适配器现在集中在 [DAKit 的 `dakit_web`](https://github.com/redtidev1918/dakit/tree/main/packages/dakit_web) 包里。这个包是可选适配层，不代表私有端点稳定；`dakit_web` 只负责“session + request → DeviantArt DTO → DAKit 模型”。

DAViewer 继续持有产品边界：WebView 登录、Cookie/CSRF 刷新与持久化、`SourceCoordinator` 能力路由、`ArtworkStore` 合并规则，以及 UI 降级文案。应用中的产品级 wrapper 仍在 `lib/core/data/`（例如 `collection_contents.dart` 与 `web_session.dart`）；HTML/JSON 解析不得回到业务代码。

## 三层防御

1. **稳定接口隔离。** 业务代码只依赖一个小接口或 DAKit 领域模型（`CollectionContentsSource.contents`、`Artwork`、`DeviationInit`），绝不依赖原始 HTML/JSON。站点变更在一个适配器内修好，不必碰任何界面。

2. **宽容解析 + 优雅降级。** 每个适配器都防御式解析（单条畸形数据跳过，而不是致命错误），并带有回退：官方 API、预览数据，或直接隐藏该可选区块。网页失败绝不能拖垮作品详情页。

3. **针对抓取快照的契约测试。** `dakit_web` 的每个解析器都有一个使用合成 fixture 的提交式单元测试，外加一个受门控的实时快照测试——当对应的 `DA_*` dart-define 指向真实抓取页面时才会读取。DeviantArt 结构一变，快照测试就会变红并直接点名是哪个解析器。

## 端点注册表

| 功能 | 模块 | 端点 / 数据源 | 会话 | 回退 | 契约测试（快照 define） |
| --- | --- | --- | --- | --- | --- |
| 个性化首页信息流 | `RfyFeedFetcher` (`dakit_web`) | `_puppy/dabrowse/networkbar/rfy/deviations` | 网页 Cookie + CSRF（已登录） | 无（需要网页会话；展示登录提示） | `rfy_feed_test.dart` —— `updatedTime ?? publishedTime` 提供给作品时间戳，使排序反映编辑 |
| 数字→UUID + 简介 + 日期 | `DeviationInitFetcher` (`dakit_web`) | `_puppy/dadeviation/init` | 匿名浏览器 CSRF | 简介回退到短摘要；标签为空（官方 `deviation/metadata` 只服务 OAuth 作品）；日期回退到信息流条目的发布时间 | `deviation_init_test.dart`（`DA_DEVIATION_INIT_JSON`）—— 同时解析 `publishedTime` / `updatedTime` 供详情页日期行使用 |
| 相关作品 | `WebMoreLikeThisFetcher` (`dakit_web`) | 作品页 `__INITIAL_STATE__` / `__RCACHE__` | 无（公开） | 官方 `browse/morelikethis` | `web_more_like_this_test.dart`（`DA_MORE_LIKE_THIS_HTML`） |
| 合集完整内容 | `WebCollectionContentsFetcher` (`dakit_web`) + DAViewer `WebCollectionContentsSource` | `_puppy/dashared/gallection/contents`（JSON），回退 `deviantart.com/{user}/favourites/{id}?page=N` | 匿名浏览器 CSRF（JSON）/ 无（SSR） | 预览作品 + 在网页中打开 | `web_collection_contents_test.dart`（`DA_COLLECTION_JSON`、`DA_COLLECTION_HTML`） |
| 作品搜索 | `WebSearchFetcher` (`dakit_web`) | `_puppy/dabrowse/search/deviations` | 网页 Cookie + CSRF（已登录） | 官方 `browse/home?q=`（粗粒度，无需网页会话） | `web_search_test.dart` |
| 画廊关键词搜索 | `WebGallerySearchFetcher` (`dakit_web`) | `_puppy/dashared/gallection/search` | 匿名浏览器 CSRF | 无（搜索需要网页会话） | `web_gallery_search_test.dart` |
| 个人资料事实（关注者/加入日期） | `WebUserProfileFetcher` (`dakit_web`) | `_puppy/dauserprofile/init/about` | 匿名浏览器 CSRF | 无（响应头缺少该富信息） | `web_user_profile_test.dart` |

共享的、非端点辅助模块（无独立回退，直接测试）：

| 辅助 | 模块 | 用途 | 测试 |
| --- | --- | --- | --- |
| Wix 媒体描述 → URL | `wix_media.dart` (`dakit_web`) | `baseUri` + `prettyName` + `types` 解析 | `wix_media_test.dart` |
| JS 字面量 JSON 解码 | `html_state.dart` (`dakit_web`) | `window.__X = JSON.parse("…")` 解码 | 由上面的快照测试覆盖 |
| HTML / tiptap → 文本/HTML | `html_text.dart` (`dakit_web`) | 简介渲染 | `html_text_test.dart` |
| 公开浏览器状态 | `web_session.dart` | 读取匿名浏览器 Cookie | `web_session_refresh_policy_test.dart` |
| 链接 → 路由 | `da_uri.dart` | 粘贴链接解析（无网络） | `da_uri_test.dart` |

派生区块或使用官方 API 的区块（`more_from_artist`、`similar_artists`）**不是**网页适配器，不在此列。

## DeviantArt 变更时的排查手册

1. **用最新抓取运行快照测试**，看是哪个解析器坏了：

   ```bash
   cd /path/to/dakit/packages/dakit_web
   dart test --dart-define=DA_MORE_LIKE_THIS_HTML=/path/to/artwork.html \
             --dart-define=DA_COLLECTION_HTML=/path/to/folder.html \
             --dart-define=DA_DEVIATION_INIT_JSON=/path/to/init.json
   ```

2. **把失败定位到一个适配器**。快照变红意味着「那一个端点的结构变了」，而不是「应用坏了」。

3. **只在那一个文件里修解析器**，保持映射出的 DAKit 模型不变。除非端点彻底消失，否则优先宽容读取（跳过坏条目）而非严格解析。

4. **刷新快照**并重跑；若 URL 或回退变了，同步更新上面的端点注册表。

5. **若端点被移除**，不要臆造替代品。改用官方 API 路径或隐藏该区块，并更新此处的回退列。

## 抓取快照

快照是本地保存的真实响应（**不提交**——它们体积大且随站点每次变更而变）。抓取方式：

- **公开页面**（作品、合集）：用浏览器 User-Agent 保存页面 HTML（无需登录）。
- **浏览器形态端点**（`dadeviation/init`）：从公开浏览器会话抓取 JSON 响应。fixture 中不要包含账号 Cookie。

`DA_*` dart-define 指向这些文件；未设置时受门控的测试会跳过，因此 CI 永不依赖抓取页面。
