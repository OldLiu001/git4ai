# install.spec.md

> 本文件与同名源码 `win/install.bat` **双向同步**:改代码必须同步本文件,改本文件必须落实到代码。

## 用途

git4ai(Go / Windows 版)的构建与安装脚本:`compile bin\git.exe → copy to %USERPROFILE%\.git4ai\bin\git.exe → prepend that dir to user PATH`(顶替真实 git)。纯 ASCII(避免 cmd 按本地代码页误解析非 ASCII 导致命令被截断)。

## 对外接口

| 名称 | 签名/格式 | 说明 |
|---|---|---|
| `install.bat` | `win\install.bat` | 构建 git.exe,copy 到用户目录,并把该目录前置到"用户 PATH";幂等、带长度保护 |

## 关键行为与约束

1. 环境要求:运行时 `go` 已在 PATH(cmd 中用 `where go` 校验,缺失即报错退出)。
2. 构建:`go build -o bin\git.exe .`(在 `win/` 下)。
3. 安装位置:`%USERPROFILE%\.git4ai\bin\git.exe`(用户级)。
4. **PATH 前置(幂等)**:通过 PowerShell `[Environment]::SetEnvironmentVariable(...,'User')` 写注册表并广播更改;若该目录已在用户 PATH 则跳过;拼接后长度 >1024 则**不自动写入**并提示手动添加(防截断)。
5. **编码**:脚本保持纯 ASCII;提示信息用英文,面板细节写入 README(中文)。
6. 不改系统 PATH(只写用户 PATH),不影响其它用户。

## 边界与异常用例(corner cases)

| 用例名 | 输入 | 预期行为/结果 |
|---|---|---|
| 正常安装 | 首次运行(go 在 PATH) | 编译、copy、前置用户 PATH 全成功 |
| go 缺失 | PATH 无 go | 报错 `[x] go not found` 并 exit 1,不继续 |
| 重复安装 | 目录已在用户 PATH | 跳过添加,仍重新编译并 copy(幂等) |
| 超长 PATH | 拼接后 >1024 | 不自动写入,提示手动添加,不破坏现有 PATH |

## 依赖与影响面

- 依赖:Go(构建)、PowerShell(写用户 PATH)。
- 影响面:仅修改当前用户的用户级 PATH(前置 `%USERPROFILE%\.git4ai\bin`);对所有按 PATH 顺序解析 `git` 的调用生效。
- 谁依赖我:Windows 下安装 git4ai Win 版的用户。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-21 | 0.1.0 | win 初版:构建 + 用户目录安装 + 用户 PATH 前置 | 待提交 |