// git4ai — AI 提交规范强制器(git wrapper, Go / Windows 版)
//
// 编译为 git.exe 放在 PATH 前置目录,顶替真实 git。仅拦截 commit 子命令,
// 提交前强制检查三条规范,违规只拒绝、不回滚,其余子命令原样透传真实 git。
//  1. 变更行数 ≤ 50(新增+删除;.md / 测试文件 / 隐藏文件豁免)
//  2. commit message 去空白后 ≥ 300 字(Unicode 字符计数)
//  3. 代码变更必须伴随同目录同名 .spec.md 变更(首次 commit 豁免)
//
// 版本: 0.1.0(win)
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"unicode"
)

const (
	maxLines    = 50
	minMsgChars = 300
)

// 真实 git 候选文件名:Windows 上为 git.exe,其余为 git。
func gitCandidates() []string {
	if runtime.GOOS == "windows" {
		return []string{"git.exe", "git"}
	}
	return []string{"git"}
}

// selfPath 返回当前可执行文件的绝对路径(用于在 PATH 中跳过自身)。
func selfPath() string {
	p, err := os.Executable()
	if err != nil {
		return ""
	}
	p, _ = filepath.Abs(p)
	return strings.ToLower(p)
}

// resolveRealGit 遍历 PATH,跳过 wrapper 自身(含大小写归一),返回第一个真实 git。
func resolveRealGit() string {
	self := selfPath()
	cands := gitCandidates()
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		if dir == "" {
			continue
		}
		for _, name := range cands {
			cand := filepath.Join(dir, name)
			st, err := os.Stat(cand)
			if err != nil || st.IsDir() {
				continue
			}
			if strings.ToLower(cand) == self {
				continue
			}
			// 跳过软链指向自身的条目
			if resolved, err := filepath.EvalSymlinks(cand); err == nil {
				if strings.ToLower(resolved) == self {
					continue
				}
			}
			return cand
		}
	}
	return ""
}

// isExempt 该路径是否豁免行数限制与 spec 要求(.md / tests / test_* / 隐藏文件)。
func isExempt(p string) bool {
	base := filepath.Base(p)
	if strings.HasPrefix(base, ".") {
		return true
	}
	if strings.HasSuffix(strings.ToLower(p), ".md") {
		return true
	}
	lower := strings.ReplaceAll(strings.ToLower(p), "\\", "/")
	if strings.HasPrefix(lower, "tests/") || strings.Contains(lower, "/tests/") {
		return true
	}
	if strings.HasPrefix(base, "test_") {
		return true
	}
	if i := strings.Index(base, "_test."); i >= 0 {
		return true
	}
	return false
}

// specOf 代码文件对应的 spec 路径:src/foo.go -> src/foo.spec.md
// 返回统一使用 "/" 分隔,与 git numstat 输出路径一致,便于比对。
func specOf(p string) string {
	dir := filepath.Dir(p)
	base := filepath.Base(p)
	base = strings.TrimSuffix(base, filepath.Ext(base))
	return filepath.ToSlash(filepath.Join(dir, base+".spec.md"))
}

// charCount 去掉全部 Unicode 空白后统计字符数(等价 bash ${#var})。
func charCount(s string) int {
	n := 0
	for _, r := range s {
		if !unicode.IsSpace(r) {
			n++
		}
	}
	return n
}

// gitExec 以给定全局参数 + 子命令+参数调用真实 git,返回 stdout + 退出码。
func gitExec(realGit string, globalArgs, rest []string) (string, int) {
	args := append(append([]string(nil), globalArgs...), rest...)
	cmd := exec.Command(realGit, args...)
	out, err := cmd.CombinedOutput()
	code := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			code = -1
		}
	}
	return string(out), code
}

