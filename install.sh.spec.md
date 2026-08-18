# install.sh.spec.md

> 本文件与同名源码**双向同步**：改代码必须同步本文件，改本文件必须落实到代码。

## 用途

git4ai 安装脚本：把仓库内的 `git4ai` wrapper 以符号链接方式安装到 `/usr/local/bin/git`
（系统级 PATH 首位区，裸运行也必然命中），真实 git 保持原名（`/usr/bin/git`），并校验安装环境唯一性。

## 对外接口

| 名称 | 签名/格式 | 说明 |
|---|---|---|
| install.sh | `./install.sh` | 安装 wrapper（软链到 `/usr/local/bin/git`）；支持 `GIT4AI_HOME` 覆盖目标目录 |

## 关键行为与约束

1. 目标目录默认 `/usr/local/bin`（`/etc/paths` 首位，任何 shell 裸运行 PATH 必含且排在 `/usr/bin` 之前），可用 `GIT4AI_HOME` 覆盖。
2. 安装方式：**符号链接** `$DEST_DIR/git → <repo>/git4ai`（真实 git 不能改名复制——git 内部把 `git-origin` 当子命令解析，报 `cannot handle origin as a builtin`）。
3. 真实 git 保持原名（`/usr/bin/git`），由 wrapper 运行时遍历 PATH 解析（跳过自身软链）。
4. 唯一性校验：目标 `git` 已存在且非符号链接 → 拒绝（exit 1）；PATH 中 git 数量 > 1 → 拒绝（exit 1）并列出冲突路径。
5. 不修改 PATH（`/usr/local/bin` 系统默认已含），仅提示状态。

## 边界与异常用例（corner cases）

| 用例名 | 输入 | 预期行为/结果 |
|---|---|---|
| 正常安装 | `./install.sh`（目标不存在） | 软链成功；提示已生效 |
| 目标已存在 | 已有非链接 `/usr/local/bin/git` | 拒绝覆盖，exit 1，提示手动处理 |
| 多 git 冲突 | PATH 中存在多个 `git`（如 `~/.local/bin/git` 残留） | 拒绝安装，exit 1，列出冲突路径 |
| 目标为符号链接 | 已有链接指向旧 wrapper | 覆盖链接（`ln -sf`），安装成功 |
| 自定义目录 | `GIT4AI_HOME=/opt/x ./install.sh` | 安装到 `/opt/x/git` |

## 依赖与影响面

- 依赖：bash、ln、chmod。
- 影响面：安装位置 `/usr/local/bin/git`；因该目录在系统默认 PATH 首位，**裸运行**（不读任何 shell 配置）也会命中 wrapper；所有 `git` 调用（仅 commit 被拦截）。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-18 | 0.1.0 | 初版 | `b8c6191` |
| 2026-08-18 | 0.2.0 | 改为软链安装到 `/usr/local/bin`（系统级，裸运行命中）；真实 git 保持原名；增加唯一性校验 | 待提交 |
