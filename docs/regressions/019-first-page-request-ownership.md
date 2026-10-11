# REG-019 首屏请求所有权

## 症状

登录确认后推荐页对第一页发起两次请求：一次来自健康状态恢复监听
（`recoverInitialPage` → `refresh()`），一次来自显式 `refresh()`（登录页的
`ref.invalidate(personalizedFeedProvider)`、重试按钮或恢复后的立即刷新）。
用户看到列表被重建、`Provider` 从 id=1 变成 id=2，第一页重复拉取。

## 根因

两处叠加：

1. `web_login_screen.dart` 在登录确认后显式 `ref.invalidate(
   personalizedFeedProvider)`，与既有的”健康转变监听 + 会话身份 select 重建
   Provider“两条恢复路径重复触发首次请求；
2. `ArtworkFeedController.refresh()` 是”总是发起“语义，因此”同一事务内的
   两次调用“（验证恢复 + 显式刷新）无法收敛成一次请求。

## 错误架构

- 用”再次失效 Provider“表达”会话恢复了“，而不是让既有恢复路径接管；
- 请求所有权不清：任何调用点都能重复发起首屏请求；
- 用修改断言数字（例如把期望从 1 改成 2）掩盖重复请求。

## 正确架构

- **登录确认不失效 Provider**：恢复交给 `home_providers` 的健康转变监听
  （`recoverInitialPage`），账号切换由会话身份 select 重建 Provider 处理；
- **首屏请求有明确所有权**：`refresh()` 是幂等入口——同一事务内的重复调用
  合并到在飞请求，且当前页仍属于**同一会话上下文**时不再发请求；上下文
  （CSRF + Cookie 头指纹）变化说明缓存页已过期，必须重新取；
- **用户手势用 `forceRefresh()`**：下拉刷新/重载必须重新请求，不受幂等约束；
- 失败会释放所有权（`error`/`lastRefreshError` 非空即重新取），保证重试可用。

## 修复

- `lib/core/feed/artwork_feed_controller.dart`：新增 `sessionContextKey`、
  `_firstPageFetched` / `_firstPageContextKey`，`refresh()` 幂等化，新增
  `forceRefresh()`；
- `lib/features/home/home_providers.dart`：为个性化推荐传入
  `feedSessionContextKey(csrf, cookieHeader)`（sha256，不落明文）；
- `lib/features/home/home_screen.dart`：重试按钮与下拉刷新走
  `forceRefresh()`，并保留”恢复已拥有请求时不重复发起“的守卫；
- `lib/features/web_login/web_login_screen.dart`：移除登录确认后的
  `ref.invalidate(personalizedFeedProvider)`。

## Regression

- `home_refresh_no_probe_test.dart`：`explicit retry ...` 整个重试事务只有一次
  rfy 请求（含探针计数）；下拉刷新测试要求”挂载 1 次、拖拽 +1 次“，证明
  `forceRefresh()` 仍然真正重新请求；
- `artwork_feed_controller_test.dart`（新增 `first-page ownership` 组）：同上下文
  重复 `refresh()` 不重复请求、上下文轮换后重新请求、`forceRefresh()` 总是
  请求、失败后重试重新请求；
- `home_refresh_no_probe_test.dart`：`changed cookies bypass a recently healthy
  identity lease` 锁定”Cookie 轮换必须重新取“。