func main() {
	realGit := resolveRealGit()
	if realGit == "" {
		fmt.Fprintln(os.Stderr, "git4ai: 找不到真实 git(PATH 中只有 wrapper 自身)")
		os.Exit(1)
	}

	args := os.Args[1:]

	// 定位子命令,跳过 git 全局选项及其值。
	cmd := ""
	cmdIdx := -1
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-C", a == "--git-dir", a == "--work-tree", a == "--namespace", a == "--exec-path", a == "-c", a == "--config":
			i++
		case strings.HasPrefix(a, "-"):
			// 其余形如 --foo=bar / -x 的全局/选项,当作纯选项跳过
		default:
			cmd = a
			cmdIdx = i
		}
		if cmd != "" {
			break
		}
	}

	// 非 commit:一律透传
	if cmd != "commit" {
		execRealGit(realGit, args)
	}

	// 收集全局参数,供检查命令(diff/log/rev-parse)指向同一仓库
	globalArgs := []string{}
	for i := 0; i < cmdIdx; i++ {
		a := args[i]
		switch a {
		case "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "-c", "--config":
			if i+1 < len(args) {
				globalArgs = append(globalArgs, a, args[i+1])
				i++
			}
		default:
			globalArgs = append(globalArgs, a)
		}
	}

	// 禁止绕过:--no-verify / -n
	for i := cmdIdx + 1; i < len(args); i++ {
		switch args[i] {
		case "--no-verify", "-n":
			fmt.Fprintln(os.Stderr, "✗ git4ai 提交被拒绝:禁止 --no-verify(-n)")
			fmt.Fprintln(os.Stderr, "    理由:该选项会绕过 git 的 hook 检查,AI 不得用它跳过提交规范。")
			os.Exit(1)
		}
	}

	// 提取 commit message 来源(-m / -F / -C / -c / --amend)
	var msgs []string
	msgFile := ""
	reuse := ""
	amend := false
	for i := cmdIdx + 1; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-m" && i+1 < len(args):
			msgs = append(msgs, args[i+1])
			i++
		case strings.HasPrefix(a, "-m") && len(a) > 2:
			msgs = append(msgs, a[2:])
		case strings.HasPrefix(a, "--message="):
			msgs = append(msgs, strings.TrimPrefix(a, "--message="))
		case a == "-F" && i+1 < len(args):
			msgFile = args[i+1]
			i++
		case strings.HasPrefix(a, "-F") && len(a) > 2:
			msgFile = a[2:]
		case strings.HasPrefix(a, "--file="):
			msgFile = strings.TrimPrefix(a, "--file=")
		case a == "-c" && i+1 < len(args):
			reuse = args[i+1]
			i++
		case a == "-C" && i+1 < len(args):
			reuse = args[i+1]
			i++
		case strings.HasPrefix(a, "-c") && len(a) > 2:
			reuse = a[2:]
		case strings.HasPrefix(a, "-C") && len(a) > 2:
			reuse = a[2:]
		case strings.HasPrefix(a, "--reuse-message="), strings.HasPrefix(a, "--reedit-message="):
			reuse = a[strings.Index(a, "=")+1:]
		case a == "--reuse-message" && i+1 < len(args):
			reuse = args[i+1]
			i++
		case a == "--reedit-message" && i+1 < len(args):
			reuse = args[i+1]
			i++
		case a == "--amend":
			amend = true
		}
	}

	// 组装 message;无任何来源则拒绝
	msg := ""
	msgSource := false
	if len(msgs) > 0 {
		msg = strings.Join(msgs, "\n") + "\n"
		msgSource = true
	} else if msgFile != "" {
		data, err := os.ReadFile(msgFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "✗ git4ai 提交被拒绝:无法读取 message 文件:%s\n", msgFile)
			os.Exit(1)
		}
		msg = string(data)
		msgSource = true
	} else if reuse != "" {
		if out, _ := gitExec(realGit, globalArgs, []string{"log", "-1", "--format=%B", reuse}); out != "" {
			msg = out
			msgSource = true
		}
	} else if amend {
		if out, _ := gitExec(realGit, globalArgs, []string{"log", "-1", "--format=%B", "HEAD"}); out != "" {
			msg = out
			msgSource = true
		}
	}

	if !msgSource {
		fmt.Fprintln(os.Stderr, "✗ git4ai 提交被拒绝:没有可检查的 commit message")
		fmt.Fprintln(os.Stderr, "    理由:git4ai 只支持 -m / -F / --amend / -C 方式提供提交说明,编辑器交互式提交不在支持范围。")
		fmt.Fprintln(os.Stderr, "    → 请用 -m 提供提交说明(AI 用法:git commit -m \"...\",去空白 ≥ 300 字)")
		os.Exit(1)
	}

	// 检查 1:变更行数(暂存区 numstat,新增+删除)
	numstat, _ := gitExec(realGit, globalArgs, []string{"diff", "--cached", "--numstat"})
	type pfStat struct {
		path string
		add  int
		del  int
	}
	var perFile []pfStat
	var changedPaths []string
	addTotal, delTotal := 0, 0
	for _, line := range strings.Split(numstat, "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 3 {
			continue
		}
		pa, pd, path := fields[0], fields[1], fields[2]
		a, d := 0, 0
		if pa != "-" {
			fmt.Sscanf(pa, "%d", &a)
		}
		if pd != "-" {
			fmt.Sscanf(pd, "%d", &d)
		}
		changedPaths = append(changedPaths, path)
		perFile = append(perFile, pfStat{path, a, d})
		if !isExempt(path) {
			addTotal += a
			delTotal += d
		}
	}
	total := addTotal + delTotal

	// 检查 2:message 长度(去空白字符数)
	chars := charCount(msg)

	// 检查 3:spec 同步(首次 commit 豁免)
	firstCommit := false
	if _, code := gitExec(realGit, globalArgs, []string{"rev-parse", "--verify", "-q", "HEAD"}); code != 0 {
		firstCommit = true
	}
	var specMissing []string
	if !firstCommit {
		has := func(p string) bool {
			for _, cp := range changedPaths {
				if cp == p {
					return true
				}
			}
			return false
		}
		for _, p := range changedPaths {
			if isExempt(p) {
				continue
			}
			if strings.HasSuffix(strings.ToLower(p), ".spec.md") {
				continue
			}
			sp := specOf(p)
			if !has(sp) {
				specMissing = append(specMissing, p)
			}
		}
	}

	// 汇总违规并输出可执行的修复建议
	lineOver := total > maxLines
	msgShort := chars < minMsgChars
	specBad := len(specMissing) > 0
	violations := 0
	if lineOver {
		violations++
	}
	if msgShort {
		violations++
	}
	if specBad {
		violations++
	}

	if violations > 0 {
		n := 0
		var b strings.Builder
		fmt.Fprintf(&b, "✗ git4ai 提交被拒绝:%d 项规范未满足\n\n", violations)
		if lineOver {
			n++
			fmt.Fprintf(&b, "[%d/%d] 变更行数超限:本次共 %d 行(+%d/-%d),限额 %d 行\n", n, violations, total, addTotal, delTotal, maxLines)
			b.WriteString("      超限文件明细:\n")
			for _, pf := range perFile {
				if isExempt(pf.path) {
					continue
				}
				fmt.Fprintf(&b, "      · %s: +%d/-%d(%d 行)\n", pf.path, pf.add, pf.del, pf.add+pf.del)
			}
			fmt.Fprintf(&b, "      建议:拆分为多个 ≤ %d 行的小提交(小步修改、小步提交),先提交核心逻辑,再提交配套修改。\n", maxLines)
		}
		if msgShort {
			n++
			fmt.Fprintf(&b, "[%d/%d] commit message 过短:当前 %d 字(去空白),要求 ≥ %d 字,还差 %d 字\n", n, violations, chars, minMsgChars, minMsgChars-chars)
			fmt.Fprintf(&b, "      建议:按「为什么改 / 怎么改 / 风险与验证」三段式写满 %d 字,覆盖变更动机、实现方式与影响面。\n", minMsgChars)
		}
		if specBad {
			n++
			fmt.Fprintf(&b, "[%d/%d] 缺少 spec 同步:以下代码文件的 .spec.md 不在本次变更中\n", n, violations)
			for _, p := range specMissing {
				fmt.Fprintf(&b, "      · %s → 需要 %s(新增或修改,且必须与代码同一次提交)\n", p, specOf(p))
			}
			b.WriteString("      建议:按 spec 模板补充「用途 / 对外接口 / 边界与异常用例 / 依赖与影响面 / 变更记录」。\n")
		}
		b.WriteString("\n(未做任何修改,工作区与暂存区保持原样。修复后重新 git commit 即可。)")
		fmt.Fprintln(os.Stderr, b.String())
		os.Exit(1)
	}

	// 全部通过:调用真实 git
	execRealGit(realGit, args)
}

// execRealGit 将控制权交给真实 git,stdin/stdout/stderr 透传并保持退出码。
func execRealGit(realGit string, args []string) {
	cmd := exec.Command(realGit, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	code := 0
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			fmt.Fprintln(os.Stderr, "git4ai: 调用真实 git 失败:", err)
			code = 1
		}
	}
	os.Exit(code)
}
