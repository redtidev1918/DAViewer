# REG-006 Feed pagination edge freeze

## 症状

推荐页持续下滑到当前分页边界后卡住；只有先上滑一段（越过 ~400px 预取区）再滑回
底部，才会继续加载下一页。

## 根因

`ArtworkFeedGrid` 的 `_loadMoreArmed` 只在滚动重新经过 `extentAfter >= 400` 时
重新布防。翻页完成后用户仍停留在底部预取区内，滚动不会再经过该阈值，于是下一次
下滑不再触发 `loadMore`，直到先上滑再下滑。

## 证据分级

- Verified：代码路径——布防条件只在 `extentAfter >= 400` 分支置位；
- Verified：修复后 widget 测试模拟 `paginating → idle` 期间用户停留在底部，
  下一次拖拽即再次翻页；去掉修复该测试失败。

## 正确架构

- 只有真实用户滚动才允许触发 `loadMore`（见 REG-002），程序化滚动不触发；
- 翻页请求结束（`paginating` → `idle/stopped`）时必须重新布防边缘，即使滚动
  从未重新经过预取区。

## 修复

`ArtworkFeedGrid.didUpdateWidget` 在 `feed.phase` 离开 `paginating` 时立即
`_loadMoreArmed = true`。

## Regression

- `artwork_feed_grid_test.dart`：`page completing near the bottom re-arms the
  next edge drag` 覆盖翻页完成后再下滑即翻页；
- `artwork_feed_grid_test.dart`：`remaining near the bottom fires only one edge
  event` 保证同一状态下不重复触发。

## 关联诊断

推荐流成功日志同时输出 `items=N gated=M blurred=B`。DeviantArt 对付费/锁定作品用
模糊 Wix transform（如 `blur_30`）而非显式 feed 字段表达，因此 `gated=0` 不能单独
证明本页没有锁定作品；`blurred>0` 表示存在模糊预览，下一步据此在解析层识别锁定。
