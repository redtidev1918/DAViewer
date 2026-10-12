# 14797b3 日志系统启动阻塞审计(AppLogger / LogArchive)

- 审计对象:工作区代码 = 提交 14797b3(忽略 docs/ 与 clear/)。免真机、只读代码审计;除本报告外未修改任何文件,未执行测试(避免产生构建产物)。
- 审计问题:上一轮修复(观察 `IOSink.done` 错误、串行化幂等 close、排空排队写入、close 失败捕获并在 finally 清单例)是否完整;日志系统是否仍可能阻塞 Android 启动(候选 3d62b45 真机卡在「正在恢复登录状态」)。
- 方法:通读 `lib/core/diagnostics/app_logger.dart`、`log_archive.dart`、`log_redactor.dart`、`crash_marker.dart`,并沿 `lib/main.dart` → `lib/features/splash/` → `lib/core/auth/`(auth_controller、web_session_controller、web_session_store、web_session_status、webview_oauth_bridge、web_session_refresher、web_session_verifier)→ `lib/core/runtime/app_runtime.dart` → `lib/app/router.dart` 逐个核对日志调用点;`test/` 下检索 logger / log_archive 相关测试。全部结论出自下列 file:line 引用的代码。

---

## 1. 启动关键路径:同步文件 IO / 无界等待

**结论:RISK。日志系统没有任何同步文件 IO(全部走 dart:io 异步 API),`runApp` 之后的日志调用全部是 fire-and-forget,ready 释放有 12 秒兜底定时器保证;但 `main()` 里 `await AppLogger.initialize()` 这条链上有 3 个无超时的真实 IO await(平台目录、建目录、首次 flush),磁盘挂起时会在 `runApp` 之前无限期拖住启动。另:日志没有任何轮转/清理,文件数无限增长(P2)。**

### 证据

**(a) 初始化被 await,且链上无任何超时。**

`lib/main.dart:57`:

```dart
final logger = await AppLogger.initialize();
```

`lib/core/diagnostics/app_logger.dart:50-67`:

```dart
static Future<AppLogger> initialize({String? fileName}) async {
  if (_instance case final existing?) return existing;
  final support = await getApplicationSupportDirectory();   // :52 平台通道,无超时
  final logsDir = Directory('${support.path}${Platform.pathSeparator}logs');
  await logsDir.create(recursive: true);                    // :54 真实文件系统,无超时
  ...
  final file = File('${logsDir.path}${Platform.pathSeparator}$name');
  final sink = file.openWrite(mode: FileMode.append);       // :59 惰性异步打开,不抛同步异常
  _instance = logger;
  logger.info('app', 'logger initialized: $name');          // :62
  ...
  await logger.flush();                                     // :67 等待真实 writeln+flush 落盘,无超时
```

这是启动路径上唯一一处等待真实磁盘写的地方。对比同在 `main()` 里的 `AppRuntime.create()`,那里三处 await 全部有超时(`lib/core/runtime/app_runtime.dart:57-60` proxy 10s、`:77-80` webview 12s、`:90-93` transfers 12s),唯独日志初始化没有。若磁盘在启动窗口挂起(f2fs 停滞、存储满、加密卷未就绪),`main()` 会停在 `runApp` 之前 → 应用停留在原生启动画面,不出现任何 Flutter UI。这是无界等待,但触发条件是病态磁盘,常规设备毫秒级完成,故定为 RISK(P1 级风险),不是当前故障的直接成因(见「真机观察点」)。

**(b) 慢磁盘能否拖住启动:** 能,但只拖 `runApp` 之前这一段(上条)。`runApp` 之后:

- 所有日志调用都是同步入队、不 await:`app_logger.dart:105-122`(`_write` 只做格式化 + `debugPrint` + `_enqueueLine`)、`app_logger.dart:127-142`(DAKit `DiagnosticSink.add` 同样)。
- 写与 flush 共享一个串行队列,`app_logger.dart:163-171`:

```dart
void _enqueueLine(String line) {
  if (_disposed) return;
  _flushTail = _flushTail
      .then((_) async {
        _file.writeln(line);
        await _file.flush();
      })
      .catchError(_reportFileFailure);
}
```

每行一次 `writeln`+`flush`(逐行 flush,IO 偏重但全在后台);队列是单链 future,严格串行。慢磁盘只会让队列越积越长(内存中挂起待写行,受日志量约束),不会阻塞调用方或 UI 线程。

