# Windows 本地桌面验证链 — 联合工作树 43fe8bf

日期: 2026-10-12 · 执行: 接管会话(自动化)

## 1. 环境与修复链(三次尝试)

- 源: 联合工作树 `C:\Users\12629\.codex\worktrees\daviewer-sdk-integration\DAViewer` @ **43fe8bf635a842801d0b9edd06b06b2b8deb930f**(owner 19:36:53+0800 推送,为 3d7d2d7 超集;构建期间工作树带 owner 未提交的 docs 类编辑——AGENTS.md/STATUS.md/docs×4,无代码影响,buildRevision 钉 HEAD)。
- 工具链: Windows + VS2022 Community 17.14.37628.2(`D:\Microsoft Visual Studio\2022\Community`),MSVC **14.44.35207(含 ATL)**——注意 14.38.33130 无 ATL;NuGet CLI `D:\Android\setup\nuget.exe`(不在默认 PATH);Flutter 3.47.6;`PUB_HOSTED_URL=https://pub.flutter-io.cn`(维持 pubspec.lock 与仓库一致,构建后 `git checkout -- pubspec.lock` 还原)。
- 尝试 1(`windows-desktop-verify-log.txt`,exit 1): `connectivity_plus_plugin.cpp` C2220+C4819(中文系统 GBK 代码页 936 遇非 GBK 字符,CI UTF-8 环境不触发)+ `flutter_secure_storage_windows_plugin.cpp` C1083 `atlstr.h`(默认选到无 ATL 的 14.38 工具集)。
- 尝试 2(`windows-desktop-verify-log2.txt` 前段,exit 1): 设 `VCToolsVersion=14.44.35207` + `CL=/utf-8` 后上述两错消失;改报 **NUGET-NOTFOUND**(flutter_inappwebview_windows 的 DEPENDENCIES_DOWNLOAD 步骤找不到 nuget)。
- 尝试 3(成功): 追加 `PATH+=D:\Android\setup`(nuget)→ `flutter build windows --release --dart-define="DAVIEWER_REVISION=43fe8bf…"` **exit 0**,159.4s(仅插件侧无害警告 C4244/C4458)。

## 2. 本地构建 + 30s 启动门

- 产物: `build\windows\x64\runner\Release\daviewer.exe`
- `python scripts/verify-desktop-startup.py --executable …\daviewer.exe --expected-revision 43fe8bf635a842801d0b9edd06b06b2b8deb930f --summary dist\release\startup-smoke-local.json` → **PASS**:
  `revisionMatches=true, readyObserved=true, splashExitObserved=true, reason=startup_ready, elapsedSeconds=1.765, scope=desktop_startup_only_no_login_verification`(verify exit 0)

## 3. CI 交叉证据(joint candidate run 38243805269)

- CI 自带 gate: artifact 内 `startup-smoke-Windows.json` = **PASS**(同 revision 匹配,elapsedSeconds 13.738)。
- 本地复跑 gate 于 CI 构建 exe(artifact `sdk-integration-Windows-43fe8bf` zip 解包后): **PASS**(elapsedSeconds 2.078),summary 存 `D:\Android\setup\joint-43fe8bf-windows\startup-smoke-local-run.json`。

## 4. 与计划预测的偏差(如实记录)

- 计划预测 buildRevision 嵌入 **3d7d2d7**;实际嵌入 **43fe8bf**——工作树 head 在 s3/s5 之间被 owner 前移(43fe8bf 为 3d7d2d7 超集,差异见 `main-vs-worktree-session4.txt` 与异常 u-lmhew8 记录),本次验证的是分支当前头。
- 96eec26 时脚本 1.552s;本次本地构建版 1.765s(同量级)。

## 5. 日志

- `windows-desktop-verify-log.txt`(尝试 1)、`windows-desktop-verify-log2.txt`(尝试 2+3 与本地 verify 输出)、工作树 `dist\release\startup-smoke-local.json`。
