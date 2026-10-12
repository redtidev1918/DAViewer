# 14797b3 启动门控与路由免真机代码审计

- 审计对象:提交 `14797b3` "fix(auth): release startup gate and stop unknown-session routing loop"(工作区代码与提交一致,忽略无关 docs 编辑与未跟踪 `clear/`)。
- 审计方式:只读代码审计,全部结论来自亲自读到的代码。未运行真机,未修改任何代码。
- 主文件:`lib/features/splash/splash_screen.dart`、`lib/app/router.dart`;状态来源:`lib/core/auth/web_session_status.dart`(`webSessionReadyProvider` 定义于 :22)、`lib/core/auth/auth_controller.dart`、`lib/core/auth/auth_state.dart`、`lib/core/auth/web_session_controller.dart`。
- 背景对照:v0.5.13 生产故障(冷启动有效登录态卡在「正在恢复登录状态」/个性化推荐不恢复);上一候选 3d62b45 真机 FAIL,疑为 OAuth unknown 时 `/splash → / → /splash` 循环。14797b3 的修复声明:单一 12 秒总截止无条件释放 ready、异常经 finally 释放、超时后 unknown 可达 Home/设置/诊断、超时不登出不清凭据。

---

## 问题 1:总截止时间是否无条件释放 ready?

**结论:OK。** 12 秒总截止 Timer 在 `initState` 同步武装,先于一切 await;正常完成与异常路径都经 `finally` 释放;`_finished` 标志与释放同点置位,无"置位但跳过释放"交错。唯一使 ready 永不释放的前提是 Splash 在 ready 之前被 dispose,而路由守卫(见问题 2)使该前提在路由驱动下不可达,且全库无其他导航代码能把用户带离 `/splash`。

### 证据

截止计时器同步武装,先于任何 await:

- `lib/features/splash/splash_screen.dart:48`
  ```dart
  static const Duration _startupTimeout = Duration(seconds: 12);
  ```
- `lib/features/splash/splash_screen.dart:63-64`
  ```dart
  // Independent of every awaited Future, including a circular restore wait.
  _startupDeadline = Timer(_startupTimeout, () => _finishStartup('deadline'));
  ```

正常完成与异常路径都在 `finally` 释放:

- `lib/features/splash/splash_screen.dart:89-100`
  ```dart
  try {
    _startupStage = 'restore_pending';
    await ref.read(startupRestoreProvider)();
    _startupStage = 'restore_complete';
  } on Object catch (error) {
    AppLogger.instance.warning(...);
  } finally {
    _finishStartup('restore_finished');
  }
  ```
  catch 的是 `Object`(Dart 万物),`web.initialize()`(`splash_screen.dart:33`)抛出的任何错误都会被捕获并落入同一 `finally`。`auth.initialize()` 的错误在 restore 内部先被吞掉(`splash_screen.dart:25-30`),不影响 finally 到达。

释放动作与守卫标志同点置位,无分离:

- `lib/features/splash/splash_screen.dart:103-116`
  ```dart
  void _finishStartup(String reason) {
    if (mounted && !_finished) {
      _finished = true;
      _startupDeadline?.cancel();
      AppLogger.instance.info(...);
      ref.read(webSessionReadyProvider.notifier).state = true;
      unawaited(_checkSession());
    }
  }
  ```
  `_finished = true`(:105)与 `state = true`(:111)之间只有日志与 cancel,没有可跳过释放的分支;两处调用点(deadline Timer、finally)竞争时第一个到达者释放,第二个被 `_finished` 挡住,单次释放。

计时器只有两个取消点,都不产生"取消后永不释放":

- `lib/features/splash/splash_screen.dart:74`(dispose 中 cancel)与 `:106`(`_finishStartup` 内部 cancel,即释放已发生)。

唯一理论死角:Splash 在 ready 前 dispose → Timer 被 cancel(:74)、`_finishStartup` 因 `!mounted` 不执行(:104)→ ready 永不置 true。该前提不可达:

- 路由守卫 `lib/app/router.dart:165-168`:`!ready` 时对 `/splash` 恒返回 `null`(原地停留),路由不会把用户带离 Splash;
- `grep "'/splash'"` 全 lib/ 仅命中 `router.dart`(7 处),Splash 自身代码无任何 `context.go/push` 导航调用,启动期没有任何已挂载组件能导航。

### 解释

