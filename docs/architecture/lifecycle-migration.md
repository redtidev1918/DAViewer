# DAViewer Lifecycle Migration

本迁移把“Provider 生命周期=网络请求”逐步改成分层契约。每次只迁移一类边界，
不一次重构全部。

## 1. Repository gate（已落地）

目标：所有页面请求经过 Repository 级 single-flight/cache/dedup。

完成标准：

- `RepositoryRequestGate` 已存在并有测试
- `ArtworkFeedController` 首屏/refresh/pagination 已接入 gate
- 同一 key 并发请求只执行一个 loader
- 失败不缓存
- 显式 force/invalidate 可用

## 2. Controller 请求状态机（已落地）

目标：`ArtworkFeedController` 不再用 `isLoading` 猜测状态。

完成标准：

- `FeedRequestPhase`：idle / loading / refreshing / paginating / stopped
- silent refresh 失败进入 stopped 并保留 lastRefreshError
- 只有 manual refresh、retry、pagination 能再次离开 stopped
- 每次 transition 都有测试

## 3. Session identity 事件化

目标：身份变化通过显式事件触发数据恢复，不再靠 provider watch 链猜测。

完成标准：

- `identity_changed` 事件只由真正登录/登出产生
- personalized feed 对该事件执行一次 reset/load
- CSRF/cookie/health/navigation 不产生同类事件

## 4. 页面组件契约固化

目标：feed card、rail card、detail media 各自拥有布局契约。

完成标准：

- `FeedArtworkCard` / `RailArtworkCard` / detail media 不再复用同一无上下文组件
- 每一类有固定宽高比/文本容量测试
- 任何约束变化可被测试捕获

## 5. 回归测试

每个步骤必须附带：

- 请求次数断言
- 状态 transition 断言
- UI layout overflow 断言
- 登录/登出 identity 事件断言
