---
name: ios-device-debug-logs
description: Guide iOS real-device Debug troubleshooting without remote log instrumentation. Use when debugging iOS apps on a physical device, adding diagnostic logs, investigating runtime behavior, or when the user mentions Cursor Debug mode, console logs, 真机调试, 调试日志, or 远程日志插桩.
---

# iOS 真机调试日志

## 核心规则

当我在 ios 真机调试运行时，cursor 中的 debug 模式不要再进行远程日志插桩，而是添加调试日志，让我从 console 中手动复制

## 使用场景

当用户在 iOS 真机 Debug 运行中排查问题时，优先添加可在 Xcode Console 或 macOS Console.app 中看到的本地调试日志。

不要为了收集诊断信息而加入远程日志插桩、遥测上报、网络日志上传、外部观测 SDK、代理服务或服务端收集链路，除非用户明确要求。

## 工作流程

1. 先定位最小可疑路径，只在关键入口、状态变化、异步边界、错误分支和返回值处加日志。
2. 优先使用项目已有的日志工具；如果没有合适工具，再使用 `print`、`os.Logger` 或 `NSLog` 等能出现在本地 console 的方式。
3. 对临时诊断日志使用稳定前缀，例如 `[Debug][Player]`，并输出足够复现问题的上下文：对象 id、URL host/path、状态枚举、线程/任务边界、错误类型和关键耗时。
4. 避免输出隐私数据、认证信息、完整 token、cookie、用户文件内容或其他敏感值。
5. 需要用户提供运行证据时，请让用户在真机上复现后，从 Xcode Console 或 Console.app 手动复制相关日志片段回来。
6. 问题修复后，移除临时噪声日志；如果日志对长期维护有价值，保留为低噪声、结构化、非敏感的 Debug 日志。

## 实现约束

- 真机 Debug 排查默认不引入新依赖。
- 真机 Debug 排查默认不修改后端、云端、代理或远程日志管线。
- 临时日志应尽量用 `#if DEBUG` 包裹，避免进入 Release 行为路径。
- 日志文本要便于用户搜索和复制，避免过长、过密或跨多行难以匹配。
- 如果远程插桩看起来是唯一可行方案，先向用户说明原因并等待确认。