设计是"截止时间优先"而非"阶段驱动":截止 Timer 是 `initState` 里的第一个动作,不依赖任何 await 完成;restore 各阶段(auth.initialize / web.initialize,`splash_screen.dart:23,33`)挂多久都只影响 `_startupStage` 日志,不影响 12 秒释放。`_initialize` 中的 restore 即使形成循环等待(测试 'cycle' 模式模拟的正是"restore 等 ready、ready 等 restore"),deadline 仍独立触发。释放后 late restore 继续:`startupRestoreProvider` 用 `operation ??= restore()` 记忆化(`splash_screen.dart:37`),splash 卸载不取消进行中的 restore,二次进入也只是 join 同一 Future。

残留交错(不构成缺陷,见结尾风险节):(1) Android 后台冻结/Doze 可推迟 Timer 回调到解冻后,ready 延迟但不丢失;(2) `_finished` 置位后、`state = true` 前若 `AppLogger.info` 抛错会卡死释放——AppLogger 为本地日志不抛,属理论值。

---

## 问题 2:重定向循环逐状态枚举

**结论:OK。** 修复了 3d62b45 的 `/splash ↔ /` 循环;当前所有状态组合下均无回 Splash 的循环,也无任何"弹回 Splash"的组合在 ready 后成立。注:应用没有 `/login` 路由,登录路由是 `/web-login`(`router.dart:46`);诊断路由是 `/settings/diagnostics`(`router.dart:88`)。

### 证据

路由级守卫(redirect 的第一段):

- `lib/app/router.dart:165-168`
  ```dart
  if (state.matchedLocation == '/splash' &&
      !ref.read(webSessionReadyProvider)) {
    return null;
  }
  ```
  即:**任何 auth 状态下**,`/splash` + `!ready` → 原地停留,`authRedirect` 不会被调用。

策略函数:

- `lib/app/router.dart:232-241`(unknown 分支)
  ```dart
  if (status == AuthStatus.unknown) {
    if (!startupReady) return '/splash';
    if (location == '/splash') return '/';
    // A timed-out restore stays unknown. Keep recovery routes reachable after
    // leaving Splash; redirecting Home back to Splash creates a startup loop.
    return isSignedOutRoute(location) ? null : '/';
  }
  ```
- `lib/app/router.dart:243-245`:`signedIn && location == '/splash'` → `'/'`
- `lib/app/router.dart:249-251`:`signedOut && location == '/splash'` → `'/web-login'`
- `lib/app/router.dart:254-256`:非 signedIn 且非签出可达路由 → `'/'`
- `lib/app/router.dart:263-269`:`isSignedOutRoute` = `/`、`/watch`、`/web-login`、`/history`、`/settings`、`/settings/*`

修复 diff(14797b3 对 router.dart 的改动,旧代码正是循环源):

```diff
-    return startupReady && location == '/splash' ? '/' : '/splash';
+    if (!startupReady) return '/splash';
+    if (location == '/splash') return '/';
+    return isSignedOutRoute(location) ? null : '/';
```
旧代码在 `unknown+ready` 时对 `/` 返回 `/splash`、对 `/splash` 返回 `/`,构成循环;`docs/agent-tasks/session-recovery/STARTUP-REGRESSION.md:10-13` 确认了这一归因。

### 逐组合枚举表

**(a) unknown + ready=true**(`authRedirect` :232-241):

| location | redirect 结果 | 依据 |
| --- | --- | --- |
| `/splash` | `'/'`(去 Home) | :238 |
| `/`(Home) | `null`(停留) | :241 + :264 |
| `/settings`、`/settings/proxy`、`/settings/diagnostics` | `null` | :268-269 |
| `/web-login`、`/watch`、`/history` | `null` | :266-267 |
| `/search`、`/favourites`、`/downloads`、`/watching`、`/notifications`、`/artwork/:id`、`/artist/:username`、`/tag/:tag` | `'/'`(弹到 Home) | :241(不在 isSignedOutRoute 列表) |

**(b) unknown + ready=false**:

| location | 结果 | 依据 |
| --- | --- | --- |
| `/splash` | `null`(守卫停留) | :165-168 |
| 其他一切(含 `/web-login`、`/`) | `'/splash'`(单跳) | :237 |

跳到 `/splash` 后命中守卫(:165-168)原地停留——单跳即稳,无循环。

**(c) signedOut + ready=true**:

