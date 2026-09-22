# DAViewer Data Lifecycle Audit

状态：基于当前工作树代码的审计，不是新架构设计稿。

## 1. 当前请求触发地图

```text
UI build/scroll
  └─ ArtworkFeedGrid / PageView / sections
      └─ Provider access (`ref.watch`)
          └─ StateNotifier / FutureProvider
              └─ ArtworkFeedController constructor → autoLoad
                  └─ Repository / DataAccess / OfficialApiTransport
```

`ref.watch(webSessionProvider)` 已经全部清理为 `ref.read`（执行期读取）。
`ref.read(webSessionProvider)` 用于 Home 推荐、Artist、Search、Web Login、Artwork providers。

## 2. 观察到的 ownership 缺失

| 生命周期 | 当前 owner | 问题 |
|---|---|---|
| initial load | Provider/Controller 隐式 | provider 重建也会触发首次请求 |
| manual refresh | `ArtworkFeedController.refresh()` | 已可用，但 health/cache 曾拦截 |
| pagination | `ArtworkFeedGrid + Controller` | 已收敛，仍需 runtime 验证 |
| retry | UI 回调 | 已改为 force check + refresh |
| identity change → reload | WebLoginScreen invalidate + provider identity watch | 两处都负责，易重 |
| cache | Provider memory / FutureProvider | 失败结果缓存导致 Retry 拿到旧值，已移除部分 |
| viewability | DAKit media availability | 已分离 downloadability/viewability |
| rail layout | 通用 ArtworkCard → 专用 MoreFromArtistCard | 正在替换 |

## 3. 已确认的架构症状

1. Provider lifecycle 直接产生网络副作用：`ArtworkFeedController` 构造时 `autoLoad`。
2. Session/health 状态和请求结果混在同一个 FutureProvider：曾表现为 Retry 无效。
3. WebSession 被数据 provider 订阅：`ref.watch(webSessionProvider)` 仍存在后续点。
4. 同一 Media 模型同时表达“是否可下载、是否可显示”：已用 `viewAvailability` 分离。
5. UI 组件复用无上下文：`ArtworkCard` 被塞进固定高度 rail。
6. 临时 N+1 hydration：上一轮加入后根据日志回滚。

## 4. 最小边界建议

### 4.1 Request 状态应独立于 Data 状态

`ArtworkFeedState` 保留 `items/cursor/error` 作为数据；请求状态（idle/loading/refreshing/failed/stopped）应由 Controller 显式管理，并保证：

- silent refresh 失败可观察
- 不会自动无限 retry
- 手动 retry 每次恰好一个请求

### 4.2 WebSession 只允许 narrow identity 作为数据 provider 依赖

允许：

```dart
ref.watch(webSessionControllerProvider.select(personalizedFeedSessionIdentity))
```

不允许：

- watch 整体 `WebSessionState`
- watch `csrf`
- watch cookie health 后在同一 provider 内再次修改它（已移除）

### 4.3 Repository 层提供 cache / dedup / single-flight

不要继续让 Provider 直接承担请求去重：

- 同一 resource key 的请求只能有一个 in-flight
- 失败结果不能永久缓存
- 成功结果可缓存，但必须能被 identity/显式 invalidate 清理

### 4.4 专用 UI 组件

横向 rail、详情媒体、feed 卡片应各自拥有 layout contract：

- `FeedArtworkCard`
- `DetailMediaViewer`
- `RailArtworkCard`（当前 `MoreFromArtistCard`）

禁止把同一 `ArtworkCard` 塞进多种约束后靠高度魔法修复。

## 5. 本轮已经落地的边界修正

- `personalizedFeedProvider` 只在 `webSessionReady` 后创建
- `webSessionProvider` 在 Home 推荐使用 `read` 而非 `watch`
- `webCookieHealthProvider` 的缓存/自触发 watch 已移除
- 登录成功以 WebView 跳转首页作为服务端确认，并显式 invalidate 推荐一次
- retry 使用 force check + 真实 refresh
- `MoreFromArtistCard` 使用专用固定视口布局

## 6. 下一步审计目标

1. 把剩余 `ref.watch(webSessionProvider)` 全部改成 `ref.read`（它们只用于执行期取 cookie）。
2. 定义每个 feed provider 的 `owner / reason / trigger`。
3. 把 Repository 级 cache/dedup 与 Provider 生命周期解耦。
4. 为“登录后恰好一次推荐恢复”和“手动 Retry 恰好一次”写永久回归测试。
