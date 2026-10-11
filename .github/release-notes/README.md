# Release 正文说明

DAViewer 的 Release 正文默认面向中文用户，规则如下：

- `.release-policy.yml` 固定 `release.notes.language: zh`；
- 每次发版前在该目录放置 `<version>.md`，用中文写“本次更新”；
- 需要机器可读资产表时，ReleaseGraph 会在正文末尾自动追加“下载”表格。

CI 检查 `.release-please-manifest.json` 中的当前版本是否有对应文件，并要求正文含中文及「本次更新」章节。缺少文件会使检查失败；不要依赖英文提交信息作为发布正文。
