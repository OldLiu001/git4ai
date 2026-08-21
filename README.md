# git4ai

> 用 Git 层的硬约束，管住 AI 写代码。
> **小步修改、小步提交、spec 同步** —— 不满足就拒绝提交，并告诉你差在哪、怎么改。

## 为什么需要它

AI 写代码的典型失控场景：一次提交几百行、commit message 只有一句废话、修 bug 修到死循环、代码几万行人类根本审核不了。

给 AI 写 skill / 提示词约束？**它不遵守。** 唯一靠谱的约束点是工具链本身——于是有了 git4ai：一个覆盖 `git` 命令的包装脚本，在提交前强制检查三条规范，违规就拒绝，**只拒绝、不回滚、给方向**。

## 三条规则

| # | 规则 | 默认阈值 | 豁免 |
|---|------|---------|------|
| 1 | 单次变更行数（新增+删除） | ≤ 50 行 | `.md` 文件、`tests/` 与 `test_*`/`*_test.*` 测试文件、隐藏文件（`.` 开头） |
| 2 | commit message 去空白后字数 | ≥ 300 字 | 无（支持 `-m` 多个拼接 / `-F` 文件 / `--amend` / `-C` 复用） |
| 3 | 代码变更必须伴随 `.spec.md` 同步 | 同目录同名（`src/foo.py` → `src/foo.spec.md`） | 纯文档/测试提交；仓库首次 commit |

## 工作原理

```
你的终端 / AI 工具
      │  git commit ...
      ▼
~/.local/bin/git  ← git4ai（PATH 前置，覆盖真实 git）
      │
      ├─ 非 commit 子命令 → 原样透传真实 git（add/status/log/push... 一律不管）
      ├─ commit --no-verify / -n → 直接拒绝（禁止绕过）
      ├─ 检查 ① 暂存区变更行数（git diff --cached --numstat）
      ├─ 检查 ② commit message 字数（去空白）
      ├─ 检查 ③ 代码文件是否伴随同名 .spec.md 变更
      │
      ├─ 全部通过 → exec 真实 git 完成提交
      └─ 有违规   → 结构化列出每条违规 + 实际值 + 修复建议，exit 1（工作区原样）
```

被拒绝时你会看到类似这样的输出（每条都给出修复方向，AI 照做即可）：

```
✗ git4ai 提交被拒绝：2 项规范未满足

[1/2] 变更行数超限：本次共 87 行（+60/-27），限额 50 行
      超限文件明细：
      · src/foo.py: +40/-10（50 行）
      · src/bar.py: +20/-17（37 行）
      建议：拆分为多个 ≤ 50 行的小提交（小步修改、小步提交），先提交核心逻辑，再提交配套修改。

[2/2] commit message 过短：当前 42 字（去空白），要求 ≥ 300 字，还差 258 字
      建议：按「为什么改 / 怎么改 / 风险与验证」三段式写满 300 字，覆盖变更动机、实现方式与影响面。

（未做任何修改，工作区与暂存区保持原样。修复后重新 git commit 即可。）
```

## 安装

```bash
git clone https://github.com/OldLiu001/git4ai.git
cd git4ai
./install.sh          # 安装到 ~/.local/bin/git
# 若提示 PATH 未包含 ~/.local/bin，执行：
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

git --version         # 应正常显示 git 版本（透传验证）
```

卸载：`rm ~/.local/bin/git` 即可，真实 git 不受任何影响。

## Windows 版（Go 编译 git.exe）

bash 版面向 macOS/Linux;Windows 下用 Go 把 wrapper 编译成真正的 `git.exe`(cmd 与 PowerShell 都按 PATH 顺序命中,覆盖面比 bat 更广)。

```bat
cd win
install.bat        :: 编译 bin\git.exe → 复制到 %USERPROFILE%\.git4ai\bin → 提示加 PATH 前置
setx Path "%USERPROFILE%\.git4ai\bin;%Path%"   :: 或到"环境变量"图形界面把该目录排到最前
git --version      :: 应正常显示 git 版本(透传)
git commit -m "短"  :: 应被 git4ai 拒绝(演示拦截)
```

- 源码在 `win/main.go`,规格见 `win/main.spec.md`;逻辑与 bash 版一致(三条检查 + 透传,阈值 50/300)。
- **局限**:只拦"按 PATH 解析 git"的调用(cmd / PowerShell / 取 PATH 的 IDE);直接调 `git.exe` 绝对路径或工具内部固定解析真实 git 的调用会被绕过。
- 无法运行 bash 环境时,`win/` 即 Windows 版本体。

## 对 AI 的使用提示（如果你是被 git4ai 约束的 AI）

- 每次提交前先看 `git diff --cached --stat`，**主动拆分**超过 50 行的变更为多个提交
- commit message 用 `git commit -m "..."` 传入（**不要**打开编辑器交互式提交），写满 300 字：
  为什么改 → 怎么改 → 风险与验证
- 改代码前先确认同名 `.spec.md` 存在，把「用途 / 对外接口 / 边界与异常用例」写好，与代码**同一次提交**
- 不要尝试 `--no-verify` / `-n`：git4ai 在参数层直接拒绝
- 被拒绝不可怕：输出里写了每条违规的实际值与修复建议，照做重提即可

## 设计决策（v0.1）

| 决策 | 选择 | 理由 |
|------|------|------|
| 拦截范围 | 只拦 `commit` | commit 是唯一"交货点"，卡住它 AI 就交不了货；其他命令零干扰 |
| 违规处理 | 只拒绝，不回滚 | 自动回滚有数据丢失风险；拒绝后工作区原样，人工/AI 修完重提 |
| 阈值 | 硬编码（50 / 300） | 初版极简；后续版本支持配置 |
| message 来源 | 仅 `-m`/`-F`/`--amend`/`-C` | 编辑器交互式提交无法在调用前拿到内容，暂不支持（会被明确拒绝并提示） |
| 实现 | 纯 bash 单文件 | 零依赖，macOS/Linux 开箱即用 |

## 限制与 Roadmap

**已知限制（v0.1）**
- 阈值不可配置（硬编码 50 / 300）
- 不支持编辑器交互式提交（会拒绝并提示用 `-m`）
- 不拦截 `push`（commit 已检查；`--no-verify` 已在参数层禁止）
- 路径含 tab / 特殊引号的 numstat 输出未做完整转义解析
- 未实现 commit-msg hook 兜底（编辑器路径）——见 Roadmap

**Roadmap**
- [ ] 仓库级配置 `.git4ai.yml`（阈值 / 豁免规则可调）
- [ ] 自动安装 `commit-msg` hook，覆盖编辑器提交路径
- [ ] `git4ai check` 子命令：提交前干跑检查
- [ ] `git4ai rollback`：手动回滚违规暂存（可选开关）
- [ ] push 拦截（可选）
- [x] Windows 适配（Go 编译 git.exe,见 `win/`,已实现三条检查 + 透传）

## 开发与测试

```bash
./tests/run_tests.sh    # 12 条验收用例（行数/字数/spec/绕过/透传/边界），全绿
```

用例来源：`git4ai.spec.md` 的「边界与异常用例」表，逐条转成可执行测试。
本仓库开发遵循 **spec-driven-coding**：spec 先行 → 测试先行 → 小步提交。

## 版本

v0.1.0（2026-08-18）
