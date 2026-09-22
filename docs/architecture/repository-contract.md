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
- `invalidate(key)` / `clear()`：显式失效

Repository 应该把 loader 包装进 gate：

```dart
final gate = RepositoryRequestGate();
Page<Artwork> fetch(String key) =>
    gate.load<Page<Artwork>>(key, () => transport.getPage(...));
```

## 暂不接线范围

这是契约落地，不要求本轮把所有 Repository 全部接入；下一步按各 feed provider
逐个迁移后再删除 Provider 里的局部 dedup/cooldown 逻辑。
