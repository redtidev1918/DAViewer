# REG-004 Notice layout shift

## 症状

顶部通知横批出现后挤压 AppBar/内容，整页向下移动。

## 根因

通知使用参与正常布局流的 MaterialBanner/Column。

## 错误架构

```text
Column
 ├── Banner
 └── Content
```

## 正确架构

```text
AppShell
 └── Stack
      ├── Navigator
      └── Positioned
           └── NoticeOverlay
```

## 修复

- `AppNoticeHost` 改为 overlay，不改变 AppBar/内容/滚动位置。

## Regression

- Widget test 断言通知显示前后 AppBar/content geometry 不变。
