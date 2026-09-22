# REG-001 WebView challenge

## 症状

首次进入 App 内网页登录页即显示 `Max challenge attempts exceeded. Please
refresh the page to try again!`。

## 根因

DeviantArt Web 侧返回 challenge error。DAViewer 没有证据推断“用户刷太多次”，
也不存在自动 reload 循环；该页面内容来自 DeVIANTArt 的 WAF/网络判定。

## 错误架构

- 把 Web 页面返回的 challenge 当作用户操作上限；
- 对 challenge 自动 refresh 或等待。

## 正确架构

- `WebSessionStatusState` 增加 challenge error 状态，只表示“页面返回验证错误”；
- App 不自动 reload；手动刷新 + 系统浏览器入口是唯一出路；
- Web Login 与 Home/API 数据树完全隔离。

## 修复

- `WebSessionStatusProvider` 状态机；
- `WebLoginScreen` 手动刷新；无自动 reload。
- `WebLoginScreen` 的 `InAppWebView` 使用稳定 key，challenge/verification banner
  插入时不会因 sibling slot 偏移重建 WebView controller。

## Regression

- WebView reload 自动触发器为 0；
- challenge 横幅为 overlay 且不移动布局。