| location | 结果 | 依据 |
| --- | --- | --- |
| `/splash` | `'/web-login'` | :249-251 |
| 签出可达路由(`/`、`/watch`、`/web-login`、`/history`、`/settings*`) | `null` | :254-256 不触发 |
| 其余(`/favourites` 等) | `'/'` | :254-256 |

**(d) signedIn + ready=true**:

| location | 结果 | 依据 |
| --- | --- | --- |
| `/splash` | `'/'` | :243-245 |
| 其他全部 | `null` | :254 条件 `status != AuthStatus.signedIn` 不成立 |

**(e) signedIn + ready=false**:

| location | 结果 | 依据 |
| --- | --- | --- |
| `/splash` | `null`(守卫停留) | :165-168 |
| 其他全部 | `null` | signedIn 分支 :254 不触发 |

### 解释

循环不可能重构:redirect 到 `/splash` 的唯一来源是 `unknown + !ready`(:237),而 `/splash` 在 `!ready` 时被守卫按住;一旦 ready 置 true(且永不回落,见问题 4),`:237` 永不再触发,`authRedirect` 没有任何分支指向 `/splash`。(e) 组合中 `signedIn + !ready` 在非 splash 位置返回 `null`,理论上允许 ready=false 的 Home——但不可达:初始 location 是 `/splash`(:37),导航到 `/` 的每条 redirect 路径都要求 ready=true,启动期无其他导航代码。即便到达,Home 也只渲染骨架屏兜底(`lib/features/home/home_screen.dart:233-235`:
```dart
if (!ref.watch(webSessionReadyProvider)) {
  return const SkeletonGrid();
}
```

---

## 问题 3:超时释放后 auth 仍 unknown,四类页面是否可达?

**结论:OK。** Home、设置、诊断、登录全部可达,没有任何把 unknown 弹回 splash 的守卫。

### 证据

ready=true 后,unknown 分支走 `lib/app/router.dart:241`:

```dart
return isSignedOutRoute(location) ? null : '/';
```

`isSignedOutRoute`(`router.dart:263-269`):

```dart
bool isSignedOutRoute(String location) =>
    location == '/' ||
    location == '/watch' ||
    location == '/web-login' ||
    location == '/history' ||
    location == '/settings' ||
    location.startsWith('/settings/');
```

- Home `/` → `null`(:264)✓
- 设置 `/settings` → `null`(:268)✓
- 诊断 `/settings/diagnostics` → `startsWith('/settings/')` → `null`(:269)✓(诊断路由注册为 `/settings` 的子路由,`router.dart:87-91`)
- 登录 `/web-login` → `null`(:266)✓

指向 `/splash` 的唯一条件是 `!startupReady`(:237),超时释放后 ready 恒为 true(见问题 4 证据:全库唯一写点置 true,无回落写点),该条件永不再成立。

测试锁定:`test/auth_routing_test.dart:22-41`('unknown auth after deadline never redirects recovery routes to splash')对 `/`、`/settings`、`/settings/diagnostics`、`/web-login` 逐一断言 `isNull`,并断言 `/favourites` → `'/'`。

### 解释

超时后用户处于「unknown + ready」:身份未定但 UI 已放行。行为与 signedOut 的公共路由策略一致(:253-256 注释),区别仅在非恢复路由弹到 Home 而非登录页。用户在 Home 的恢复入口(登录按钮 `context.push('/web-login')`,`home_screen.dart:271`)与设置/诊断都可用,这正是故障场景要求的"卡在恢复页之外仍有自救途径"。

---

## 问题 4:用户到达 Home(ready)后,还有什么可能把用户推回 Splash?

**结论:OK。** ready 置 true 后不存在任何非自愿回 Splash 的路径;回到 Splash 只可能是新进程冷启动。用户主动登出落在设置页或公共 Home,不经过 Splash。

### 证据

路由重算的触发面(redirect 只在这两个 listen 变化时重算):

- `lib/app/router.dart:34-35`
  ```dart
  final authRevision = ValueNotifier<int>(0);
  ref.listen(webSessionReadyProvider, (_, _) => authRevision.value++);
  ```
- `lib/app/router.dart:183`
  ```dart
  ref.listen(authControllerProvider, (_, _) => authRevision.value++);
  ```

`webSessionReadyProvider` 永不回落 false——全库唯一写点:

- `lib/features/splash/splash_screen.dart:111`:`ref.read(webSessionReadyProvider.notifier).state = true;`(置 true)
- 定义 `lib/core/auth/web_session_status.dart:22`:`StateProvider<bool>((ref) => false)`(仅初始值)
- `grep webSessionReadyProvider` 全库结果:router 读 4 处、splash 写 1 处、home watch 1 处、测试 override 若干——**无任何 `state = false` 回写**。

会话状态迁移不触发路由:web 会话(`webSessionControllerProvider`)与健康判定(`webSessionStatusProvider`)不在 router 的 listen 列表(:35、:183 只监听 `webSessionReadyProvider` 与 `authControllerProvider`),`unknown → loggedOut`、`anonymous → stale` 等迁移不 bump `authRevision`,redirect 不重算,更无守卫检查会话健康度。

auth 状态后到迁移只可能落在非 Splash:

- 挂起的 restore 稍后完成:`AuthController.initialize` 要么 `signedIn`(如 `lib/core/auth/auth_controller.dart:103,147,165,189`——含超时/网络失败时的"保留会话")要么 `signedOut`(:195),二者在 Home `/` 的 redirect 均为 `null`(:254-256 对 signedIn 不触发、对 signedOut 因 isSignedOutRoute('/') 不触发);OAuth 失效流 `_handleSessionInvalidation` 也只置 `signedOut`(`auth_controller.dart:199-208`)。
- 用户主动登出:`lib/features/settings/settings_screen.dart:156-166` 调 `logout()` 后不导航,只弹 SnackBar;`AuthController.logout` 第一时间置 `signedOut`(`auth_controller.dart:355-356`:
  ```dart
  _authEpoch += 1;
  state = const AuthState(status: AuthStatus.signedOut);
  ```
  )→ refreshListenable 重算当前页:在 `/settings` → `null` 留在设置;在 `/favourites` 等账户路由 → `'/'`(:254-256)。都不经过 Splash。
- 登录页完成后的 `context.go('/')` 是用户主动流程(`lib/features/web_login/web_login_screen.dart:350-359`,含 canPop=false 时的兜底)。

回 Splash 的唯一路径:进程重启后 `initialLocation: '/splash'`(`router.dart:37`)。ready=true 后 `/splash` 本身不可达:(a)/(c)/(d) 组合下 `/splash` 分别被重定向到 `/`、`/web-login`、`/`。

### 解释

关键不变量是「ready 单调」:它只在 Splash 的 `_finishStartup` 置 true 一次,没有复位代码,因此 `router.dart:237` 的 `!startupReady` 分支在进程生命周期内只在前 12 秒有效。refreshListenable 虽在每次 auth 状态变化时重算 redirect,但重算结果在 ready 后的任何状态×当前 Home 位置下都不是 `/splash`。真机故障里"用户被弹回 Splash"的现象在当前代码里没有对应路径。

---

## 问题 5:14797b3 新增测试是否真实覆盖四项关键行为?

**结论:OK(覆盖属实),存在三个小缺口(P2,不推翻结论)。** 14797b3 新增 `test/startup_gate_test.dart`(全新 137 行)并扩充 `test/auth_routing_test.dart`(+21 行)(`git show --stat 14797b3`);另含 web_login 系列与 `app_logger_write_race_test.dart`(属登录流与日志磁盘故障,与启动门控无直接关系)。

### 证据与逐项覆盖

**测试文件结构**:`test/startup_gate_test.dart:19-25` 用同一测试模板跑 5 个 mode('pending'、'cycle'、'error'、'success'、'actual_router'),测试名 `startup $mode releases routing without changing unknown identity`。每个 mode 里 `startupRestoreProvider.overrideWithValue`(`startup_gate_test.dart:43-57`)注入合成 restore。

1. **截止释放(restore 永不完成)** — 覆盖 ✓
   - `startup_gate_test.dart:48-50`:'pending' mode `await pending.future`(永不完成);`:107` 断言 12 秒前 ready 仍 false;`:108` `await tester.pump(const Duration(seconds: 12))` 推进真实 `Timer`;`:113` 断言路径到 `'/'`;`:119` 断言 `readyChanges == [true]`(恰一次)。
   - 测试名:`startup pending releases routing without changing unknown identity`。

2. **异常释放** — 覆盖 ✓
   - `startup_gate_test.dart:45-47`:'error' mode 直接 `throw StateError('synthetic restore failure')`;错误沿 `splash_screen.dart:91-100` 的 catch/finally 释放;`:113` 断言仍到 `'/'`。
   - 测试名:`startup error releases routing without changing unknown identity`。

3. **超时后 unknown 到达 Home(并保持 unknown)** — 覆盖 ✓
   - `startup_gate_test.dart:115-118`:断言 `authControllerProvider.status == AuthStatus.unknown`(门控释放不伪造身份);
   - `:121-128`:`router.go('/settings/diagnostics')` 后断言路径稳定在诊断页、`findsNothing` 无 Splash 残留;
   - `:32` 的 `ValueNotifier revision` + `:73-77` 自建 redirect 读 `startupReady: container.read(webSessionReadyProvider)`,把 ready 真实接进路由重算;
   - 'actual_router' mode(`:68-69`)直接用生产 `container.read(routerProvider)`,含守卫(:165-168)、refreshListenable(:35,183)与日志,是最接近真机的合成复现。
   - 纯函数侧:`test/auth_routing_test.dart:22-41`('unknown auth after deadline never redirects recovery routes to splash')锁死四条恢复路由。
   - 测试名:`startup actual_router releases routing without changing unknown identity`、`startup cycle ...`、`auth_routing_test` 上述用例。

4. **无重定向循环** — 覆盖 ✓
   - 旧循环(unknown+ready:`/splash→'/'` 且 `'/'→'/splash'`)在 'actual_router' 下必然表现为测试失败:该测试断言最终路径恰为 `'/'` 且无 Splash 挂载(:113-114),随后导航诊断页不回弹(:124-128)。'cycle' mode(`:51-56`,restore 内 `while (!ready)` 模拟循环等待)证明门控不依赖 restore 完成,即 3d62b45 怀疑的"阶段互相等待"不再阻塞释放。
   - 测试名:`startup cycle releases routing without changing unknown identity`。

单飞/晚完成不二次释放:`:120,132` 断言 `starts == 1` 与 `readyChanges == [true]`——restore 只启动一次(对应 `splash_screen.dart:37` 的 `operation ??= restore()`),晚完成的 pending 在 `:129` `pending.complete()` 后不再次置 ready。

### 真实缺口(P2)

1. **门控"保持"半程未锁**:没有任何测试断言 12 秒内导航到 `/`(或 `/settings`)会被拦到 `/splash` 并停住——即问题 2(b) 的守卫组合(:165-168 + :237)在真实 router 下未被测试钉住;`auth_routing_test.dart:11` 只测了纯函数 `authRedirect(unknown, '/splash') → '/splash'` 一格。若有人误删守卫,:165-168 缺失后 `/splash+!ready` 会走纯函数自指 `/splash`,行为可能回归而现有测试不红。
2. **真实 auth.initialize 挂起未端到端**:'pending'/'cycle' 挂起的是合成 Future。真实链路中 `validTokens(...).timeout(15s)`(`auth_controller.dart:140`)内部超时**大于** 12 秒总预算,即超时释放必然先于 auth 内部超时发生、随后走 `auth_controller.dart:176-191` 的"保留 signedIn"。该 12s→15s 交错的端到端行为(ready 先放行、auth 稍后迁移 signedIn、Home 不弹回)只有机制等价的合成覆盖,无启动级回归。
3. **signedIn+!ready 非 splash 位置返回 null 的策略未测**(问题 2(e)):实际不可达,但策略未锁,若未来加入启动期导航代码会静默变成"骨架屏 Home"。

以上缺口均为测试加固项,不构成当前行为缺陷。

---

## 总体结论

**14797b3 的四条修复声明在代码层面全部成立,五题结论均为 OK,未发现 DEFECT。**

1. 12 秒总截止无条件释放 ready:成立(Timer 先于一切 await 武装,`splash_screen.dart:63-64`;异常经 `finally` 释放,`splash_screen.dart:98-100`;无交错可跳过释放)。
2. `/splash ↔ /` 循环已消除:成立(旧循环源 `router.dart` 的 `return startupReady && location == '/splash' ? '/' : '/splash'` 已改为 `isSignedOutRoute(location) ? null : '/'`,`router.dart:237-241`;指向 `/splash` 的唯一条件 `!startupReady` 与 `/splash` 守卫互斥,`router.dart:165-168`)。
3. 超时后 unknown 下 Home/设置/诊断/登录可达:成立(`router.dart:241` + `:263-269`;测试 `auth_routing_test.dart:22-41` 锁定)。
4. 到 Home 后无非自愿回 Splash:成立(ready 单调无回落,全库唯一写点 `splash_screen.dart:111`;会话健康迁移不接路由;登出走 `signedOut` 落在设置/公共 Home,`settings_screen.dart:156-166`、`auth_controller.dart:355-356`)。
5. 测试覆盖属实:四项关键行为(截止释放、异常释放、超时后 unknown 到 Home、无循环)各有具体测试且断言到位;存在三个 P2 级测试缺口。

## 发现缺陷列表

无 DEFECT。以下是观察项与最小修复建议:

| 级别 | 条目 | 位置 | 最小修复建议 |
| --- | --- | --- | --- |
| P2(测试缺口) | 门控"保持"半程未锁:12 秒内尝试导航离开 `/splash` 应被拦回并停住,现有测试只断言 ready=false,未断言路由停在 `/splash` | `test/startup_gate_test.dart`(缺)、守卫在 `lib/app/router.dart:165-168` | 在 'pending' mode 12 秒断言处加一条:`router.go('/settings/diagnostics')` 后断言 `uri.path == '/splash'` |
| P2(测试缺口) | 12s(总预算)< 15s(`validTokens` 内部超时)的交错只有合成覆盖,真实 auth 挂起→超时释放→auth 稍后迁移 signedIn 的端到端无回归 | `lib/core/auth/auth_controller.dart:140` vs `splash_screen.dart:48` | 增加一条用假 oauth(挂起的 `validTokens`)跑真 router 的 widget 测试,断言 12s 放行后 15s auth 迁移不把用户弹离 Home |
| P2(测试缺口) | `signedIn+!ready` 在非 splash 位置返回 `null` 的策略未锁(当前不可达) | `lib/app/router.dart:243-245,254-256` | 在 `auth_routing_test.dart` 补一行 `expect(authRedirect(AuthStatus.signedIn, '/', startupReady: false), isNull)` 把策略钉住 |
| P2(观察,无需改码) | 显式登出后冷启动,`AuthController.initialize` 记录到登出证据即早退,**status 永久保持 unknown**(`auth_controller.dart:114-132`),此后 `/search`、`/favourites`、`/downloads` 等被 `router.dart:241` 弹到 `/`——与 signedOut 策略一致属设计选择,但意味着登出用户的冷启动常驻 unknown+ready 态 | `lib/core/auth/auth_controller.dart:130-131` | 若希望登出用户显式进入 signedOut 语义,可在早退前置 `signedOut`;不改则至少在 STATUS 文档记录该状态语义(非 14797b3 引入,auth_controller.dart 不在提交文件列表) |

## 真机上需要观察的残留风险

1. **后台冻结推迟释放**(RISK,低):12 秒 Timer 在 Android 冻结 cached 进程期间不回调,解冻后才释放 ready。若用户冷启动后立刻切走再回来,可能仍见 Splash 直到解冻。日志特征:`splash created deadlineMs=12000` 与 `ready=true reason=deadline` 之间的墙钟差远大于 12 秒。
2. **超时释放后恢复链路的真机到达率**(RISK,中——即原故障的验收核心):12s 释放进 Home 后,后台仍需 `validTokens` 完成(≤15s,超时保留 signedIn,`auth_controller.dart:140,176-191`)→ `accountLoad`(whoami)→ `web_session_controller` 的 cookie 再注入(`web_session_controller.dart:217-303`,内部 await `accountLoad`)→ `webSessionStatusProvider.check()` 给出健康判定,个性化推荐才恢复。任何一环在真机 Keychain/WebView 环境挂死,则卡点从 Splash 转移为"Home 可进但推荐一直不恢复"——本次审计只能证明门控与路由不再挡路,不能证明恢复链真机必达。观察日志:`stage=oauth_restore`、`restore event=await_account/account_settled`、`web session state: ... -> healthy`。
3. **unknown 持久态下的导航受限**(RISK,低):超时释放后 auth 若长期停在 unknown(restore 完成前网络死、或上文显式登出早退),深链与 `/search`、`/favourites`、`/downloads`、`/watching`、`/notifications`、`/artwork/*` 均弹回 `/`(设计如此,`router.dart:241`);真机验收时不应误判为循环。
4. **旧候选残留归因未关闭**(RISK,信息性):3d62b45 真机 FAIL 的最终物理原因(STARTUP-REGRESSION.md:15-19 所述 native 未完成 Future)仍无真机日志归因;14797b3 用"无条件截止"绕过而非解释它。若真机上 12s 释放本身被冻结推迟(风险 1),现象可能复现,需用新增的 `route=... target=... ready=... oauth=...` 路由日志(`router.dart:175-178`)直接判定。
