#!/bin/bash
# pre-commit hook: SwiftLint + SwiftFormat + 构建检查
# 安装: ln -sf ../../scripts/pre-commit.sh .git/hooks/pre-commit
# 用法: pre-commit.sh [--fast]    # --fast 仅构建 2 个关键包

set -e

FAST=false
if [[ "$1" == "--fast" ]]; then
  FAST=true
fi

echo "🔍 SwiftLint --strict..."
if ! swiftlint --strict 2>/dev/null; then
  echo "❌ SwiftLint 违规，请修复后提交"
  exit 1
fi

echo "🔍 SwiftFormat..."
if command -v swift format &>/dev/null; then
  # 只检查 staged 的 .swift 文件
  for f in $(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$'); do
    if [ -f "$f" ]; then
      swift format "$f" >/dev/null 2>&1 || true
    fi
  done
fi

if [ "$FAST" = true ]; then
  echo "🔍 (快速模式) 关键包构建..."
  swift build --package-path Packages/YunPatNetworking 2>/dev/null || {
    echo "❌ YunPatNetworking 构建失败"
    exit 1
  }
  swift build --package-path Packages/YunPatCore 2>/dev/null || {
    echo "❌ YunPatCore 构建失败"
    exit 1
  }
else
  echo "🔍 全量包构建..."
  # 6 个包逐个构建，失败即退出
  for pkg in YunPatNetworking YunPatCore PatentClient YunPatPlugins YunPatDesktop YunPatSandbox; do
    echo "  构建 $pkg..."
    swift build --package-path "Packages/$pkg" 2>/dev/null || {
      echo "❌ $pkg 构建失败"
      exit 1
    }
  done
fi

echo "✅ 代码质量检查通过"
