---
name: infuse-protocol-support
description: Guide the agent to incrementally detect, design, and implement Infuse-style connection protocols (local folder, SMB, FTP, NFS, WebDAV, cloud drives, Plex, Emby, Emby Connect, Jellyfin) for the Vanmo iOS app, with one protocol per iteration ending in tests, commit, and push. Use when the user asks to add or extend support for any of these media source protocols, mentions Infuse 协议、连接协议、媒体源协议、网盘 (Google Drive / Dropbox / OneDrive / pCloud / Yandex.Disk / MEGA / 阿里云盘 / 123 云盘 / 115 / 百度网盘), Plex/Emby/Jellyfin, or asks to "逐个实现协议".
---

# Vanmo 连接协议支持 Skill

引导代理按 Infuse 风格的协议清单，**一次实现一个协议**，全部走「检测 → 实现 → 测试 → commit → push → 暂停等待」的闭环。严禁在一次会话中跨多个协议批量实现。

## 协议清单（按官方编号）

| # | 协议 | 类型 | 备注 |
|---|------|------|------|
| 1 | localFolder | 本地 | 应用沙盒 / 文件 App / iCloud Drive |
| 2 | SMB | 网络共享 | NAS / Windows 共享 |
| 3 | FTP | 网络共享 | 明文 FTP |
| 4 | NFS | 网络共享 | 类 Unix 共享 |
| 5 | WebDav | HTTP | NAS、坚果云、AList 等 |
| 6 | GoogleDrive | 网盘 | OAuth |
| 7 | Dropbox | 网盘 | OAuth |
| 8 | OneDrive | 网盘 | OAuth (Microsoft Graph) |
| 9 | AddBox | 网盘 | (按用户清单原样保留命名) |
| 10 | pCloud | 网盘 | OAuth |
| 11 | Yandex.Disk | 网盘 | OAuth |
| 12 | MEGA | 网盘 | 端到端加密 |
| 13 | Aliyun Drive | 网盘 | 阿里云盘 |
| 14 | 123 CloudDrive | 网盘 | 123 云盘 |
| 15 | 115 CloudDrive | 网盘 | 115 网盘 |
| 16 | Baidu Netdisk | 网盘 | 百度网盘 |
| 17 | Plex | 媒体服务器 | Plex Media Server |
| 18 | Emby | 媒体服务器 | 自建 Emby |
| 19 | Emby (Emby Connect) | 媒体服务器 | Emby Connect 账号登录 |
| 20 | JellyFin | 媒体服务器 | Jellyfin |

> 严格按这个编号在沟通中引用协议，例如「正在实现 #5 WebDav」。

## 工作模式：单协议闭环

每次会话只推进**一个协议**。开始前必须确认目标协议编号；结束前必须 commit + push 并停下来等待用户决定是否进入下一个协议。

```
[选择协议 N]
   └── 1. 现状检测
   └── 2. 设计与确认
   └── 3. 实现
   └── 4. 测试 Gate
   └── 5. Git Gate（commit + push）
   └── 6. 暂停 → 报告 → 等待用户确认 → 才进入 N+1
```

## 1. 现状检测（必做）

在动手前完成以下检测，并把结果写在回复里：

1. 读取协议抽象与现有实现：
   - `Vanmo/Shared/Protocols/RemoteFileService.swift`
   - `Vanmo/Features/Browser/Models/ConnectionModels.swift`（`ConnectionType` 枚举、`SavedConnection`）
   - `Vanmo/Core/Network/ServiceFactory.swift`
   - `Vanmo/Core/Network/*Service.swift`
2. 用 Grep 在 `Vanmo/` 内确认目标协议是否已存在以下要素：
   - `ConnectionType` 枚举 case
   - `XxxService.swift` 实现
   - `ServiceFactory` 分支
   - `AddConnectionView` / `BrowserView` 入口
   - `MediaScanner` 或元数据扫描入口（媒体服务器类需要）
3. 给出三选一结论：**未实现 / 部分实现（缺哪些）/ 已完整实现**。
4. 若结论为「已完整实现」，停下来确认是否还需要补强（例如刷新 token、分页、错误处理），不要无脑重写。

## 2. 设计与确认

在写代码前先列出本次协议要新增/修改的文件清单与外部依赖，例如：

- `ConnectionType` 是否新增 case？显示名、icon、默认端口、`requiresAuth`、`isMediaServer` 怎么填？
- `RemoteFileService` 还是 `MediaServerService`？需要 OAuth / token 刷新 / 分块下载吗？
- 是否需要引入第三方 SDK 或 SPM 依赖？引入前必须列出包名、版本、协议许可与体积影响。
- `ConnectionConfig` 是否需要扩展字段（如 OAuth `accessToken` / `refreshToken` / `appKey`）？字段应避免破坏现有调用点。
- 凭据存储：必须用 Keychain，不得用 `UserDefaults`。
- UI 入口：`AddConnectionView` / `BrowserView` / 设置页是否需要新表单？
- 播放路径：`streamURL(for:)` 返回的 URL 是否需要走 `PrefetchProxy` 或自定义 `URLProtocol`？