- splash 的 ready 释放不依赖任何被 await 的 Future:`lib/features/splash/splash_screen.dart:48,64` 有独立的 12 秒兜底定时器:

```dart
static const Duration _startupTimeout = Duration(seconds: 12);   // :48
_startupDeadline = Timer(_startupTimeout, () => _finishStartup('deadline'));  // :64
```

`_finishStartup`(`:103-116`)置 `webSessionReadyProvider.state = true`(`:111`)。即使 restore(`:91` `await ref.read(startupRestoreProvider)()`)永久挂起,12 秒后 ready 也会释放。

**(c) 各操作执行方式逐项:**

| 操作 | 方式 | 位置 |
| --- | --- | --- |
| 打开 | `openWrite(mode: append)` 惰性异步;失败不抛同步异常,经 `done`/首个 flush 异步显现 | app_logger.dart:59;错误观察 :26、:170 |
| 写入 | 同步入队 `_flushTail`,后台串行执行 | app_logger.dart:163-171 |
| flush | 每行一次(168);`flush()` 仅返回当前队尾,是 barrier 不是新动作 | app_logger.dart:180 |
| close | `dispose()` → `_close()`:置 `_disposed`、`await flush()` 排空、`await _file.close()`、异常捕获、finally 清单例 | app_logger.dart:182-194;生产代码无任何调用点(仅测试调用) |
| 轮转 | **不存在**。每次启动新建时间戳文件,旧文件永不删除;`logsDirectory` 注释写 "rotated log files" 与实现不符 | app_logger.dart:55-57、:71 |

**(d) 启动路径调用点逐个核对**(全部为 fire-and-forget,无一阻塞):

- `lib/main.dart:57-59`:`await initialize()`(见上)+ `installGlobalErrorHandlers`(同步装 handler,不 IO)+ `logger.info('app', 'DAViewer starting')`(入队)。
- `lib/main.dart:61`:`await CrashMarker.consume()` — 相邻诊断链:`lib/core/diagnostics/crash_marker.dart:31-42` 全量 try/catch、失败返回 `false`,不崩溃;但 `exists()`/`delete()` 同样无超时(与 (a) 同类的病态磁盘风险,量级更小)。
- `lib/features/splash/splash_screen.dart:21,24,26,32,34,65,94,107,122,162`:全部 `AppLogger.instance.info/warning`,入队即返回。
- `lib/core/auth/auth_controller.dart:82`(`AppLogger get _log => AppLogger.instance`)及其 `:100,116,123,141,155,175,180` 等:同上;其网络恢复步骤自带 15 秒超时(`:138-140` `validTokens(...).timeout(const Duration(seconds: 15))`)。
- `lib/core/auth/web_session_controller.dart:151,156,163,224,236,241,282` 等:同上;cookie 恢复等待 `accountLoad`(`:240`)由 splash 12 秒兜底覆盖。
- `lib/core/auth/web_session_store.dart:47,141,148,161,166`:持久化失败仅记 warning 并按调用方语义 rethrow,不影响日志队列。
- `lib/core/runtime/app_runtime.dart:54,62,64,111,115`:`AppRuntime.create()` 在 `initialize()` 完成后使用 `AppLogger.instance`(main.dart:57 先于 :63),拿到的是真实实例。
- `lib/app/router.dart:175`:redirect 里 `AppLogger.instance.info(...)` — 每次 redirect 入队一次,不阻塞导航。
- 其余调用点(`lib/features/home/`、`lib/features/web_login/`、`lib/shared/widgets/artwork_feed_grid.dart:124`、`lib/core/auth/web_session_status.dart`、`webview_oauth_bridge.dart`、`web_session_refresher.dart:99`、`web_session_verifier.dart`)均在 ready 释放之后的 UI/网络路径,同样 fire-and-forget。

### 解释

日志系统对启动的阻塞面收敛为一点:`main.dart:57` 的 `await AppLogger.initialize()`,其中含 3 个无超时 IO await。该点位于 `runApp` 之前,任何挂起表现为「原生启动画面不动」而非「正在恢复登录状态」;`runApp` 之后日志全部异步入队,且 ready 有 12 秒兜底,慢磁盘只会丢/积压日志,不会拖住 UI。3d62b45 真机卡在 Flutter splash(splash_screen.dart:194 `s.splashRestoringSession`),说明当时 `main()` 已走完、日志初始化已返回——该症状不再能由当前日志代码的挂起直接造成(除非新一轮卡在原生画面,见观察点)。无轮转导致 `files/logs/` 下 `daviewer-*.log` 无限累积,是磁盘慢性风险(P2),不是启动阻塞。

