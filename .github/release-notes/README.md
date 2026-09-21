# Release 正文说明

DVViewer 的 Release 正文默认面向中文用户，规则如下：

- `.release-policy.yml` 固定 `release.notes.language: zh`；
- 每次发版前在该目录放置 `<version>.md`，用中文写“本次更新”；
- 需要机器可读资产表时，ReleaseGraph 会在正文末尾自动追加“下载”表格。

没有覆盖文件时，ReleaseGraph 会用英文 commit 生成英文条目；因此每个发版版本
都应有对应的中文 `<version>.md`。
