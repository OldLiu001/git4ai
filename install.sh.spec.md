# install.sh.spec.md

> 本文件与同名源码**双向同步**：改代码必须同步本文件，改本文件必须落实到代码。

## 用途

git4ai 安装脚本：把仓库内的 `git4ai` wrapper 复制到 `~/.local/bin/git`（PATH 前置时全局生效），并校验安装环境。

## 对外接口

| 名称 | 签名/格式 | 说明 |
|---|---|---|
| install.sh | `./install.sh` | 安装 wrapper；支持 `GIT4AI_HOME` 环境变量覆盖目标目录 |

## 关键行为与约束

1. 目标目录默认 `$HOME/.local/bin`，可用 `GIT4AI_HOME` 覆盖。
2. 目标文件已存在且**不是符号链接** → 拒绝覆盖（exit 1），提示手动备份。
3. 安装 = 复制 + chmod +x；不修改 PATH（仅提示）。
4. 真实 git 路径不在此处解析（wrapper 运行时自解析）。

## 边界与异常用例（corner cases）

| 用例名 | 输入 | 预期行为/结果 |
|---|---|---|
| 正常安装 | `./install.sh`（目标不存在） | 复制成功；提示 PATH 状态 |
| 目标已存在 | 已有非链接 `~/.local/bin/git` | 拒绝覆盖，exit 1，提示备份 |
| 目标为符号链接 | 已有链接指向旧 wrapper | 覆盖链接，安装成功 |
| 自定义目录 | `GIT4AI_HOME=/opt/x ./install.sh` | 安装到 `/opt/x/git` |

## 依赖与影响面

- 依赖：bash、cp、chmod。
- 影响面：安装位置 `~/.local/bin/git`；PATH 前置后影响所有 `git` 调用（仅 commit 被拦截）。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-18 | 0.1.0 | 初版 | `b8c6191` |
