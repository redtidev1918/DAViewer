# 网络与代理

> English: [Networking and proxy](/en/networking.md)

DAViewer 区分两条操作系统本身也区分的路由：

- **应用流量**：OAuth token 交换、API、图片、视频、下载，以及隐藏的公开网页适配器。
- **系统浏览器流量**：唯一的官方登录/注册页，以及它打开的 DeviantArt、Google、Apple、Facebook 或验证页面。

应用可以配置自己的路由，但无法静默重配外部浏览器。UI 与诊断必须如实描述这条边界，不能承诺一次成功的连通性测试覆盖了两条路由。

## 选择与持久化

应用运行时的优先级为：

1. 持久化的应用内手动代理；
2. 操作系统系统代理（macOS 用 `scutil`，Windows 用注册表，Linux 用 GNOME 手动 HTTPS/HTTP 设置）；
3. `https_proxy`、`http_proxy` 或 `all_proxy`（大小写均支持）；
4. 构建期传入的 `DAKIT_PROXY_URL`；
5. 直连。

设置界面接受 HTTP CONNECT 代理，形式为 `host:port` 或完整 URL，例如 `http://127.0.0.1:<PORT>`。`<PORT>` 是占位符：用户需填入自己代理应用显示的 HTTP/Mixed 监听端口。在移动端，`127.0.0.1` 表示代理运行在同一台手机上。电脑或路由器上的代理需要其局域网 IP，并开启「允许局域网」选项。

从某个 shell 启动时 `export all_proxy=http://127.0.0.1:<PORT>` 有效。Finder、开始菜单与多数桌面启动器不会继承该变量，因此正式用户的应用流量应优先使用持久化的应用内设置，浏览器登录则使用系统代理或 VPN。

清除手动设置会立即重新执行自动探测。连通性测试通过生效的应用路由发送一个有时限的 DeviantArt 请求。它只报告**应用侧**可达性；详细的 socket 错误留在「诊断」中。

## 平台覆盖

| 平台 | 应用 API / 媒体 / 下载 | 隐藏的公开浏览器适配器 | 登录 WebView |
| --- | --- | --- | --- |
| Android | 系统/VPN 或动态应用代理 | 进程级 WebView 覆盖 | 同一进程级 WebView 覆盖 |
| Windows | 动态应用代理 | 共享 WebView2 `--proxy-server` | 同一共享 WebView2 `--proxy-server` |
| macOS 14+ | 动态应用代理 | `WKWebsiteDataStore.proxyConfigurations` | 同一 `WKWebsiteDataStore.proxyConfigurations` |
| macOS 12/13 | 动态应用代理 | 仅操作系统系统代理 | 仅操作系统系统代理 |
| Linux | 非当前构建目标（无 `linux/` 平台目录；CI 仅构建 Android/macOS/Windows） | — | — |

若日后加入 Linux 支持，注意 GNOME 下 `none` 会忽略过期的 host/port，`manual` 优先 HTTPS 再 HTTP，而 PAC `auto` 无法用 `dart:io` 的静态代理指令表达——届时 DAViewer 应记录该限制并继续回退到环境变量、构建期注入或直连。

Windows 的隐藏 WebView 与 Cookie 读取共用同一个 WebView2 环境。这保证公开适配器的 Cookie 与代理行为一致；它不是第二个认证会话。

## 启动连接状态

启动页在恢复登录状态时不再只显示转圈。它会显示当前代理探测状态，并通过应用侧
DeviantArt 请求做一次有期限的连通性检测：

- 未检测到代理时先说明“正在尝试直连”；
- 直连失败时明确提示开启代理/VPN；
- 使用代理时显示地址，并区分代理可达与不可达；
- 代理变化后会重新检测。

这些文案只描述应用流量是否可达，不承诺外部浏览器也使用同一条路由。
## 登录恢复流程

登录路由以内置原生 UI 开始，暴露一个官方登录操作、当前生效的应用路由、代理设置、连通性测试，以及公开的「设置/诊断」路由。

OAuth 在应用内嵌 WebView 中打开一次，与隐藏适配器走同一条网络路径。由 DeviantArt 页面决定可用哪些账号与服务商控件。用户可以关闭并重新打开登录界面，或取消待处理的 PKCE 事务。在 Windows 上，ZIP 版会在 `HKCU\Software\Classes\dakit` 下注册 `dakit://oauth/callback` 以支持外部浏览器回退，并把第二次进程激活转发给正在运行的应用。

服务商与边缘安全校验可能故意返回 HTTP 403、429 或 503 同时呈现交互页面。这些都在内嵌 WebView 内完成。DAViewer 既不把这些页面标记为应用连接失败，也不尝试脆弱的 DOM 探测。若 WebView 无法访问该页面，用户应修复应用路由（代理/VPN）；应用连通性测试报告的正是同一条路由。

## 维护者检查项

网络或认证相关发版之前：

1. 验证直连、自动、手动、环境变量与清除行为；
2. 用可用与已停止的代理分别测试 `all_proxy=http://127.0.0.1:<port>`；
3. 确认应用连通性文案没有声称测试了外部浏览器；
4. 在内嵌 WebView 中完成 DeviantArt 与可用社交服务商的授权，覆盖回调、关闭/重开、取消与冷启动回调；
5. 确认服务商挑战完全停留在交互式 WebView 内，应用持续等待且不误判为网络故障；
6. 确认授权成功后直接进入首页推荐，不再要求登录或网页会话提示；
7. 确认隐藏的公开适配器能匿名刷新并在无登录提示的情况下降级；
8. 在 Windows 上验证协议注册、进程转发与移动后的发布目录；
9. 原始代理、HTTP、解析与包细节只留在「诊断」中。
