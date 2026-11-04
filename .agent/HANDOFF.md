# 会话交接

> 每次 Coding Agent 会话结束时在顶部追加一节，只记本会话发生的事实与下一步入口。跨会话状态在 [STATUS.md](STATUS.md)，任务在 [TASKS.md](TASKS.md)。

### 2026-11-04 提交发布准备（codex/fix-author-search）

- 本会话改动：同步 origin/main `1216df7` 的 CI/依赖更新后恢复本会话补丁，保留既有 `.zcode/`；修正新 Widget 测试的 Page 同名导入；编写 0.7.1 双语发布说明。远端已有 T-009，故本会话任务顺延为 T-011/T-012。
- 验证：临时工具链 `/tmp/daviewer-flutter-3.47.1`；本地完整验证与旧代码失败证据见 [REG-028](../docs/regressions/028-global-user-lookup.md)。未执行真实账号查询、实机验收或发布核验，CI/发布待本次 PR；没有把 Code Verified 写成设备验收。
- 未提交内容与风险：本会话代码、测试、回归、帮助与发布说明即将提交；`.zcode/` 不提交。本次新建备份 stash `codex-search-release-20261104` 已恢复到工作区，保留备份；未应用或删除旧 stash。SDK 位于 /tmp，环境清理后需要重新安装。
- 下一步入口：等待修复 PR 质量门和候选构建通过，再合并并跟进 release-please 版本 PR、三平台资产与线上下载页。

### 2026-11-04 作者全站用户名查询修复（本地 main，未提交）

- 本会话改动：移除用户搜索对 friends/search 的误用，复用当前 SDK 的全站完整用户名 lookup；空输入不请求；新增双语查询提示与帮助说明，以及 provider 请求路由回归。契约证据与范围见 [REG-028](../docs/regressions/028-global-user-lookup.md)，工程状态见 [T-012](TASKS.md)。不声称支持部分名称或显示名模糊搜索。
- 验证情况（含未跑的检查）：核对官方 Who Is 文档，并下载核对实际依赖 `dakit_api 1.2.0` 发布源码；格式检查通过（241 文件无变化，flutter_lints 依赖解析警告），diff check 通过。测试先于生产改动编写，但 targeted/full Flutter test 与 analyze 均因 command not found 未能启动，未取得修复前后 Flutter 执行证据。未执行联网账号查询、CI、构建、实机验收；没有提交、推送或发布。
- 未提交内容与风险：本次新增/修改 `search_providers.dart`、`search_screen.dart`、`app_strings.dart`、`app_strings_test.dart`、`user_search_test.dart`、双语 browse-and-search 帮助与 REG-028、`.agent/`；上次 URL 修复和其测试、REG-027 仍未提交。已有 `.zcode/` 保持原样。当前代码与新测试未通过 Flutter 类型检查或执行验证。
- 下一步入口：恢复 Flutter SDK 后先执行 `flutter test test/user_search_test.dart test/app_strings_test.dart test/da_uri_test.dart test/search_submission_test.dart --dart-define=DAVIEWER_VERSION=0.7.0`，再按 TESTING.md 跑完整 L1；用真实登录账号查询目标作者补运行证据。

### 2026-11-04 作者搜索范围诊断（只读代码检查）

