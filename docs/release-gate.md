# DAViewer Release Gate

发布目标不是“无 Bug”，而是：

```text
没有已知 P0/P1
核心路径经过真实 Mac 验证
关键历史 Bug 有永久回归测试
剩余风险全部明确记录
```

## 必须解决

- `collections/all` 请求风暴
- 首页瀑布流不能继续加载
- WebView 重复加载 / Challenge 反馈环
- Notice 无法关闭、遮挡 UI
- 重复登录提示
- Pagination 重复请求
- API/Web Session 错误耦合
- `mature_content` 参数错误
- 所有已确认的 P0/P1

## 必须验证

- DAViewer 全量测试
- DAKit 全量测试
- macOS build
- Mac 首页真实滚动与分页
- WebView lifecycle
- Notice 实机表现
- 核心 API 请求行为

## Keychain 验收（环境限制）

项目**不购买 Apple Developer Program**，不要求付费开发者签名。

```text
Root cause understood;
application-side implementation verified;
stable signing behavior intentionally out of scope
because the project does not purchase Apple Developer Program signing.
```

接受：

- Debug：ad-hoc / 无 TeamIdentifier
- Release：未签名或本地非稳定签名
- 免费开发环境下系统偶尔要求一次 Keychain 授权

这属于签名模型造成的系统行为，不因“没有稳定签名”阻塞 `v0.4.12`。若应用自身
出现循环 `read/delete/create` Keychain item，仍属于 P1 缺陷。

## 当前状态

`v0.4.12` 已按项目决策发布，DAKit `dakit_api 1.1.1` 已上传 pub.dev。已知剩余
runtime caveats（Mac 交互 smoke、部分回归证据）记录在
`docs/architecture/data-lifecycle-audit.md`；Keychain 付费签名不再作为阻塞项。
