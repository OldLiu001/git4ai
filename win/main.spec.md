# main.spec.md

> 本文件与同名源码 `win/main.go` **双向同步**:改代码必须同步本文件,改本文件必须落实到代码。

## 用途

git4ai 的 **Windows/Go 版** git 包装器(`git.exe`)。通过把编译产物放到 PATH 前置目录顶替真实 git,
只拦截 `commit` 子命令,提交前强制检查 AI 提交规范(变更行数 / commit message 长度 / spec 文件同步),
违规则**拒绝提交**并给出可执行修复建议;其余子命令交给真实 git 原样透传。

## 对外接口

| 名称 | 签名/格式 | 说明 |
|---|---|---|
| `git.exe`(编译产物) | `git [全局选项] commit [选项]` | 包装器本体;仅 `commit` 走检查,其余透传 |
| `install.bat` | `win\install.bat` | 用 Go 编译 `bin\git.exe`,复制到 `%USERPROFILE%\.git4ai\bin`,提示加入 PATH 前置 |
| 拒绝输出 | stderr,结构化多行 | 每条违规 = 实际值 / 限额 / 超限文件 / 修复建议 |

## 关键行为与约束

1. **真实 git 解析**:遍历 PATH(Windows 按 `;` 分隔),候选名 `git.exe` / `git`;跳过自身
   (`os.Executable` + `EvalSymlinks`,大小写不敏感);返回第一个非自身。找不到则报错退出。
2. **子命令范围**:只处理 `commit`(含 `--amend`);其他子命令原样透传(退出码保持,stdin/stdout/stderr 透传)。
3. **只拒绝,不回滚**:违规 `exit 1`,不改工作区、不删暂存;提示"未做任何修改"。
4. **行数限额**:`git diff --cached --numstat`,`新增+删除 ≤ 50`(硬编码)。
   - 豁免不计入:所有 `.md` 文件、位于 `tests/` 下的文件、`test_*` / `*_test.*` 命名、隐藏文件(`.` 开头)。
   - 二进制(numstat 为 `-`)计 0 行。
5. **message 长度**:去除全部 Unicode 空白(`unicode.IsSpace`)后按 rune 计 ≥ 300(中文按字符计,等价 bash `${#var}`)。
   - 来源:`-m`(可多个,拼接)、`--message=`、`-F` / `--file=`、`-C` / `-c` / `--reuse-message=`(取指定 commit message)、`--amend`(取 HEAD message)。
   - 无任何来源 → 拒绝,提示"请用 -m 提供提交说明"。
6. **spec 同步**:本次变更中每个"代码文件"(非豁免、非 `.spec.md` 自身),对应 `同目录同名 .spec.md`
   (`src/foo.go` → `src/foo.spec.md`,无扩展名文件 → `path.spec.md`)**必须在本变更集合中**。
   - `specOf` 统一返回 `/` 分隔,与 git numstat 输出一致(Windows 不误判大小写/分隔符)。
   - 豁免:`.md`、测试文件、隐藏文件。首次 commit(无 HEAD)整体豁免 spec 检查。
7. **禁止绕过**:`--no-verify` / `-n` 直接拒绝。
8. **全局参数兼容**:`-C <dir>`、`--git-dir=`、`--work-tree=`、`--namespace`、`--exec-path`、`-c key=val` /
   `--config` 带值全局选项在定位子命令时跳过其值,并收集作用于检查命令(diff/log/rev-parse)指向同一仓库。

## 边界与异常用例(corner cases)

| 用例名 | 输入 | 预期行为/结果 |
|---|---|---|
| 行数超限-拒绝 | 暂存 60 行代码 + 合规 message + spec | exit 1;stderr 含"变更行数超限"、实际行数、超限文件、拆分建议 |
| 行数合规-通过 | 暂存 ≤50 行代码 + 合规 message + spec | commit 成功(exit 0) |
| message 过短-拒绝 | 合规行数 + "短消息" + spec | exit 1;stderr 含"commit message 过短"、实际字数、差值、三段式建议 |
| message 300 字-通过 | 合规行数 + 去空白≥300 字 message + spec | commit 成功 |
| 缺 spec-拒绝 | 改 `src/foo.py` 无对应 spec + 其余合规 | exit 1;stderr 含"缺少 spec 同步"、缺失路径 `src/foo.spec.md`(或 `src\foo.spec.md`) |
| spec 同行变更-通过 | `src/foo.py` + `src/foo.spec.md` 同 commit + 其余合规 | commit 成功 |
| 纯文档提交-豁免 | 仅改 `README.md` + 短 message | 不要求 spec;行数豁免;仍受 message 长度约束 |
| 测试文件-行数豁免 | 暂存 60 行 `tests/test_x.py` + 合规 message | 行数检查通过;commit 成功 |
| 首次 commit-豁免 spec | 空仓库首提代码文件 + 合规 message | spec 检查跳过;commit 成功 |
| `--no-verify`-拒绝 | `git commit --no-verify -m ...` | exit 1;stderr 含"禁止 --no-verify" |
| 无 message 来源-拒绝 | `git commit`(无 `-m`/`-F`/`--amend`) | exit 1;提示"请用 -m 提供提交说明" |
| `-F` 文件-通过 | `git commit -F msg.txt`(≥300 字) | 读取文件内容检查;commit 成功 |
| `--amend`-继承检查 | `--amend` 复用 HEAD message(合规)+ 行数/spec 合规 | commit 成功 |
| 多 `-m` 拼接 | `-m "标题" -m "正文长文..."` | 拼接后去空白计数 |
| 非 commit-透传 | `git status` / `git log` / `git push` | 原样透传真实 git,保持退出码 |
| `-C` 目录-生效 | `git -C /path repo commit ...` | 检查作用于 `/path/repo` 的暂存区 |
| 找不到真实 git | PATH 中仅 wrapper | 报错"找不到真实 git"退出 |

## 依赖与影响面

- 依赖:Go 1.23+(编译期)、真实 git(PATH 中 wrapper 之外的 git.exe)、Windows。
- 影响面:所有经 PATH 解析 `git` 的进程(只拦 `commit`)。**局限性**:仅对按 PATH 顺序解析 git 的调用生效
  (cmd / PowerShell / 部分取 PATH 的 IDE);直接调 `git.exe` 绝对路径、或工具内部以固定路径解析真实 git 的调用会被绕过。
- 谁依赖我:Windows 下使用 PATH 前置安装的终端环境;README 引导的 AI 编码工具。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-21 | 0.1.0 | win 初版:Go 包装器(透传/三条检查)+ install.bat | 待提交 |