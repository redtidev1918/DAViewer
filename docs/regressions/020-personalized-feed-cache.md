# REG-020 个性化推荐缓存

## 症状

冷启动（尤其已登录、会话尚在恢复）时推荐页只有骨架屏，直到会话确认 + 首个
rfy 请求返回才出现内容；同时 Widget 测试出现
`A Timer is still pending even after the widget tree was disposed`。

## 根因

缓存水合（`_hydratePersonalizedFeedFromCache`）被放在首屏请求之前，并且水合
结束时才调用 `refresh()`；缓存目录解析使用
`getApplicationSupportDirectory().timeout(Duration(seconds: 3))`。结果是：

- fake-async 的 Widget 测试里缓存 I/O 永不返回 → 首屏请求被无限延迟 →
  `pumpAndSettle timed out`；
- 超时定时器在 Widget 销毁后仍挂着 → 残留 Timer 报错；
- 线上：存储慢（或平台无支持目录）时，**缓存成了推荐请求的强制依赖**。

## 错误架构

- 让缓存 I/O 决定首次推荐请求的时机；
- 用加超时/加等待掩盖问题，而不是消除依赖；
- 把”展示缓存预览“与”请求实时数据“串行化。

## 正确架构

- 缓存只是**预览**，不是前置条件：Provider 创建时立即发起实时首屏请求，
  水合并发进行，且仅在列表仍为空时补种数据；
- 存储不可用/失败不影响推荐请求，失败按 warning 记录后放弃缓存；
- 不引入人为超时定时器：目录解析失败（如平台无支持目录）直接退化为无缓存；
- 缓存按账号隔离（用户名分桶），带格式版本号，原子写 + 条数上限；
- Provider 销毁后不再回写状态。

## 修复

- 新增 `lib/core/feed/artwork_feed_cache.dart`：`ArtworkFeedCacheSnapshot` +
  `ArtworkFeedCacheStore`（`formatVersion = 1`、最多 60 条、按 `username` 分桶、
  临时文件 + rename 原子写、损坏/过期视为无缓存）；
- `lib/features/home/home_providers.dart`：新增
  `feedCacheDirectoryProvider`（测试注入临时目录），首屏请求与缓存水合解耦，
  移除 `timeout` 兜底；
- `lib/shared/widgets/artwork_feed_grid.dart`：保留旧数据的刷新失败提示带上
  “上次成功加载时间”，区分”有内容但刷新失败“与”空列表失败“。

## Regression

- `home_pagination_no_auth_damage_test.dart` 与
  `home_refresh_no_probe_test.dart` 注入临时缓存目录运行，不再出现残留 Timer；
- `home_refresh_no_probe_test.dart`（新增）：**不提供缓存目录**时，个性化推荐
  仍然只发一次实时请求并渲染真实内容，Widget 销毁后无残留 Timer；
- 缓存水合不改变首屏请求次数（水合不设置”已取到首屏“标记），保证冷启动
  永远有实时推荐。
