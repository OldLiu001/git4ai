#!/usr/bin/env bash
# git4ai 安装脚本 — 安装到 /usr/local/bin（默认），保证裸运行也命中
# 真实 git 保持原名（/usr/bin/git），wrapper 用符号链接命名 git 覆盖它。
# wrapper 运行时遍历 PATH 找到第一个非自身的真实 git。
# 安装时校验唯一性：PATH 中只允许出现 wrapper 一个 git，多 git 则报错退出。
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${GIT4AI_HOME:-/usr/local/bin}"
DEST="$DEST_DIR/git"

echo "git4ai 安装目录: $DEST_DIR"

# ---------- 唯一性校验 ----------

# 1. 目标 git 已存在且不是符号链接 → 冲突（可能为系统 git 或其他安装），报错退出
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "✗ $DEST 已存在且不是符号链接（$DEST 指向 $(readlink "$DEST" 2>/dev/null || echo 未知)），拒绝安装。" >&2
  echo "  手动处理：确认该位置无重要 git 后，rm $DEST 再重新运行本脚本" >&2
  exit 1
fi

# 2. PATH 中不允许出现多个 git（只能有 wrapper 一个）
count=0
IFS=: read -r -a _paths <<< "$PATH"
for dir in "${_paths[@]}"; do
  [ -n "$dir" ] || dir="."
  cand="$dir/git"
  [ -x "$cand" ] && [ -f "$cand" ] && count=$((count+1))
done
if [ "$count" -gt 1 ]; then
  echo "✗ PATH 中存在 $count 个 git：" >&2
  IFS=: read -r -a _paths <<< "$PATH"
  for dir in "${_paths[@]}"; do
    [ -n "$dir" ] || dir="."
    cand="$dir/git"
    [ -x "$cand" ] && [ -f "$cand" ] && echo "    $cand" >&2
  done
  echo "  要求：PATH 中只能有 wrapper 一个 git；其余真实 git 应移出 PATH。" >&2
  exit 1
fi

# 3. 真实 git 必须存在（wrapper 运行时遍历 PATH 找到它）
if ! command -v git >/dev/null 2>&1; then
  echo "✗ 找不到任何 git，拒绝安装。" >&2
  exit 1
fi

# ---------- 安装 ----------

# wrapper → 符号链接 $DEST_DIR/git
ln -sf "$ROOT/git4ai" "$DEST"
chmod +x "$ROOT/git4ai"

echo "✓ 已安装: $DEST（符号链接 → $ROOT/git4ai）"
echo "✓ 真实 git 保持原名（/usr/bin/git），由 wrapper 运行时遍历 PATH 解析"

# PATH 校验
case ":$PATH:" in
  *":$DEST_DIR:"*)
    echo "✓ $DEST_DIR 已在 PATH 中，git4ai 立即生效"
    ;;
  *)
    echo "⚠ $DEST_DIR 不在 PATH 中，请将以下行加入 shell 配置（~/.zshrc 等）："
    echo "    export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac

echo ""
echo "验证方式："
echo "  git --version          # 应正常显示 git 版本（透传）"
echo "  git commit -m \"短\"     # 应被 git4ai 拒绝（演示拦截）"