---

## 2. flush/close 失败捕获、单例生命周期、幂等性

**结论:上一轮声称的修复全部落实且经测试覆盖——`IOSink.done` 错误在构造器即被观察;写+flush 共队列且队尾永不以错误完成;close 异常被捕获、finally 清单例;dispose 幂等;close 与写的并发语义明确。但发现一个 P1 缺口:`initialize()` 前两步(`getApplicationSupportDirectory`/`logsDir.create`)的异常未被捕获,会直接冒泡炸掉 `main()`。**

### 证据(修复落实部分)

- **done 错误流被观察**,`app_logger.dart:23-27`:

```dart
AppLogger._(this._file, this._directory) {
  // File-open/stream errors also complete done with an error, independently
  // of flush. Observe it immediately so diagnostics never add an uncaught error.
  unawaited(_file.done.then<void>((_) {}).catchError(_reportFileFailure));
}
```

- **写队列错误不逃逸**:`app_logger.dart:170` `.catchError(_reportFileFailure)` 使 `_flushTail` 永远正常完成,`flush()`(`:180`)不可能向调用方抛错。
- **close 串行排空 + 捕获 + finally 清单例**,`app_logger.dart:184-194`:

```dart
Future<void> _close() async {
  _disposed = true;
  try {
    await flush();          // 排空此前排队的全部写入
    await _file.close();
  } on Object catch (error) {
    _reportFileFailure(error);
  } finally {
    if (identical(_instance, this)) _instance = null;
  }
}
```

- **dispose 幂等**:`app_logger.dart:182` `Future<void> dispose() => _disposeFuture ??= _close();` — 连续两次 close 返回同一 future,`_close` 不重入。
- **close 与写并发**:`_close()` 在 `dispose()` 被调用的同一微任务内同步置 `_disposed = true`(`:185`),此后 `_enqueueLine` 直接丢弃(`:164-165`);此前已入队的写由 `:187` `await flush()` 排空。单线程事件循环下不存在「close 进行中但守卫未生效」的窗口。
- **失败后可恢复**:dispose 后 `initialize()` 建新实例新文件(测试 `test/app_logger_write_race_test.dart:56-58` 验证)。

### 证据(P1 缺口)

`app_logger.dart:52-54` 的 `await getApplicationSupportDirectory()` 与 `await logsDir.create(recursive: true)` 没有任何 try/catch;若抛出(平台通道异常、磁盘满/权限/存储损坏的 `FileSystemException`),异常穿过 `initialize()` 冒泡到 `lib/main.dart:57` 的 await,`main()` 在 `runApp` 之前崩溃——整进程无 UI 直接退出,且此时连日志文件都还没有。`_instance` 也尚未赋值(`:61` 在其后),没有任何降级路径。触发条件罕见,但后果是「完全无法启动」,与前一轮修复「日志失败不得拖垮启动」的目标直接矛盾,故定 **DEFECT(P1)**。

### 证据(两点备注)

- 打开失败的坏单例(如目录当文件)会被 `:51` `if (_instance case final existing?) return existing;` 在进程内永久保留:写入全部转入 `catchError → debugPrint`,文件日志整个会话丢失,只有控制台输出。生产代码没有任何 `AppLogger.dispose()` 调用点(全库检索,仅测试调用),因此「finally 清单例、失败后可恢复」实际上只对显式 dispose 的路径生效(P2,见缺陷列表 D3)。
- dispose 之后 `AppLogger.instance` 回落到 NullSink 后备(`:33-37`),`logsDirectory` 会变成 `Directory.systemTemp.path`(`:36`)——生产无 dispose 调用点,当前仅测试可达,列为备注不单列缺陷。

### 解释

五项声称的修复都能在代码里逐一指认,且有针对性测试(见第 5 节)。剩余缺口集中在「打开之前的两步」:前一轮修的是 `openWrite` 异步失败,这次审计确认 `openWrite` 之前还有两个同步于 `initialize` 的 await 完全裸奔。

---

