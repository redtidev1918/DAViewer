# DAKit 2590cbe 审查与全量测试(takeover s2)

- 提交:`2590cbec59e0193d231addc73b3373cbe2b9b88e` "fix(oauth): serialize token transactions and fence logout immediately"(redtidev1918,2026-10-12 16:00:13 +0800,分支 codex/oauth-lifecycle-reliability,已推送 = PR #42 head)
- 变更(5 文件 +382/-26):docs/AUTHENTICATION.md +19;packages/dakit_api/lib/src/oauth/oauth_session.dart +91;packages/dakit_api/test/oauth_session_test.dart +244;packages/dakit_flutter/lib/src/dakit_oauth_client.dart +16;packages/dakit_flutter/test/oauth_logout_cleanup_test.dart +38

## 1. _withStore 序列化实现审查(oauth_session.dart)

**队列与有界性(L39, L189-211)**
- 所有存储事务(read/write/clear)经 `_withStore` 排入 `_storeTail`;`_storeTail = actual.then(_, onError:_)` 保存的是**真实 Native 完成而非超时包装**,迟到写/清按真实完成顺序排列;tail 错误被吞,队列不会中毒(测试:'storage write failure does not poison subsequent transactions')。
- 返回给调用方的 future 是 `actual.timeout(storeOperationTimeout)`(默认 5s,dakit_flutter 侧绑定 recoveryLookupTimeout)→ 每个调用方有界,超时抛 storage 类 `oauth.storage.timeout`(retryable)。
- `skipIfExpired`(默认 true):调用者已超时的排队操作在**触及存储之前**直接跳过;`skipIfExpired: false` 用于 logout(L125)与 refresh-invalidation(L181)的 clear——即使调用方超时,清除仍执行。

**save 语义(L74-90)**
- 事务内二次检查 `_loggingOut || expected != _generation`:过期写入(write A 已落盘但 session 已变)在**同一事务内** clear 再抛 `_changedSession` → 旧写入/迟到清理不可能超越新写入(测试:'issued save, logout and next save retain the new account',事件序 `['write:A','clear','clear','write:B']`;另有 'timed-out native write cannot overwrite or clear a newer account' 事件序 `['clear','write:B']`)。
- 同 generation 且未登出的超时写:写入成功后**保留**凭据供下次恢复(L86-88 注释 "A timeout is not logout…retain it for subsequent recovery";测试:'same-generation late save retains valid credentials after caller timeout' 与 'same-generation late refresh retains the rotated token after caller timeout')。

**logout 围栏(L92-137)**
- 单飞(memoized `_activeLogout`);`_generation += 1; _loggingOut = true` 同步先行,登出不可被晚到的 token exchange 撤销(测试:'logout cannot be undone by an in-flight refresh'、'a token exchange started before logout cannot restore a session')。
- 排空在途 refresh(L114,`storeOperationTimeout` 有界);revoke 在存储队列**之外**执行(L121,不阻塞队列,受 oauth_endpoint 的 dio connect 15s/receive 30s 界定);最终 clear 用 `skipIfExpired: false`;`_loggingOut` 在 finally 复位 → 删除失败不毒化下一次授权(测试:'failed token deletion cannot poison the next authorization')。
- flutter 客户端(dakit_oauth_client.dart logout 路径):**先同步调用** `session.logout()`(代数围栏先于 pending cleanup yield——"A login started while that cleanup is delayed must not be erased by an old logout that only reaches the token session several seconds later")再并行 await `cancelPending`+`logout`;pendingCleanup 错误全吞(best-effort,较旧版只捕 DAKitException 更宽,属有意)。另:`storeOperationTimeout: recoveryLookupTimeout` 把存储超时接到既有客户端设置。

**refresh 合并与失效(L139-187)**
- `_activeRefresh` 单飞(测试:'concurrent expired-session reads share one refresh request');invalid_grant → `_invalidateRefreshToken`:代数守卫(L178),clear(skipIfExpired:false)**完成后**才发 invalidations 事件,清除失败吞错保留 provider 错误(测试:'invalid refresh clears tokens and notifies the host')。

**审查结论**:未发现任何"迟到清理删除新账号 Token"的路径——每个 clear 要么被代数围栏(save 的过期写自清),要么序列化在 logout 边界内;未发现调用方无界等待(存储事务 5s、revoke 由 dio 界定、refresh 排空 5s)。

**两个已记录的固有边界**(记录在案,不构成推翻):
1. native 存储永久挂起时队列停摆:后续存储 ops 均有界报 storage.timeout,但存储 I/O 死到进程重启(native 操作不可取消,固有;测试 'hung native read is storage failure without deleting credentials' 钉住该失败形态——不删凭据)。
2. logout 的 revoke 窗口内(最长约 45s)`_loggingOut=true`,此时新登录的 save 抛 changed——围栏语义正确,表现为有界延迟而非数据损坏。SDK 层 logout() 返回的 future 未再包超时,依赖宿主有界等待(DAViewer auth_controller 已有 15s 级别界)。

## 2. 全量测试(本地,mirror CI quality job)

- 命令链:`dart pub get` → `dart run melos run format` → `dart run melos run analyze` → `dart run melos run test`(与 .github/workflows/ci.yml quality job + tool/verify.sh 同款,melos 脚本定义于 pubspec.yaml:六包 flutter test)
- 环境:本机 Flutter 3.47.6 stable / Dart 3.13.5(CI 为 3.47.1);HEAD 2590cbe,分支 codex/oauth-lifecycle-reliability,工作树干净
- 结果:**+262 All tests passed,exit 0**;format/analyze 均过(脚本逐段 exit-code 门禁,flutter analyze 默认 info 也致命 → 0 issues)。基线对比:worktree STATUS 记录 feec94f 时 251 → 262(净 +11,为 oauth_session 竞态新测试)。
- 完整日志:`dakit-2590cbe-test-log.txt`(559 行,含环境、各段输出)

## 3. CI 交叉核对(PR #42 @ 2590cbe)

- CI run 38240753370 绿(6m15s,quality 含 test:coverage)/ Release run 38240754037 绿(3m50s)/ Branch contract run 38240754041 绿

## 4. 判定

h1「withstore完备」= **支持**:实现审查未发现无限等待或迟到清理删新 Token 的路径;本地全量 262 PASS(exit 0);PR #42 三个 CI run 全绿。

## Postscript(2026-10-12 20:15 +0800,takeover 会话补记)

审查完成后状态变化:
- PR #42 head 前移:2590cbe → 6f8d7bd(纯 docs 检查点,JOINT-RELIABILITY-STATUS.md +11)→ a52d100(release.yml 有序发布 +29 / RELEASING.md +2),均为 redtidev1918 提交。
- PR #42 于 2026-10-12 19:51:41 +0800 被 redtidev1918 squash-merge 进 main,mergeCommit c43e6a1 "feat: make OAuth lifecycle and RFY transport reliable"。
- 代码同一性:`git diff --stat 2590cbe origin/main -- packages/dakit_api/lib/ packages/dakit_core/lib/ packages/dakit_flutter/lib/ packages/dakit_web/lib/` 为空 —— 本审查覆盖的全部 SDK 代码(含 oauth_session.dart)在 main 中逐字节一致;两个增量提交只动 docs 与 workflow。
- 上文「2590cbe 已推送 = PR #42 head」为审查时点(约 19:15)的事实,保留作历史记录;引用时:审查内容引 SHA 2590cbe,main 现状引 c43e6a1。
- merge 后 main 上 CI(38245381070)/Release(38245382007)/Static/notify 全部 success;release-please 分支 CI/Release 因 dakit_core 2.0.0 版本发布跨内部约束上限而失败,已提 PR #44 修复(约束上限放宽至 <3.0.0)。
