# REG-010 后台探测把已确认登录态改写为 anonymous（滑动后弹登录提示）

## 症状

v0.5.5 用户已登录且个性化推荐正常（rfy 成功 24 条），滑动一段时间后推荐 tab
突然变成登录/恢复提示；重启后有时恢复。日志时序：

```text
03:17:04.364 personalized feed fetch
03:17:05.430 personalized feed success items=24
03:17:05.648 verifier response classification=anonymous
03:17:05.652 web session probe unconfirmed
03:17:07.766 persist skipped reason=empty_capture
```

## 根因

1. `WebSessionRefresher._report()` 把「页面没解析出用户名」与「页面明确报告
   anonymous」合并成同一种结果，还会用**本地用户名**冒充页面观察结果上报；
2. 分页 403（WAF/CSRF）触发 `refresh()` 后，headless 页面若停在匿名/挑战页，
   `reportRefresh(..., username: 'anonymous')` 会穿透保留策略，把
   `WebSessionController` 改写成 `isLoggedIn=false`；
3. 推荐 tab 的请求门读到该身份，抛出 `web.session.unavailable`，UI 显示登录
   提示——尽管状态机里会话是 healthy。403 重试失败也错误地复用了
   `web.session.unavailable`。

一句话：**feed 的后台上下文刷新拥有了对认证结论的写权限。**

## 修复

- 探测结果三值化（`webSessionProbeResultFromPage`）：渲染出用户名 →
  confirmed；页面明确报 `anonymous` → anonymous；结构缺失/挑战页/加载不完整 →
  unavailable。未解析出用户名绝不等于登出；
- `reportRefresh` 只接受页面确认的用户名；匿名/未解析的探测上报空用户名，
  命中 preserve-signed-in 策略；同一账号的确认探测只轮转 CSRF，不重写身份、
  不输出 persist-failure 风格日志；
- rfy 重试仍失败改为 `rfy.feed.unavailable`（feed 故障），登录提示只能由
  权威会话链产生；
- 所有 `WebSessionStatus` 迁移带 `old -> new source generation claimed server`
  日志；推荐恢复 UI 与登录横幅各自记录出现事件。

## Regression

- `test/web_session_refresher_probe_test.dart`：username 存在/`anonymous`/
  缺失/null/CSRF 缺失分别映射 confirmed/anonymous/unavailable；
- `test/home_pagination_no_auth_damage_test.dart`：
  - 分页 403 + 探测 unavailable + 重试成功 → 状态保持 healthy、身份不变、
    页面正常追加；
  - 分页持续 403 → feed 错误码不是 `web.session.unavailable`，认证不变；
- `test/web_session_status_test.dart`：真实浏览器仲裁三态与既有回归保持。