## 3. 初始化失败后的静默降级

**结论:OK(打开失败场景)。文件打开/写入失败后,后续日志调用不会崩溃也不会卡住:每行仍 `debugPrint` 到控制台,文件写入静默转入错误报告;`initialize` 之前的 `AppLogger.instance` 访问也有 NullSink 兜底。唯一例外是第 2 题的 P1:path_provider/建目录异常会让进程在产生任何日志调用之前就死掉。**

### 证据

- **打开失败不抛、不卡**:`openWrite`(`app_logger.dart:59`)惰性打开,失败经 `done`(`:26`)或首个 flush(`:170`)异步显现并被 `catchError` 吞掉;`initialize` 里的 `await logger.flush()`(`:67`)因此永不抛错,`initialize` 正常返回一个「文件已死」的 logger。
- **后续调用安全**:每次 `_write` 先 `debugPrint(line)`(`:119`)——即使文件 sink 全坏,日志仍到控制台/logcat;`_enqueueLine` 的 `.catchError`(`:170`)保证任何写入异常不逃逸到调用方(OAuth 回调、WebView 事件等被诊断路径不会被日志炸掉)。失败只打一行 `'[logger] file write unavailable: ${error.runtimeType}'`(`:173-176`,刻意不含异常文本以免泄露路径)。
- **初始化前访问安全**:`app_logger.dart:33-37`,`instance` getter 返回 NullSink 后备实例,写入全被丢弃(`:198-234`),不崩溃。
- 全局错误处理器(`:239-258`)本身只调用 `logger.error`(入队)+ `unawaited(CrashMarker.record())`(`crash_marker.dart:22-29` 全量捕获),不会造成二次崩溃。

### 解释

「坏 sink + 好单例」的组合下,系统是静默降级到控制台日志,符合修复目标。降级的代价是整个会话没有文件日志(D3),以及 P1 场景(初始化两步直接抛)没有任何降级。

---

## 4. log_archive 导出路径

**结论:OK(含两点 P2 风险)。导出前先 `await AppLogger.instance.flush()` 排空队列,再读文件;读取有明确上限(20 会话 × 512 KiB,带可见截断标记);脱敏在导出时执行且携带 accountNames。风险:全链路(flush、目录列举、逐文件读、系统分享)没有任何超时,磁盘挂起时表现为导出按钮无响应/日志页永久转圈,但不冻结 UI 线程。**

### 证据

- **导出等待排队写入**:`lib/features/diagnostics/diagnostics_screen.dart:77-84`:

```dart
await AppLogger.instance.flush();
final text = await LogArchive.readRecent(
  Directory(AppLogger.instance.logsDirectory),
  accountNames: [
    ref.read(authControllerProvider).account?.username ?? '',
    ref.read(webSessionControllerProvider).username,
  ],
);
```

日志页刷新同样先 flush(`:42`)。注意 `LogArchive.readRecent` 自身不 flush(`lib/core/diagnostics/log_archive.dart:9-49` 直接 `file.open()`/`read()`),契约靠调用方维护——当前唯一调用方守约;若新增调用方忘记先 flush,会导出到不含最新排队的陈旧尾巴(测试缺口,见第 5 节)。
- **上限与截断**:`log_archive.dart:15-21` 列举 `.log` 按路径逆序取最近 20 个,再正序拼接;`:30-37` 单文件超过 512 KiB 时定位到末尾读最后 512 KiB,并写 `[truncated: last N bytes of M]` 标记。
- **脱敏在导出时做**:`log_archive.dart:39-42` — `LogRedactor.redactAll(utf8.decode(bytes, allowMalformed: true), accountNames: accountNames)`,即导出时二次脱敏(写入时已按模式脱敏一次,`app_logger.dart:157`,但写入时不带 accountNames;`log_redactor.dart:56-64` 的账号名替换只在导出/报告路径生效)。问题报告路径同样再脱敏一次(`diagnostics_screen.dart:120`)。
- **错误处理**:`_exportLogs` 整体 `on Object` 兜底并弹 SnackBar(`:102-111`);`_loadLog` 同样(`:66-71`)。
- **无超时(风险)**:`flush`、`directory.list()`、`handle.read()`(`log_archive.dart:37`)、`target.readAsLines()`(`diagnostics_screen.dart:58`)、`SharePlus.instance.share`(`:87`)均无 `.timeout()`。挂起磁盘下 `_loadLog` 的 `_loading` 转圈(`:39`)永不结束、分享面板永不弹出;所有步骤均为异步,UI 线程不被冻结。
- **不改源文件**:导出只读(`readRecent` 仅 `open/read/setPosition/close`),分享用 `XFile.fromData` 内存数据(`diagnostics_screen.dart:90-95`),符合注释声明。