- 本会话发现：`userSearchProvider` 调用 `OfficialUserRepository.searchFriends(query)` 且不传 username。2026-11-04 核对 [官方 Friends Search 文档](https://deviantart.readme.io/reference/user_friends_search)：该端点搜索关注列表，省略 username 时使用当前认证用户。因此现有「用户」搜索并非全站作者搜索，是已确认的功能范围错误；不能据此判断目标作者不存在。
- 验证情况（含未跑的检查）：检查了 provider、结果 UI 与本机缓存 SDK 的实现，官方文档独立证实端点范围；未取得用户搜索请求日志或目标账号 API 响应，未运行 Flutter 检查（本机仍缺 SDK）。目标作者这次失败的事件原因仍 Unverified。
- 未提交内容与风险：本次仅追加交接记录，上个条目的所有未提交代码、测试和已有 `.zcode/` 保持原样。本次没有修复作者搜索，也没有提交、推送或发布。
- 下一步入口：修复作者搜索时复用现有官方用户查询能力支持完整用户名查找，并明确区分关注列表匹配与全站搜索；先核验官方查询契约，再补回归测试。上次 URL 修复只解决链接导航，不解决作者搜索范围。

### 2026-11-04 画廊链接与搜索按钮（本地 main，未提交）

- 本会话改动：共享解析器接受画廊根链接；搜索页点击放大镜/回车复用解析器，链接不进入关键词防抖请求；补 URL 与 Widget 回归。证据、范围和限制见 [REG-027](../docs/regressions/027-gallery-link-search.md)，任务见 [T-011](TASKS.md)。
- 验证情况（含未跑的检查）：原始链接修复前返回 null、修复后路由正确；原生 Dart 12 项 URL 检查通过；`dart format --output=none --set-exit-if-changed lib test` 通过（240 文件无变化，缺依赖解析有警告）。未跑 Flutter analyze、Widget/全量测试、CI、构建及实机验收：无可用 Flutter SDK，`flutter` command not found；旧工作区 package_config 指向的 SDK 路径也不存在。没有提交、推送或发布。
- 未提交内容与风险：`lib/core/data/da_uri.dart`、`lib/features/search/search_screen.dart`、`test/da_uri_test.dart`、`test/search_submission_test.dart`、REG-027 与本次 `.agent/` 文档；Widget 测试尚未运行。会话前已存在的未跟踪 `.zcode/` 保持原样，不提交、不删除。
- 下一步入口：恢复 Flutter SDK 后，先跑 `flutter test test/da_uri_test.dart test/search_submission_test.dart --dart-define=DAVIEWER_VERSION=0.7.0`，再按 TESTING.md 执行 L1。目标账号页面抓取失败，实际联网加载未验证。

### 2026-10-31 PR #147（分支 docs/help-center）

- 本会话改动：文档站信息架构重构（应用户诊断「文档是工程交接记录而非使用说明书」）——新增双语帮助中心 12 页（`docs/help/` + `docs/en/help/`：快速上手、登录与账号、网络与代理、浏览与搜索、下载与保存、常见问题），写作依据为 `lib/core/l10n/app_strings.dart` 真实 UI 文案；authentication/networking（zh/en）用户操作内容迁出、仅保留实现契约并指向帮助中心；侧边栏双区（使用帮助/开发者文档）与首页「我想……」任务表重排（sidebar.generated.mjs 由固定 SHA 工具再生成）；download 页用真实 v0.7.0 JSON 本地重放同步新链接；根 README 用户任务行改指帮助页。**现有页面路径零变动**。
- 验证情况（含未跑的检查）：build 零死链（修复 en/authentication 两处 faq 相对路径）；docsite check 9/9、navcheck 零警告；12 页全部在 dist；白话质检对照 app_strings 无虚构 UI 路径。PR #147 CI 全绿（release 正确 skipping）；Pages run 41204239255 成功；实站验收：`/help/`、`/en/help/` 各页 200、旧页 200、首页双区渲染、download 页新链接在线。**未跑** Flutter 检查（无 Dart 改动）。
- 未提交内容与风险：无。遗留：帮助页截图暂缺（文字描述操作路径，后续可补图）；en 侧内容质量建议使用者阅读时顺带校订。
- 下一步入口：可选后续——帮助页配 App 截图；帮助中心使用数据观察（搜索热词）；og/sitemap 仍需 docsite 工具仓库升级（见 T-006 遗留）。

### 2026-10-31 PR #146（分支 docs/trim-recovery-transaction）

- 本会话改动：应用户要求评估并精简 `docs/authentication.md` / `docs/en/authentication.md` 的「Android 恢复事务」节——保留实机验收警示（T-002/T-003 仍 BLOCKED）、保守判证规则摘要、诊断导出行为、状态映射；观察器代际/指纹采纳/事务协调细则改为指向 REG-021 与 `docs/agent-tasks/session-recovery/` 归档（归档经核实含全部细节）。标题去掉「2026-10-12 修正」日期后缀，无锚点引用受影响。
- 验证情况：本地 build 零死链、docsite check 9/9、navcheck 零警告；PR #146 CI 全绿（docs/Analyze and test/branch-contract，release skipping）；合并后 Pages run 41202427693 成功，实站已无旧标题。未跑 Flutter 检查（无 Dart 改动）。
- 未提交内容与风险：无。
- 下一步入口：更大的文档站信息架构重构（帮助中心 vs 开发者文档分区）另行规划（T-008 候选）。

### 2026-10-31 PR #145（分支 docs/site-optimization）

- 本会话改动：文档站系统优化——删除 docsify 残留（旧 index.html、vendor、根级 .nojekyll、static.yml.docsite.bak）；侧边栏补全（zh/en 内容屏蔽、架构审计组、en 撤掉全部「(中文)」回退）；新译 en/TESTING、en/release-gate、en/architecture/web-session-and-notices；en/artwork-access 移入 en/architecture/ 对齐路径；login-status-proposal/RECOVERY-REPORT/notice-ux 归档进 docs/agent-tasks/；4 份英文审计移入 en/architecture/；21 个手写页加 title/description frontmatter；build.md 不再复述 L1 命令（权威在 TESTING.md）、示例版本 0.5.10→0.7.0；README.en.md 两处 `/#/en/` 修正；截图 900→540px q82（-30%）。sidebar.generated.mjs 由固定 SHA `d4915deb` 工具 `update` 再生成。
- 验证情况（含未跑的检查）：`npm run docs:build` 零死链；固定 SHA 工具 `docsite.py check` 9/9 一致、`navcheck` 零 error 零 warning；grep 复核移动/删除文件无残留引用（含 agent-tasks STATUS.md 一处反引号路径已修）；压缩截图经视觉检查无可见瑕疵。**未跑** `flutter analyze`/`flutter test`（无 Dart 改动，PR CI 亦不涉及）。
- 合并结果：PR #145 merge commit 合并为 main `00eed67`；CI 全绿（docs、Analyze and test、branch-contract，release build/finalize/release-please 正确 skipping，无客户端发布）；Pages 部署成功（run 41201701264），实站验收通过：en/TESTING 页 meta description 与新侧边栏（Content Filtering、Architecture 嵌套组、Architecture audits 组）在线、`/en/` 直达 200、web-session-and-notices 200、旧 vendor 404。T-006 已置 DONE。
- 未提交内容与风险：无。风险遗留：en 侧三页为新译内容，术语沿用回归目录词汇，使用者后续阅读时可顺带校订；4 份审计 URL 由 `/architecture/…` 变为 `/en/architecture/…`（零入链，仅外部书签影响）。
- 下一步入口：og:image/sitemap/en 独立 description 需 docsite 工具仓库升级模板后再升 pin（`.docsite.json` 的 themeKey 死键可顺手清理）；其余开发工作走 GitHub issues。

### 2026-10-31 VitePress 文档站试点

- 本会话改动：从最新远端新克隆接入 VitePress 1.6.4，使用 Node 22 构建；static.yml 备份停用，新 docs.yml 部署。71份原文档、旧 index/vendor 保留，未创建无关示例页面。修正截图路径、一个英文相对死链、一处跨行 inline code；语言切换交给主题菜单。
- 下载页：docsWorkflow 改为 docs.yml；使用真实 v0.7.0 JSON 本地回放，保留中英文安装说明与截图。docsite 上游补齐 previewFiles、英文平台名、LF 输出，验证工具固定到 d4915deb706aed0de55a77127b9c70abc127e627。
- 验证：Node 22 构建零 dead link、无.git副本 check 9/9；本次无 Dart 改动，未在本机跑 Flutter 测试，由既有 PR CI 执行。未进行 Android 实机验收，不发布客户端版本。
- 备份：原内容已备份到工作区外 backups/DAViewer-67c0e0f2eb31；旧文件不清理，回滚使用迁移前 Git 基线和备份。下一步是 PR CI、合并后 Pages 及真实 release dispatch 验收。

## 条目模板

```
### <日期> <分支 / PR>
- 本会话改动：
- 验证情况（含未跑的检查）：
- 未提交内容与风险：
- 下一步入口：
```

### 2026-10-26 PR #142（分支 docs/agent-governance）

- 本会话改动：建立 `.agent/` 六件（STATUS/PLAN/TASKS/HANDOFF/DECISIONS/LESSONS）、`docs/TESTING.md`、`.agents/skills/release/SKILL.md`、`.agents/skills/diagnosis/SKILL.md`；改写 `AGENTS.md` 为唯一入口；`docs/_sidebar.md`、`docs/en/_sidebar.md`、`docs/README.md` 增加测试规范入口。
- 验证情况：新文档内部相对链接逐一核对指向真实文件；未跑 Flutter 测试（无代码改动，CI 在 PR 上全量执行）。
- 未提交内容与风险：工作区既有未跟踪残留（session-recovery audits 备份、`.review-tmp/`、`.tmp-session-import/`、`.workbuddy/`、`clear/`）与两个 stash 保持原样未动。注意 `stash@{1}`（backup-local-edits-before-update-2026-10-12）是明确禁止应用的旧备份。
- 合并结果：PR #142 squash 合并为 main `ea7a2fe`，T-001 已置 DONE。PR 检查全绿（Analyze and test、branch-contract、release/build-plan dry-run）；main 上 Release 运行成功且 build/finalize 跳过——release-please 正确忽略纯 `docs:` 提交，未产生版本 PR，最新 release 保持 v0.7.0；Pages 已部署（侧边栏含测试规范入口）。
- 下一步入口：后续功能开发走 GitHub issues，发布按 `.agents/skills/release/SKILL.md`；遗留证据门见 T-002/T-003。

### 2026-11-01 SDK candidate trust

- 根因：#148/#149 的 Dependabot head 同属本仓，旧条件进入签名 candidate，Ubuntu 因缺生产密钥失败。
- 修复：明确 dispatch 或可信关联的同仓人工 PR，额外排除 Dependabot 作者/执行者/重跑者；quality 无条件且无生产 Secrets。
- 验证：scripts/test-sdk-trust.py 直接求值真实 workflow 表达式；旧实现失败，修复后通过。main classic required contexts=[]、active rules=[]（本次 API 读取）；不修改保护规则。远端 CI 尚待验证；Flutter 本地未跑（无 Dart 改动）。

## 2026-11-01 codex/sync-docsite-template

上游 docsite #16 已合并；更新固定 SHA 并运行 docsite update。旧 pin 附带的下载页生成器 showAssetTable 选项默认保持原输出。npm ci、docs:build、无 .git 的 check/navcheck 通过；应用测试未在本地重跑，远程 CI 和 Dependabot 最新 SHA 待验收。
