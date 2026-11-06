#!/usr/bin/env bash
# 生成 Xcode 27 原生工程（BrandMeister.xcodeproj）
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    cat >&2 <<'EOF'
未找到 XcodeGen。

安装：
    brew install xcodegen

或者不用它 —— 直接用 Xcode 27 打开 Package.swift，同样可以编译、断点调试，
只是产物是命令行可执行文件，不是 .app 包。
EOF
    exit 1
fi

echo "==> 生成工程"
xcodegen generate --spec project.yml

echo "==> 完成：BrandMeister.xcodeproj"
echo "    App target : BrandMeister"
echo "    CLI target : bmwatch"
echo "    库 target  : BrandMeisterKit（静态库）"
