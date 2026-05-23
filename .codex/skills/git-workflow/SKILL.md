---
name: git-workflow
description: Manage Git version control for the Vanmo project, including committing, pushing, pulling, branching, and merging. Use when the user asks to commit code, push changes, pull updates, create branches, merge branches, resolve conflicts, check git status, or any Git-related operations.
---

# Git 版本管理

## 仓库信息

| 项目 | 值 |
|------|-----|
| 项目名称 | Vanmo |
| 本地路径 | `/Users/yingu/Vanmo` |
| 远程仓库 | `git@github.com:dl-Yang/Vanmo.git` |
| 远程名称 | `origin` |
| 主分支 | `main` |

所有 git 命令在 `/Users/yingu/Vanmo` 目录下执行。

## 提交规范（Conventional Commits）

提交信息格式：

```
<type>(<scope>): <subject>

<body>
```

### Type 类型

| Type | 含义 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(auth): add login with Face ID` |
| `fix` | 修复 Bug | `fix(payment): correct decimal rounding` |
| `refactor` | 重构（不改功能） | `refactor(network): simplify error handling` |
| `style` | 代码格式调整 | `style: fix indentation in views` |
| `docs` | 文档更新 | `docs: update API usage guide` |
| `test` | 测试相关 | `test(auth): add login flow tests` |
| `chore` | 构建/工具/依赖 | `chore: update SwiftLint to 0.55` |
| `perf` | 性能优化 | `perf(list): optimize scroll performance` |

### Scope（可选）

使用项目功能模块名称，如 `auth`、`home`、`payment`、`profile`、`network`、`storage` 等。

### Subject 规则

- 使用英文，祈使语气（"add" 而非 "added"）
- 首字母小写，结尾不加句号
- 不超过 72 字符
- 描述 **做了什么**，而非 **怎么做的**

## 常用工作流

### 1. 查看状态

每次操作前先了解当前状态：

```bash
git status
git log --oneline -10
git branch -a
```

### 2. 提交更改

```bash
# 查看变更
git diff
git diff --staged

# 暂存
git add <files>           # 指定文件
git add -A                # 所有变更

# 提交（使用 HEREDOC 保证格式）
git commit -m "$(cat <<'EOF'
feat(module): brief description

Optional detailed explanation.
EOF
)"
```

**重要**：
- 提交前始终运行 `git status` 和 `git diff` 确认变更内容
- 不要提交含敏感信息的文件（`.env`、证书、密钥等）
- 不要使用 `--no-verify` 跳过 hooks
- 不要使用 `git commit --amend` 修改已推送的提交

### 3. 推送到远程

```bash
# 推送当前分支
git push origin <branch-name>

# 首次推送新分支
git push -u origin <branch-name>
```

**重要**：
- 禁止对 `main` 分支执行 `git push --force`
- 推送前确认分支名和目标正确

### 4. 拉取更新

```bash
# 拉取并合并
git pull origin main

# 拉取但不合并（更安全）
git fetch origin
git log HEAD..origin/main --oneline    # 查看远程新提交
git merge origin/main                   # 确认后合并
```

### 5. 分支管理

```bash
# 创建并切换新分支（从 main 创建）
git checkout main
git pull origin main
git checkout -b feature/<feature-name>

# 分支命名规范
# feature/<name>    — 新功能
# fix/<name>        — 修复
# refactor/<name>   — 重构
# release/<version> — 发布

# 删除已合并的本地分支
git branch -d <branch-name>
```

### 6. 合并分支

```bash
# 将 feature 合并到 main
git checkout main
git pull origin main
git merge feature/<name>

# 如有冲突，解决后：
git add <resolved-files>
git commit
```

### 7. 暂存工作区

```bash
# 暂存当前未提交的修改
git stash push -m "描述"

# 恢复
git stash pop

# 查看暂存列表
git stash list
```

## 冲突解决流程

1. 运行 `git status` 找到冲突文件
2. 读取冲突文件，找到 `<<<<<<<`、`=======`、`>>>>>>>` 标记
3. 理解双方修改意图，合并为正确版本
4. 删除所有冲突标记
5. `git add <file>` 标记为已解决
6. 所有冲突解决后 `git commit`

## 安全规则

以下操作**禁止执行**，除非用户明确要求：

- `git push --force`（尤其是 main 分支）
- `git reset --hard`（会丢失未提交更改）
- `git clean -fd`（会删除未跟踪文件）
- `git rebase -i`（交互式 rebase 需要终端交互）
- 修改 `git config` 中的 user.name / user.email

## 操作前检查清单

每次执行 Git 操作前：

1. `git status` — 确认当前分支和工作区状态
2. `git diff` — 确认将要提交的内容
3. `git log --oneline -5` — 确认最近的提交历史
4. 确认目标分支正确
5. 确认没有敏感文件将被提交

## .gitignore 建议

iOS 项目应忽略的常见文件：

```gitignore
# Xcode
*.xcodeproj/project.xcworkspace/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
xcuserdata/
DerivedData/
*.moved-aside
*.pbxuser
*.perspectivev3

# Swift Package Manager
.build/
Packages/

# CocoaPods
Pods/

# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/test_output

# Environment
.env
*.p12
*.mobileprovision

# OS
.DS_Store
```
