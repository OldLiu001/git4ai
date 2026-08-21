# go.spec.md

> 本文件与 `win/go.mod` 双向同步。

## 用途

git4ai(Go / Windows 版)模块定义:module 名 `git4ai/win`,Go 版本 `go 1.23`。本模块是自包含单文件程序(`main.go`),无第三方依赖。

## 对外接口

| 名称 | 说明 |
|---|---|
| `go.mod` | 定义模块 `git4ai/win`,go 1.23 |

## 关键行为与约束

1. 无外部依赖(仅标准库),`go build` 即出单文件 `git.exe`。
2. module 路径 `git4ai/win` 仅用于本地构建,不发布。

## 边界与异常用例

| 用例名 | 输入 | 预期行为 |
|---|---|---|
| 编译 | `go build -o bin\git.exe .`(win 目录下) | 生成 `bin\git.exe` |
| go 版本 | go < 1.23 | 编译报错要求升级 |

## 依赖与影响面

- 依赖:Go 1.23+。
- 影响面:仅 Windows 版构建。

## 变更记录

| 日期 | 版本 | 变更摘要 | 关联 commit |
|---|---|---|---|
| 2026-08-21 | 0.1.0 | win 初版 | 待提交 |