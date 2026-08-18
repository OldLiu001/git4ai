# git4ai.spec.md

> 本文件与同名源码**双向同步**：改代码必须同步本文件，改本文件必须落实到代码。

## 用途

git4ai 是一个 git 包装脚本（wrapper）：通过 PATH 前置覆盖 `git` 命令，只拦截 `commit` 子命令，
在提交前强制检查 AI 提交规范（变更行数、commit message 长度、spec 文件同步），不满足则**拒绝提交**并给出可执行的修复建议；
其余子命令一律透传给真实 git，不做任何干预。

## 对外接口

| 名称 | 签名/格式 | 说明 |
|---|---|---|
| `git4ai`（安装为 `git`） | `git [全局选项] commit [选项]` | 包装脚本本体；仅 `commit` 走检查 |
| `install.sh` | `./install.sh` | 安装到 `~/.local/bin/git`（PATH 前置时生效） |
| 拒绝输出 | stderr，结构化多行 | 每条违规 = 实际值 / 限额 / 超限文件 / 修复建议 |

## 关键行为与约束

1. **子命令范围**：只处理 `commit`（含 `--amend`）；其他任何子命令（`add`/`status`/`log`/`push`/`pull`…）原样透传。
2. **只拒绝，不回滚**：违规时 `exit 1`，不修改工作区、不删暂存内容；提示"未做任何修改"。
3. **行数限额**：`git diff --cached --numstat` 统计暂存区，`新增 + 删除 ≤ 50`（硬编码）。
   - 豁免不计入行数：所有 `.md` 文件（含 `.spec.md`）、`tests/` 目录下文件、`test_*` / `*_test.*` 命名文件、隐藏文件（`.` 开头）。
   - 二进制文件（numstat 显示 `-`）计 0 行。
4. **message 长度**：去除空白字符后 ≥ 300 字符（中文按字符计，bash `${#var}` 语义）。
   - 支持来源：`-m`（可多个，拼接）、`--message=`、`-F`/`--file=`、`--amend`（取 HEAD message）、`-C`/`-c`/`--reuse-message=`（取指定 commit message）。
   - 无任何 message 来源 → 拒绝，提示"请用 -m 提供提交说明"。
5. **spec 同步**：本次变更中的每个"代码文件"（非豁免、非 `.spec.md` 自身），其对应 `同目录同名 .spec.md`
   （`src/foo.py` → `src/foo.spec.md`，无扩展名文件 → `path.spec.md`）**必须在本次变更集合中**（新增或修改）。
   - 豁免不要求 spec：`.md`、测试文件、隐藏文件。
   - 首次 commit（仓库无 HEAD）整体豁免 spec 检查（鸡生蛋问题）。
6. **禁止绕过**：`--no-verify` / `-n` 直接拒绝（会跳过 hook 类检查）。
7. **真实 git 解析**：`command -v -a git` 遍历，跳过 wrapper 自身路径，取第一个真实 git；找不到则报错退出。
8. **全局参数兼容**：支持 `-C <dir>`、`--git-dir=`、`--work-tree=` 等带值全局参数（检查时同样作用于目标仓库）。
9. 阈值硬编码（初版），不做配置文件。

## 边界与异常用例（corner cases）

| 用例名 | 输入 | 预期行为/结果 |
|---|---|---|
| 行数超限-拒绝 | 暂存 51 行非豁免代码文件 + 合规 message + 合规 spec | exit 1；stderr 含"变更行数超限"、实际行数、超限文件路径、拆分建议 |
| 行数合规-通过 | 暂存 50 行代码 + 合规 message + spec | commit 成功（exit 0） |
| message 过短-拒绝 | 合规行数 + 42 字 message + spec | exit 1；stderr 含"commit message 过短"、实际字数、差值、三段式建议 |
| message 300 字-通过 | 合规行数 + 去空白 300 字 message + spec | commit 成功 |
| 缺 spec-拒绝 | 改 `src/foo.py` 无对应 spec 变更 + 其余合规 | exit 1；stderr 含"缺少 spec 同步"、缺失路径 `src/foo.spec.md` |
| spec 同行变更-通过 | `src/foo.py` + `src/foo.spec.md` 同 commit + 其余合规 | commit 成功 |
| 纯文档提交-豁免 | 仅改 `README.md` + 短 message | 不要求 spec；行数豁免；仍受 message 长度约束 |
| 测试文件-行数豁免 | 暂存 60 行 `tests/test_x.py` + 合规 message | 行数检查通过（豁免）；commit 成功 |
| 首次 commit-豁免 spec | 空仓库首提代码文件 + 合规 message | spec 检查跳过；commit 成功 |
| `--no-verify`-拒绝 | `git commit --no-verify -m ...` | exit 1；stderr 含"禁止 --no-verify" |
| 无 message 来源-拒绝 | `git commit`（无 `-m`/`-F`/`--amend`） | exit 1；提示"请用 -m 提供提交说明" |
| `-F` 文件-通过 | `git commit -F msg.txt`（≥300 字） | 读取文件内容检查；commit 成功 |
| `--amend`-继承检查 | `--amend` 复用 HEAD message（合规）+ 行数/spec 合规 | commit 成功 |
| 多 `-m` 拼接 | `-m "标题" -m "正文长文..."` | 拼接后去空白计数 |
| 非 commit 子命令-透传 | `git status` / `git log` / `git push` | 原样透传真实 git，不做检查 |
| `-C` 目录-生效 | `git -C /path/repo commit ...` | 检查作用于 `/path/repo` 的暂存区 |
| 找不到真实 git | PATH 中仅 wrapper | 报错"找不到真实 git"退出 |

## 依赖与影响面

- 依赖：bash 3.2+（macOS 默认）、git、核心文本工具（awk/sed/tr 可选，主逻辑纯 bash）。
- 影响面：所有调用 `git` 的进程（含 AI 工具、脚本、人类）；仅 `commit` 受影响。
- 谁依赖我：使用 PATH 覆盖安装的终端环境；README 引导的 AI 编码工具。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-18 | 0.1.0 | 初版：规格与验收测试 | `45bd821` |
| 2026-08-18 | 0.1.0 | 初版：git4ai 实现 + install.sh | `b8c6191` |
| 2026-08-18 | 0.1.0 | 初版：README 文档 | 待提交 |
