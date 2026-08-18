#!/usr/bin/env bash
# git4ai 安装脚本 — 安装到 ~/.local/bin/git（PATH 前置时生效）
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${GIT4AI_HOME:-$HOME/.local/bin}"
DEST="$DEST_DIR/git"

mkdir -p "$DEST_DIR"

# 已存在且不是符号链接 → 拒绝覆盖（保护已有 git 安装）
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "✗ $DEST 已存在且不是符号链接，拒绝覆盖。" >&2
  echo "  手动处理：mv $DEST $DEST.git.bak 后重新运行本脚本" >&2
  exit 1
fi

cp "$ROOT/git4ai" "$DEST"
chmod +x "$DEST"

echo "✓ 已安装: $DEST"
echo "  真实 git 由 wrapper 运行时自动解析（跳过自身），无需配置。"

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
