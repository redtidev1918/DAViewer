# REG-022 降级推荐整批丢弃导致首页不可用与登录误报

## 症状（2026-10-13 13:38 Android 生产日志）

登录成功（OAuth 交换、`whoami` 200、`@@publicSession` 身份解析、Cookie 持久化、
Web Session `healthy` 全部正常）后，首页 RFY 请求 `transport_succeeded`：

- `items=24`、`credentialsChanged=false`；
- 游标解码含 `vespa_content_group: 2` → `genericFallback=true`；
- 整批 24 项作品被 `discardReason=generic_fallback` 全部丢弃；
- 随后 13:38:44 的 bareProbe 再次 `classification=signedIn`（`healthy -> healthy`）。

用户侧表现为：首页推荐空白，出现"登录恢复"式提示与登录按钮——把推荐能力
降级误报成了登录问题。同一日志内身份与 Cookie 均健康，证明丢弃判定不是身份
失败。

## 根因分析

1. REG-009 记录过匿名 Cookie 也能得到 HTTP 200 + 通用内容（伴随 group 2 游标），
   据此建立了"group 2 ⇒ 通用回退 ⇒ 整批拒绝"的保护。
2. REG-017 自己已承认 group 2 是"历史观察得到的疑似回退信号，并非已验证的
   完整协议定义"。2026-10-13 的日志证明：**服务器确认已登录的健康会话同样会
   返回 group 2 游标**。因此 group 2 不能单独证明"响应是匿名通用内容"，
   其完整语义 UNVERIFIED（无法在本机网络环境验证：匿名基线请求被
   CloudFront 403 阻断，见 AGENTS.md 外部协议核实规则）。
3. 无论 group 2 语义如何，把整批数据丢弃并展示登录恢复 UI，都会让一个身份
   健康的会话在首页表现为"未登录 + 无内容"——把推荐能力问题错误呈现为
   登录问题，且首页完全不可用。

## 修复（P0-B，2026-10-13）

保留 group 2 作为**疑似降级**信号与状态标记，改变其后果：

- **展示而非丢弃**：疑似通用批次照常进入信息流（`artworkStore` 亦可用），
  首页不再空白。
- **清晰标识**：首页推荐 tab 顶部显示降级横幅（账号已登录、内容未确认
  个性化、可重试、可关闭），横幅直接附着于它所限定的内容。全局通知宿主
  （AppNoticeHost）不再对降级弹通知，避免双重提示与登录 CTA 误报。
- **不冒充、不缓存**：降级批次永不写入个性化冷启动缓存
  （`_persistPersonalizedFeedCache` 仅在 `!degraded` 时执行）；恢复阻断式
  登录 UI 仅在权威 `needsLogin` 判定下出现。
- **状态与恢复**：`personalizedSessionStatus` 仍记录 degraded 事件；显式
  登录（新代际）或取得无 group 2 信号的成功响应可解除；`recheckAfterWebSignal`
  身份复核保留（不提升 generation，不影响降级标记）。
- **结构化脱敏诊断**：`transport_succeeded` 增记 `cursorStructure=`
  （解码后的键名排序列表 + `vespa_content_group` 数值；不含任何游标值），
  为未来真实协议取证积累证据。
- 游标误判保护保留：`vespa_content_group` 字符串 `"2"`、group 1、未知/超长/
  不可解码游标均不触发降级；跨代际的迟到通用结果仍被 `session_superseded`
  拒绝（不可顶替新登录）。

## 未验证事项（UNVERIFIED）

- `vespa_content_group` 的完整语义（是否 2 专属通用回退、是否存在其他组号）。
  当前仅知：匿名通用回退（REG-009 历史样本）与已登录健康会话（2026-10-13
  日志）均出现过 group 2。
- DAKit 私有网页请求使用固定桌面 Chrome UA，与 Android 登录 WebView 的 UA
  不一致；无证据表明该差异导致 group 2，未做改动。

## Regression

- `test/home_refresh_no_probe_test.dart` "suspected generic fallback is
  displayed with a degraded incident, never as confirmed personalized"：
  降级批次展示 + 事件保留 + 无错误态 + 恢复后 forceRefresh 取得 usable 页。
- "a late generic result cannot replace a newer same-account login"：
  跨代际通用结果仍被拒绝。
- `test/personalized_session_status_test.dart` / `personalized_request_policy_test.dart`：
  游标信号与归属策略不变。