如果存在多种合理方案（例如 Aliyun Drive 走开放平台 vs 逆向 Web API；百度网盘走官方 SDK vs 第三方代理），**停下来用 AskQuestion 让用户选择**，不要擅自决定。

## 3. 实现规范

- 每个协议一个独立 service 文件，路径：`Vanmo/Core/Network/<Protocol>Service.swift`，遵循 `swift-coding` 规则。
- 实现 `RemoteFileService`，媒体服务器额外实现 `MediaServerService`。
- 所有网络 IO 使用 `async/await`；共享可变状态使用 `actor`。
- 错误统一抛 `NetworkError` 中现有/新增的 case，禁止抛裸 `NSError`。
- OAuth/token 流程封装在独立的 `XxxAuthClient` actor 内，service 只消费 token。
- 新增 `ConnectionType` case 时，必须同步更新：`displayName` / `icon` / `defaultPort` / `requiresAuth` / `isMediaServer` / `ServiceFactory.makeService(for:)` / `AddConnectionView` 表单分支 / `BrowserView` 图标。
- 不要修改本协议范围之外的文件；与本协议无关的重构必须留到独立提交。

## 4. 测试 Gate（不通过禁止提交）

每个协议都要给出可复现的验证证据，至少满足以下三档之一：

1. **单元测试**：在 `Vanmo/Tests/` 下新增针对 service 的测试（mock URLProtocol / 协议层），并跑通。
2. **集成验证**：用真实账号或本地 mock 服务器（如 `vsftpd`、`samba`、`alist`）跑通「连接 → 列目录 → 取流 URL → 播放」一遍，截图或控制台日志贴回复里。
3. **手动验证清单**：当真机环境受限时，提供给用户一份「按步骤点这几下」的清单，并由用户回报通过后再进入 Git Gate。

执行步骤：

```bash
xcodebuild build \
  -project Vanmo.xcodeproj \
  -scheme Vanmo \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

- 编译通过是最低门槛，不算测试通过。
- 任何编译警告/SwiftLint 报错都必须当场修，不留给下一个协议。
- 测试失败时禁止 `git add`，先回到第 3 步修复。

## 5. Git Gate（commit + push）

测试 Gate 通过后必须按 `git-workflow` skill 的规范完成 commit 并 push 到 `origin`：

1. `git status` + `git diff` 复核，只包含本协议相关变更。
2. 提交信息使用 Conventional Commits：

```
feat(network): add support for <protocol-display-name>
```

   常用 scope：`network`（协议层）、`browser`（连接 UI）、`library`（媒体服务器扫描）。可在 body 里说明协议编号、依赖、限制。

3. 推送到主分支或当前工作分支：

```bash
git push origin <current-branch>
```

   - 默认推送当前分支，**禁止 `--force`**。
   - 如当前分支不存在远程跟踪，使用 `git push -u origin <branch>`。

4. 推送成功后立即在回复里给出：协议编号、提交 hash（`git log -1 --oneline`）、改动文件数、测试结论。

## 6. 暂停与交接

push 完成后**必须停下来**：

- 不要自动开始下一个协议，即使用户最初一次性列了多个。
- 用 AskQuestion 或简短文字询问：「#N 已完成并 push，是否进入 #N+1 ？或调整下一个目标？」
- 用户明确回答后才能开始新一轮闭环。

## 安全与红线

- 一次提交只对应一个协议；禁止把多个协议的实现塞进同一次 commit。
- 测试不通过禁止 commit，更禁止 push。
- 凭据、token、API Key 一律走 Keychain；任何 secret 不得出现在代码、注释、提交信息、日志里。
- 不允许 `git commit --amend` 已推送的提交、`git push --force`、`git reset --hard`。
- 不要悄悄升级或新增与本协议无关的依赖。
- 如果实现需要付费账号 / 私有 SDK / 厂商审核，**先停下来告诉用户**，不要伪造 mock 当真实实现提交。

## 推荐起步顺序（可被用户覆盖）

如果用户没指定先做哪一个，按「实现成本 ↑」推荐：

1. #1 localFolder
2. #5 WebDav
3. #2 SMB
4. #18 Emby / #20 JellyFin（已有部分代码可补齐）
5. #17 Plex
6. #3 FTP / #4 NFS
7. 其余网盘按 OAuth 易用性排序：#7 Dropbox → #8 OneDrive → #6 GoogleDrive → #11 Yandex.Disk → #10 pCloud → #9 AddBox → #12 MEGA → #13 Aliyun Drive → #14 123 / #15 115 / #16 Baidu Netdisk
8. #19 Emby (Emby Connect)（依赖 #18）

只是建议；若用户指定顺序，**完全按用户的来**。
