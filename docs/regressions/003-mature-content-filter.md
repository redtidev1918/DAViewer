# REG-003 Mature content filter in More Like This

## 症状

更多类似作品中的 NSFW 作品全部显示打码/模糊预览。

## 根因

`browse/morelikethis/preview` 未携带 `mature_content: true`，DA 对 NSFW 返回
模糊媒体。其它 DAKit 端点均已携带该参数。

## 错误架构

- 依赖“其它端点有，所以 More Like This 也有”。

## 正确架构

- 每个官方端点请求显式声明成熟内容策略；
- DAKit contract test 固定该行为。

## 修复

- DAKit `moreLikeThis` 查询添加 `mature_content: true`。

## Regression

- dakit_api contract test：断言 More Like This 请求 query 含 `mature_content=true`。
