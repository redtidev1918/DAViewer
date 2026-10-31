---
title: Repository Request Contract
description: Contract placing cache, dedup, and single-flight request control in the repository layer.
---

# Repository Request Contract

目标：把 cache / dedup / single-flight 放在 Repository 层，不让 Provider 或 UI
重新发明请求控制。

## 契约

1. 每个 resource key 同一时间最多一个 in-flight request。
2. 成功结果可以缓存。
3. 失败结果永不缓存，失败后允许再次请求。
4. `force` 只用于显式 invalidate/用户刷新/身份变化，不用于自动重试。
5. UI rebuild、CSRF rotation、health 变化都不产生新请求。

## 实现

`lib/core/data/request_gate.dart` 的 `RepositoryRequestGate` 提供：

- `load<T>(key, loader)`：single-flight + success cache
- `force: true`：绕过缓存，仍 single-flight
- `cache: false`：只合并正在执行的请求，结束后不缓存；用于实时推荐分页
- `invalidate(key)` / `clear()`：显式失效
- `cancel(key)`：放弃该请求的缓存写入资格；晚到的结果不能覆盖缓存或移除替代请求

## 推荐列表的恢复规则

刷新创建新的请求版本。旧版本的分页成功或失败都不能再修改列表，
即使刷新后的游标与旧游标相同，也不能复用旧版本的请求。
列表按作品 ID 去重；分页返回原游标时停止加载，避免重复请求同一页。

首次加载失败显示错误；已有内容时刷新失败保留列表及游标，并提供刷新重试。
分页失败沿用退避和分页重试。实时列表不缓存已完成的页，避免刷新后接上旧页。
保留列表不放宽会话校验：登录失效或个性化能力降级仍由推荐页的会话恢复界面处理，
每日精选内容不能作为个性化推荐的替代结果。

隐藏浏览器的会话探测从代理准备开始计时，最多等待 20 秒。
只有主文档导航错误会结束探测，图片或字体加载失败不影响身份判断。
超时先返回“无法确认”，再尽力清理浏览器；旧浏览器回调不能结束新探测。

Repository 应该把 loader 包装进 gate：

```dart
final gate = RepositoryRequestGate();
Page<Artwork> fetch(String key) =>
    gate.load<Page<Artwork>>(key, () => transport.getPage(...));
```

## 暂不接线范围

这是契约落地，不要求本轮把所有 Repository 全部接入；下一步按各 feed provider
逐个迁移后再删除 Provider 里的局部 dedup/cooldown 逻辑。
