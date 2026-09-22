# REG-005 Duplicate authentication prompt

## 症状

首页 Web Session 未登录时，全局 AppNoticeHost 显示“未登录”，推荐区同时又显示
一个同语义 LoginPrompt，出现两个登录提示。

## 根因

同一全局状态同时由 overlay 和页面级 widget 各自表达；页面没有区分“全局状态”与
“业务上下文提示”。

## 正确架构

- 全局未登录/Web challenge：只由 `AppNoticeHost` overlay 提示；
- 具体业务上下文（收藏、跟随等）：可以保留 inline prompt；
- 首页推荐区不再自己渲染 Web Session 登录提示，只消费 feed 状态。

## 修复

- `HomeScreen._PersonalizedFeed` 移除三处 Web Session `LoginPrompt` 分支；
- `AppNoticeHost` 的 dismiss 只在同一 session-state occurrence 内生效，经历
  healthy 状态后同一状态可以再次提示。

## Regression

- `test/app_notice_host_test.dart`：dismiss 后保持隐藏；markHealthy 后再次进入
  同状态会重新出现。
