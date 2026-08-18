#!/usr/bin/env bash
# git4ai 验收测试 — 用例来自 git4ai.spec.md「边界与异常用例」表
# 用法: ./tests/run_tests.sh
set -u

# 字符计数依赖 UTF-8 locale（与 git4ai 脚本一致）
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GIT4AI="$ROOT/git4ai"
REAL_GIT="$(command -v git)"
PASS=0
FAIL=0
FAILED_NAMES=()

# ---------- 工具函数 ----------

# 生成去空白后 >= 300 字的 commit message
long_msg() {
  local s=""
  while [ ${#s} -lt 320 ]; do
    s="${s}这是一个足够长的提交说明用于满足字数要求同时覆盖为什么改怎么改以及风险验证"
  done
  printf '%s' "$s"
}

new_repo() {
  local d
  d="$(mktemp -d)"
  "$REAL_GIT" -C "$d" init -q -b main
  "$REAL_GIT" -C "$d" config user.email test@git4ai.local
  "$REAL_GIT" -C "$d" config user.name "git4ai-test"
  echo "$d"
}

# 断言: 期望命令 exit code 与输出子串
expect() {
  local name="$1" want_code="$2" want_out="$3"
  shift 3
  local out code
  out="$("$@" 2>&1)"
  code=$?
  if [ "$code" -eq "$want_code" ] && printf '%s' "$out" | grep -qF "$want_out"; then
    PASS=$((PASS+1))
    echo "  ✓ $name"
  else
    FAIL=$((FAIL+1))
    FAILED_NAMES+=("$name")
    echo "  ✗ $name (期望 exit=$want_code 含「$want_out」，实际 exit=$code)"
    printf '%s\n' "$out" | head -8 | sed 's/^/      | /'
  fi
}

# 暂存一个非空文件（写入多行）
stage_file() {
  local repo="$1" path="$2" lines="$3"
  mkdir -p "$repo/$(dirname "$path")"
  seq 1 "$lines" > "$repo/$path"
  "$REAL_GIT" -C "$repo" add "$path"
}

# ---------- 用例 ----------

echo "== git4ai 验收测试 =="
[ -x "$GIT4AI" ] || echo "  [warn] $GIT4AI 不存在或不可执行（实现未就绪，预期全红）"

# T1 行数超限-拒绝
echo "T1 行数超限-拒绝"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 51
  printf '%s' "src/foo.py 边界处理说明" > "$r/src/foo.spec.md"
  "$REAL_GIT" -C "$r" add src/foo.spec.md
  expect "T1-超51行被拒" 1 "变更行数超限" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T2 行数合规-通过（50 行 + spec + 长 message）
echo "T2 行数合规-通过"
{
  r="$(new_repo)"
  stage_file "$r" src/bar.py 50
  printf '%s' "src/bar.py 边界处理说明" > "$r/src/bar.spec.md"
  "$REAL_GIT" -C "$r" add src/bar.spec.md
  expect "T2-50行通过" 0 "" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T3 message 过短-拒绝
echo "T3 message 过短-拒绝"
{
  r="$(new_repo)"
  stage_file "$r" src/baz.py 1
  printf '%s' "src/baz.py 边界处理说明" > "$r/src/baz.spec.md"
  "$REAL_GIT" -C "$r" add src/baz.spec.md
  expect "T3-短message被拒" 1 "commit message 过短" "$GIT4AI" -C "$r" commit -m "修复bug"
}

# T4 缺 spec-拒绝（先做一次合规首提，避开首提豁免）
echo "T4 缺 spec-拒绝"
{
  r="$(new_repo)"
  stage_file "$r" README.md 5
  "$REAL_GIT" -C "$r" commit -q -m "$(long_msg)"
  stage_file "$r" src/nospec.py 1
  expect "T4-缺spec被拒" 1 "缺少 spec 同步" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T5 纯文档提交-豁免 spec 与行数，仍查 message
echo "T5 纯文档提交-豁免"
{
  r="$(new_repo)"
  stage_file "$r" README.md 80
  expect "T5-纯文档豁免通过" 0 "" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T6 测试文件-行数豁免
echo "T6 测试文件-行数豁免"
{
  r="$(new_repo)"
  stage_file "$r" tests/test_util.py 60
  stage_file "$r" src/util.py 1
  printf '%s' "src/util.py 边界处理说明" > "$r/src/util.spec.md"
  "$REAL_GIT" -C "$r" add src/util.spec.md
  expect "T6-测试文件豁免通过" 0 "" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T7 首次 commit-豁免 spec
echo "T7 首次 commit-豁免 spec"
{
  r="$(new_repo)"
  stage_file "$r" src/boot.py 5
  expect "T7-首提豁免spec通过" 0 "" "$GIT4AI" -C "$r" commit -m "$(long_msg)"
}

# T8 --no-verify-拒绝
echo "T8 --no-verify-拒绝"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 1
  printf '%s' "spec" > "$r/src/foo.spec.md"
  "$REAL_GIT" -C "$r" add src/foo.spec.md
  expect "T8-no-verify被拒" 1 "禁止 --no-verify" "$GIT4AI" -C "$r" commit --no-verify -m "$(long_msg)"
}

# T9 无 message 来源-拒绝
echo "T9 无 message 来源-拒绝"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 1
  printf '%s' "spec" > "$r/src/foo.spec.md"
  "$REAL_GIT" -C "$r" add src/foo.spec.md
  expect "T9-无message被拒" 1 "请用 -m 提供提交说明" "$GIT4AI" -C "$r" commit --amend
}

# T10 -F 文件-通过
echo "T10 -F 文件-通过"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 1
  printf '%s' "spec" > "$r/src/foo.spec.md"
  "$REAL_GIT" -C "$r" add src/foo.spec.md
  printf '%s' "$(long_msg)" > "$r/msg.txt"
  expect "T10-F文件通过" 0 "" "$GIT4AI" -C "$r" commit -F "$r/msg.txt"
}

# T11 非 commit 子命令-透传
echo "T11 非 commit 子命令-透传"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 1
  expect "T11-status透传" 0 "" "$GIT4AI" -C "$r" status --short
}

# T12 多 -m 拼接 + 300 字边界
echo "T12 多 -m 拼接"
{
  r="$(new_repo)"
  stage_file "$r" src/foo.py 1
  printf '%s' "spec" > "$r/src/foo.spec.md"
  "$REAL_GIT" -C "$r" add src/foo.spec.md
  m1="标题：修复边界问题"
  m2="$(long_msg)"
  expect "T12-拼接后合规通过" 0 "" "$GIT4AI" -C "$r" commit -m "$m1" -m "$m2"
}

# ---------- 汇总 ----------

echo ""
echo "========== 结果: $PASS 通过 / $FAIL 失败 =========="
if [ "$FAIL" -gt 0 ]; then
  printf '失败用例: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
