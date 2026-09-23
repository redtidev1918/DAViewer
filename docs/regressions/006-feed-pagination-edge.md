# REG-006 Feed pagination edge freeze

## 症状

推荐页持续下滑到当前分页边界后卡住；只有先上滑一段（越过 ~400px 预取区）再滑回
底部，才会继续加载下一页。关键观察：是否卡住取决于底部两张预览图的底端是否对齐
——两列底端高度一致（masonry 两列恰好齐平）时就卡住，不一致时反而会自动加载。

## 根因

两个独立缺陷叠加，都是“把翻页触发绑定到滚动几何上”：

1. 布防依赖几何：`_loadMoreArmed` 原本只在滚动重新经过 `extentAfter >= 400` 时
   重新布防。翻页完成后用户仍停留在底部预取区，是否重新布防取决于新一页是否把
   masonry 较高的那一列继续拉高——两列恰好齐平（新内容填进较矮列）时最大滚动
   高度不变，`extentAfter` 永远 < 400，布防永不恢复，于是必须上滑再下滑。
2. 贴底只有 overscroll：用户已经停在最底端（`extentAfter == 0`）时，再往下拖只能
   产生 `OverscrollNotification`，不会产生带位移的 `ScrollUpdateNotification`，
   处理器只监听后者，即使已布防也永远不会触发。

## 证据分级

- Verified：用户实测——底部两列底端对齐时卡住、不对齐时自动加载；
- Verified：代码路径——布防条件只在 `extentAfter >= 400` 分支置位；贴底拖拽只产生
  `OverscrollNotification`。

## 正确架构

- 只有真实用户滚动才允许触发 `loadMore`（见 REG-002），程序化滚动不触发；
- 布防（re-arm）由 controller 状态驱动：`paginating` → `idle/stopped` 时重新布防，
  与滚动是否重新越过预取区无关；
- 已经贴底（`extentBefore > 0 && extentAfter == 0`）时的向下拖拽（overscroll）也
  必须视为下一页请求；单飞（isLoading/hasMore/backoff）由 controller 负责。

## 修复

`ArtworkFeedGrid`：

- `didUpdateWidget` 在 `feed.phase` 离开 `paginating` 时立即 `_loadMoreArmed = true`
  （布防与几何解耦）；
- `_maybeLoadMore` 监听 `OverscrollNotification`：`extentBefore > 0 &&
  extentAfter == 0`（贴底 overscroll）与预取区内 `ScrollUpdate` 一样触发下一页。

## Regression

- `artwork_feed_grid_test.dart`：`a drag at the exact bottom asks for the next
  page` 覆盖贴底只产生 overscroll 也能触发（两列齐平场景）；
- `artwork_feed_grid_test.dart`：`page completing at the bottom loads again even
  if content barely grows` 覆盖翻页完成后滚动高度几乎不变仍能继续翻页；
- `artwork_feed_grid_test.dart`：`in-flight pagination suppresses repeated bottom
  asks` 保证加载中不重复触发。

## 关联诊断

推荐流成功日志同时输出 `items=N gated=M blurred=B`。DeviantArt 对付费/锁定作品用
模糊 Wix transform（如 `blur_30`）而非显式 feed 字段表达，因此 `gated=0` 不能单独
证明本页没有锁定作品；`blurred>0` 表示存在模糊预览，下一步据此在解析层识别锁定。
