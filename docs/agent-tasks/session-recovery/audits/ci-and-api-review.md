# CI 终态核查与公共 API diff 审查 — 2026-10-12(接管会话 s6)

## 1. CI run 终态(gh 实测)

| 范围 | run / 检查 | 终态 |
| --- | --- | --- |
| DAKit PR #42 分支 @ 2590cbe | CI 38240753370 / Release 38240754037 / Branch contract 38240754041 | 全 success |
| DAKit main(squash 后 c43e6a1) | CI 38245381070 / Release 38245382007 / Static Pages / notify | 全 success(11:51:44Z) |
| DAKit release-please 分支(首轮 da7901f) | CI 38245652481 / Release 38245653132 | **failure** → 根因:提议 dakit_core 2.0.0 撞 workspace 内部约束上限 `<2.0.0`;经 PR #44(559a1b4,四包约束放宽 `<3.0.0`)修复 |
| DAKit PR #44(本会话) | 全部 checks | 全 SUCCESS;squash 合并 5b15497 @ 12:43:06Z |
| DAKit PR #43(release-please 再生,head 1011cde) | 全部 checks | 全绿,mergeStateStatus **CLEAN**(合并属 s7,不可逆) |
| DAViewer PR #97 分支 @ 43fe8bf | CI 38240761910 / Branch contract / Release 38240762782 | 全 success |
| DAViewer joint candidate 38243805269 | quality + candidate(ubuntu / windows-2022 / macos-26) | 全 success(provenance: daviewer_sha=43fe8bf…, dakit_sha=2590cbe…) |
| DAViewer Release(分支)38243806005 | 全部 | success |
| DAViewer PR #97 / PR #96 | branch-contract / Analyze and test / quality / build-plan | PR #97 CLEAN MERGEABLE;PR #96 CLEAN |

## 2. joint candidate 三平台产物与签名

- Linux(31.5MB):`DAViewer-v0.5.13.apk`,SHA256 `7720B79CAFAFDC1C001D2FFA57DC5F5C15D65F26793090218A83EAA68420F63B`(67,445,346 bytes);apksigner 证书 SHA-256 `686474b39fd91d20c1db3ce5bf6216ed8ab05ec7638f904251e0d108a34e7141` = 正式发布证书;aapt:package `app.daviewer` versionCode 225 versionName 0.5.13,minSdk 24 / target 36,MainActivity 内 meta-data `flutter_deeplinking_enabled=0x0`。
- Windows(14.6MB):release 构建;`verify-desktop-startup.py` 门 PASS(CI 13.738s;本地复跑 CI exe 2.078s)。
- macOS(25.3MB):candidate job success(CI 侧构建+门)。
- 三平台源钉:`sdk-integration-provenance.json`(daviewer_sha=43fe8bf635a842801d0b9edd06b06b2b8deb930f,dakit_sha=2590cbec59e0193d231addc73b3373cbe2b9b88e,candidate_only=true)。

## 3. DAKit 公共 API diff 审查(基于 s2 深审 docs/agent-tasks/session-recovery/audits/dakit-2590cbe-review.md + c43e6a1 stat)

- `oauth_session.dart` +91:存储事务序列化(`_withStore` 队列、`skipIfExpired`、存储超时→`DAKitException(oauth.storage.timeout)`)与登出代数围栏。公共语义变化:logout/失效期间的迟到写不再能覆盖新账号凭据;超时路径有界。实现审查结论=正确完备(阶段事实 f-pdj8f1;本地全量 262 测试通过,含竞态回归)。
- `dakit_oauth_client.dart` +16:logout 改为同步先 `session.logout()`(代数围栏先于 pending cleanup yield)再并行 await;RFY `CancelToken` + `retryInvalidCsrf:false`。
- `authorization_coordinator` +90 / `diagnostic_sink` +11 / `oauth_endpoint` +5 / `oauth_token_client` +7 / `redaction` +45:分支既有的可靠性修复(更早 joint CI 38218485367 三平台 PASS 已验)。
- 破坏性版本:dakit_core 2.0.0(a9f0837 重命名,`packages/dakit_core/lib` 9 文件)。**DAViewer 已在钉 2590cbe(含该重命名)上全量 488 测试通过** → 消费一致,无未消费的破坏性变更。
- 发布内容 = 联测内容:`git diff --stat 2590cbe origin/main -- packages/*/lib/` 为空(逐字节一致);workspace 约束经 PR #44 放宽,发布后 DAViewer 换 pub 版本无阻塞(s8)。

## 4. PR 处理与合并顺序(结论)

- **PR #42**:已由 owner(redtidev1918)squash 合并为 c43e6a1 @ 19:51:41+0800。SDK-INTEGRATION 曾要求 "Do not merge SDK #42 or publish until new source and joint tests pass"——由仓库主人自行裁决;本会话在合并后补齐联测证据(joint candidate 38243805269 三平台 + DAViewer 488 + DAKit 262)并验证内容一致性(发布树与联测树逐字节相同)。
- **PR #44**(本会话):squash 5b15497,解除 release-please 版本求解阻塞。
- **PR #43**(release-please,提议 dakit_core 2.0.0 / dakit_api 1.2.0 / dakit_flutter 1.1.0 / dakit_web 0.3.0):CLEAN 就绪;合并即触发组件 tag + OIDC publish(**不可逆**,执行前 Frame 登记 irreversible)。
- **PR #97** @ 43fe8bf:CLEAN MERGEABLE;**PR #96** @ aead827:CLEAN。顺序:s7 合并 PR #43(发布)→ s8 DAViewer 换 pub 正式依赖并全量重测 → 合并 PR #97 进 codex/android-session-recovery → PR #96 保持 Draft 待 owner 真机验收。

## 5. 证据文件索引

`eval-ci-api-probes.txt`(PR #42 合并/release 探测归档)、`android-callback-emulator-verify.md` + `android-emulator-43fe8bf/`(s4)、`windows-desktop-verify.md` + 日志(s5)、`dakit-2590cbe-review.md` + 测试日志(s2)、`main-vs-worktree-session4.txt`(s1)、`worktree-3d7d2d7-test-log.txt`(s3)。
