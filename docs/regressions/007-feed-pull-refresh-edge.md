# REG-007 Feed pull-to-refresh requires a second gesture off the top

## 症状

推荐页下滑到任意位置后，直接下拉不会刷新；必须先上滑回到顶部，再下拉一次才会
触发刷新。

## 根因

`AppRefreshIndicator` 默认使用 `RefreshIndicatorTriggerMode.onEdge`。该模式下
`RefreshIndicator` 只在滚动位置已经位于顶部（`extentBefore == 0`）的拖拽开始时
才开始跟踪下拉量；从非顶部位置下拉只会把列表滚回顶部，本次手势不会进入刷新状态，
于是用户需要第二次下拉。

## 证据分级

- Verified：代码路径——onEdge 下 `_shouldStart` 要求 `extentBefore == 0`；
- Verified：修复前 widget 测试从 200px 位置单次下拉 600px 不触发
  `onRefresh`；修复后同一步骤触发。

## 正确架构

- 下拉手势本身仍保持“必须越过顶部并超过指示器阈值”才刷新，不应把任意小幅上移
  误判成刷新（仍尊重 `dragDetails`，程序化滚动不会触发）；
- 单次连续下拉手势：从任意位置下拉 → 滚回顶部 → 越过阈值 → 刷新，一气呵成。

## 修复

`AppRefreshIndicator` 增加 `triggerMode: RefreshIndicatorTriggerMode.anywhere`。
该模式允许在拖拽过程中滚动到达顶部后继续跟踪下拉量，从而单次手势完成刷新。

## Regression

- `artwork_feed_grid_test.dart`：`pull-to-refresh from a scrolled position works
  in one gesture` 覆盖“非顶部下拉一次即刷新”；
- 既有 `rebuilds never load more` / `programmatic scroll never loads more`
  保证该改动不会把程序化滚动误判为刷新。
