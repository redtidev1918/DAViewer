# REG-026 持久化 Cookie 恢复被双重解析静默禁用

## 症状（2026-10-15 00:35 / 00:54 Android v0.5.20 日志）

冷启动后 OAuth 官方 API 全部 200（`user/whoami`、`browse/deviantsyouwatch` 50
项），但网页会话表现为匿名：

- 实时 Cookie 仅 7 个（`_px`、`_pxvid`、`g_state`、`pxcts`、`td`、`tpc`、
  `userinfo`），缺 `auth`、`auth_secure`；
- 持久化快照曾以 `persist snapshot cookies=9` 保存（含 `auth`/`auth_secure`）；
- 网页 HTTP 验证 200 / anonymous，Headless WebView 两次 `explicit_anonymous`；
- RFY 在发请求前被 `dakit:authentication:web.session.unavailable` 阻断；
- **全程没有任何 `restore candidate` / `restore skipped reason=nothing_missing`
  / `restore verified` 日志**——恢复流程从未到达决策点。

PR #118（`67dfaba`）专门为回答"9 还是 7"加了恢复决策日志；日志缺失本身即证据：
恢复路径在读回持久化快照时就提前返回了。

## 根因

`WebSessionStore.read()` 自 `058edd0`（2026-09-22，"root-cause cookie
persistence and pagination stalls"）起把 `cookies` 字段解码并迁移为
`List<PersistedWebCookie>` 后返回；但 `WebSessionController` 的三个消费方仍在
`read()` 结果上再次调用 `parsePersistedCookies`：

1. `_restoreWebCookies`：`parsePersistedCookies(saved['cookies'])`——
   `PersistedWebCookie.fromJson` 对非 `Map` 项返回 `null`，已解析对象全部被
   丢弃 → 列表恒为空 → `if (cookies.isEmpty) return;` 在任何日志之前静默
   返回。**恢复路径自该提交起完全失效。**
2. `persistedCookies()`：同样的双重解析，恒返回空列表，
   `web_session_status` 的空实时 Cookie 诊断因此拿到 `persistedCount=0`。
3. `ensurePersistentSnapshot`：读回"已持久化"快照恒为空 → 指纹比对恒不相等
   → 每次健康检查都重写快照（去重失效）。

v0.5.14–v0.5.20 全部携带该缺陷（`git merge-base --is-ancestor 058edd0b <tag>` 逐个核实）。

### 为什么 586 项全绿的套件没有发现

`web_session_store_test.dart` 的本地辅助 `read()` 直接 `jsonDecode` 原始
secure-storage 字符串，绕过了 `store.read()` 的解码——存储层测试从未与消费方
组合走通"`store.read()` → 消费"这条路径。被中断会话遗留的
`test/web_session_mutation_race_test.dart` 新测试通过生产 `store.update()` 构造
真实快照（不反向工程 `parsePersistedCookies`），首次组合走通该路径，立即在旧
代码上复现失败：

- 冷启动用例：`persistedCookies()` 期望 9，实际 `[]`；
- 并发恢复用例：恢复死路导致 `setCookie` 从不执行，2 秒超时。

## 修复（2026-10-15）

最小修复：三个消费方直接使用 `read()` 返回的已解析
`List<PersistedWebCookie>`，仅当值不是该类型（契约外）时才回退到
`parsePersistedCookies`。写入路径（`toJson` 序列化）、账号匹配
（`shouldRestoreSavedWebSession`）、过期过滤（`missingSavedWebCookies`）、
登出墓碑与代际隔离逻辑均不变。

同时修正测试桩缺陷：fake CookieManager 重建 `expiresDate` 时未带
`isUtc: true`，导致与 `DateTime.utc(2030)` 比较因时区标志不同而误报。

## 未验证事项（UNVERIFIED）

- **本修复不等于原始事件已解决。** 00:35 的日志显示实时 Cookie 完整 9 个时
  网页验证仍返回 anonymous——Cookie 名称齐全不代表服务端接受凭据。本修复恢复
  的是客户端"平台 Cookie 丢失后从持久化快照重新注入"的能力；服务端是否接受
  注入的凭据仍需真机证据（Android Verified / Original Incident Verified 均
  PENDING）。
- Android 平台 Cookie 存储丢失 `auth`/`auth_secure` 的上游原因（服务端轮换、
  平台存储清除还是 WebView 行为）仍未确证；修复保证可从快照重注入，不解释丢失。
- 修复后需要真机日志确认 `restore candidate` / `restore candidates count=`
  / `restore verified`（或 `nothing_missing`）按预期出现，作为链路复活的
  直接证据。

## Regression

`test/web_session_mutation_race_test.dart`（通过生产 store 构造真实持久化
快照，而非反向工程解析器）：

- "cold-start restores decoded saved authentication cookies with metadata"：
  旧代码失败（`[]` vs 9）；修复后恢复以完整元数据（domain/path/expiry/
  secure/httpOnly）注入 `auth`/`auth_secure`，且重复冷启动不覆盖已轮换的
  实时 Cookie。
- "restoration rejects expired saved auth cookies"：过期快照不注入。
- "restoration rejects a snapshot for another OAuth account"：跨账号快照拒绝。
- "concurrent restores share native writes and logout fences the remainder"：
  旧代码超时失败；修复后并发恢复单飞共享、登出隔离剩余写入并清空持久化。