### 解释

导出路径结构上是「排空队列 → 有界读取 → 导出时脱敏 → 系统分享」,方向正确。缺陷是无超时:它继承的是与第 1 题 (a) 同类的病态磁盘风险,但场景是用户主动点击、UI 不冻结,故 P2。

---

## 5. 测试覆盖(test/ 下 logger / log_archive 回归测试)

**结论:OK。针对前一轮修复有 3 个真实文件系统上的回归测试,导出有 2 个;覆盖了打开失败、双 close、close 与写并发、flush 期间写入、导出边界与脱敏。缺口:initialize 两步异常(第 2 题 P1)无测试;坏单例进程内不恢复(D3)无测试;导出方「先 flush 再 readRecent」的契约无测试;会话中途磁盘满(打开成功后写失败)无独立测试。本审计只读未执行,以下为对测试代码本身的核对。**

### 已有覆盖

`test/app_logger_write_race_test.dart`(真实临时目录 + mock path_provider,真实 IOSink):

| 测试 | 覆盖点 |
| --- | --- |
| `failed file open does not poison callbacks, flush or disposal`(:10-35) | 用目录冒充文件让异步打开失败(:20-21 `Directory('.../unwritable.log').create(recursive: true)`);断言失败后 info/flush/dispose 全部不抛、`AppLogger.isInitialized` 为 false(:33,即 finally 清单例) |
| `concurrent disposal drains writes and allows a new logger`(:37-59) | `Future.wait([dispose(), dispose()])` 双 close 幂等(:49);close 前排队的 `queued before close` 落盘、close 后写入被丢弃(:54-55);随后 `initialize` 得到新实例(:56-58) |
| `logging during an in-flight flush never aborts a login callback`(:61-97) | flush 进行中连续 100 条写入不抛、回调完成、全部 100 条 + 之前的行都在文件里(:83-95) |

`test/log_archive_test.dart`:

| 测试 | 覆盖点 |
| --- | --- |
| `one export includes ten separate cold starts in order and redacts credentials`(:7-25) | 10 个会话按序拼接;`SECRET`、`username=artist` 被脱敏(:23-24) |
| `archive bounds sessions and bytes with visible truncation evidence`(:27-46) | maxSessions=2 丢弃最旧、512KiB→10 字节截断标记出现 2 次 |

`test/web_login_lifecycle_test.dart:299-301, 533-549`:端到端使用真实 logger 走完 OAuth 登录生命周期,最后 flush 并断言 `login.log` 含 `authorize dispatched`/`callback received`(:545-548)——验证 DAKit 诊断桥接不阻塞登录流,属附带覆盖,非失败路径。

### 缺口

1. **`initialize()` 自身失败无测试**:mock path_provider 抛异常 / `create` 抛 `FileSystemException` 时应降级而不炸 `main()`——正是第 2 题 P1,当前无测试且现状必挂。
2. **坏单例进程内恢复无测试**:打开失败后不 dispose、再次 `initialize()` 仍返回坏实例(`app_logger.dart:51`)的行为没有测试固定,也没有决策记录(D3)。
3. **导出契约无测试**:`readRecent` 依赖调用方先 flush,无测试固定「不 flush 会读到陈旧尾巴」或「flush 后导出包含最新行」。
4. **会话中途写失败无独立测试**:现有失败测试只覆盖「打开即失败」;打开成功后写失败(如磁盘满)走同一条 `catchError`,风险低,但 `done` 中途错误(构造器 :26 那条路径)无显式断言(flutter_test 会在未处理异步错误时挂测试,属隐式覆盖)。
5. 无轮转/清理测试(功能本身缺失,见 D4)。

---

## 总体结论

