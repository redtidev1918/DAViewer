# REG-002 Collections request loop

## 症状

日志显示 `collections/all` 约每 0.6 秒重复一次，持续数十秒，且没有用户滚动。

## 根因

历史代码（进入本次未提交修改前）中 `ArtworkFeedGrid` 的
`NotificationListener` 在 `extentAfter < 400` 时对任意 `ScrollNotification`
无条件调用 `loadMore`。Masonry 布局在内容未填满视口时，加载/追加/重建会持续
产生滚动通知；`ArtworkFeedController.loadMore` 只挡住 in-flight，请求成功后
下一次布局通知又可再次触发，形成自动翻页循环。

## 证据分级

- Verified：历史代码路径与当前修复：无条件 `extentAfter < 400` 调用存在于
  `08a6261` 引入 Masonry 起直到本次未提交 guard；当前 grid 只接受真实用户滚动。
- Verified：当前 provider 图上 Web Session 状态变化不会重建/重取
  `currentFavouritesProvider`（见 `session_decoupling_test.dart`）。
- Verified：Home 推荐 provider 的 CSRF rotation 不再作为 identity watch 触发
  重建（`9511a19` + `personalized_feed_refresh_policy_test.dart`）。
- Unverified：原始 0.6～0.7s 的 runtime 日志未在本次本地环境重新捕获；仍不能
  排除历史上存在 Web Session/Home 组合触发的叠加因素。

## 错误架构

- Widget 布局事件直接触发网络请求；
- 只有 in-flight guard，没有真实用户滚动判定，也没有失败 backoff。

## 正确架构

- 只有真实用户滚动才允许触发 `loadMore`：触摸/鼠标拖拽与触控板/滚轮都要放行，
  程序化滚动（`jumpTo`/布局重排）不触发；
- Provider/Controller 只持有状态，不因 rebuild 隐式发请求。

## 修复

- `ArtworkFeedGrid` 通过 `Listener` 记录拖拽与 `PointerScrollEvent`，再配合
  `ScrollUpdateNotification` 判定真实用户滚动；
- `ArtworkFeedController` 对 pagination 失败增加有界 backoff，成功后重置。

## Regression

- `artwork_feed_grid_test.dart`：rebuild/programmatic scroll 不产生 `loadMore`；
- `artwork_feed_grid_test.dart`：trackpad scroll 与真实 drag 到底部都会触发
  `loadMore`；
- `artwork_feed_controller_test.dart`：pagination 失败进入有界 backoff，期间不
  产生 HTTP，成功后重置；
- 未来加入 Network Budget Test：同一页面生命周期 `collections/all <= 1`。