上一轮对 AppLogger 的修复(观察 `IOSink.done`、写+flush 共串行队列、幂等 close、排空后关、finally 清单例)在 14797b3 中**全部落实且有真实文件系统回归测试**;`runApp` 之后日志系统不再有阻塞启动的路径,ready 释放由 splash 的 12 秒兜底定时器独立保证。剩余风险集中在 `runApp` **之前**:`initialize()` 的平台目录/建目录/首次 flush 三个无超时 await——其中前两步异常还会直接崩溃 `main()`(P1),第三步挂起则无限期停留在原生启动画面(P1 风险)。3d62b45 卡在 Flutter splash 的症状与当前日志代码的挂起模式不符(那意味着 `main()` 已完成);若复现,应先区分原生画面与 Flutter splash,再查 ready 释放后的路由(每次 redirect 都有日志,`lib/app/router.dart:175`)。

## 缺陷列表

| # | 级别 | 缺陷 | 位置 | 最小修复建议 |
| --- | --- | --- | --- | --- |
| D1 | **P1** | `initialize()` 中 `getApplicationSupportDirectory()` / `logsDir.create()` 异常未捕获,冒泡至 `main.dart:57`,进程在 `runApp` 前崩溃,无任何 UI 与日志 | app_logger.dart:52-54 | 两步包 try/catch;失败时返回 NullSink 后备实例(复用 `:36` 模式)并 `debugPrint` 警告,`initialize` 永不抛 |
| D2 | **P1(风险)** | 启动关键路径上的日志 await 无超时(平台通道、建目录、首次 flush);磁盘挂起 → `main()` 在 `runApp` 前无限等待,停在原生启动画面 | app_logger.dart:52,54,67 + main.dart:57 | `initialize` 内部对三步加 `.timeout(..., onTimeout: ...)` 降级为控制台 logger(参照 app_runtime.dart:57-60 的 10 秒模式);或把 `:67` 的首次 flush 移出启动关键路径 |
| D3 | P2 | 打开失败的坏单例进程内永不恢复:生产无 `dispose()` 调用点,`initialize` 又直接复用现有实例,整个会话只有控制台日志 | app_logger.dart:51, 61, 173-176 | 在 `_reportFileFailure` 置失败标记;`initialize` 见坏标记时重建(先 close 旧 sink);或显式接受并文档化「本会话降级」 |
| D4 | P2 | 无轮转/清理:每次启动新建 `daviewer-<时间戳>.log`,旧文件无限累积;`logsDirectory` 注释声称 "rotated" 与实现不符 | app_logger.dart:55-57, 71 | `initialize` 成功后按文件名排序保留最近 20 个(与 LogArchive 的 20 会话一致)删除更旧者,失败仅警告 |
| D5 | P2 | 诊断页加载/导出全链路无超时:挂起磁盘下日志页永久转圈、分享面板永不弹出(不冻结 UI 线程) | diagnostics_screen.dart:42,58,77,87;log_archive.dart 全文 | `_loadLog`/`_exportLogs` 各套整体 `.timeout(const Duration(seconds: N))`,超时走既有错误提示分支 |

## 真机观察点

1. **先分辨卡点层级**:停在原生启动画面(无 Flutter UI)→ 指向 D1/D2,`adb logcat` 中应看不到 `DAViewer starting`(该行在 logger 初始化之后,main.dart:59);停在「正在恢复登录状态」(Flutter splash)→ 日志初始化已完成,查 12 秒兜底是否生效(logcat 找 `splash created deadlineMs=12000` 与 `ready=true reason=deadline`,splash_screen.dart:64,107-110),再看 ready 置 true 后路由是否循环(每次 redirect 都有 `route=... target=... ready=...` 日志,router.dart:175)。
2. **sink 失败证据**:logcat 搜 `[logger] file write unavailable`(app_logger.dart:175)——出现即文件通道故障,只有 runtimeType,需配合下一条定位。
3. **日志目录状态**:`adb shell ls -la /data/data/<pkg>/files/logs`(Android `getApplicationSupportDirectory` = `files/`):数 `daviewer-*.log` 个数验证 D4 累积;看当前会话文件是否在增长(不增长 = 写通道已死)。
4. **导出行为**:诊断页点导出,观察分享面板是否及时弹出(D5);导出的 `DAViewer-cold-start-logs.txt` 应含本次会话最新行(验证 flush-then-read 契约),且用户名/令牌均为 `[redacted]`。
5. **慢盘复现法(可选)**:向设备存储写入大文件制造 IO 压力后冷启动,观察是否出现原生画面停留(D2)——这是目前日志系统唯一能拖住启动的路径。
