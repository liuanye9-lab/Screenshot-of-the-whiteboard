#!/bin/bash
# SnapLeaf 构建脚本 — 构建 Swift 可执行文件并打包为 .app bundle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="SnapLeaf"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

# 默认快捷键（与 HotkeySettings.defaults 保持一致）
SHORTCUT_REGION="⌥E"
SHORTCUT_FULLSCREEN="⌥Q"
SHORTCUT_SCROLL="⌥W"
SHORTCUT_ANNOTATE="⌥A"
SHORTCUT_QUIT="⌘Q"

echo "==> 清理旧 bundle ..."
rm -rf "$APP_BUNDLE"

echo "==> 编译 $APP_NAME (arm64 release) ..."
swift build -c release --arch arm64

echo "==> 创建 .app bundle ..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 复制 Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"

# 复制资源（图标、图标集等）
if [ -d "Sources/Resources" ]; then
    cp -R Sources/Resources/* "$APP_BUNDLE/Contents/Resources/"
fi

# 修正可执行文件权限
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 签名（ad-hoc，适合本地分发与测试）
echo "==> 签名 bundle ..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# 简单校验
if [ -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]; then
    echo "==> 构建成功: $APP_BUNDLE"
else
    echo "==> 构建失败: 可执行文件未生成"
    exit 1
fi

echo ""
echo "使用方法:"
echo "  1. 双击 $APP_BUNDLE 启动"
echo "  2. 菜单栏会出现相机图标"
echo "  3. 首次启动需要授权「屏幕录制」和「辅助功能」权限"
echo ""
echo "默认快捷键:"
echo "  $SHORTCUT_REGION    局部截图"
echo "  $SHORTCUT_FULLSCREEN    全屏截图"
echo "  $SHORTCUT_SCROLL    长图截图"
echo "  $SHORTCUT_ANNOTATE    标注上次截图"
echo "  $SHORTCUT_QUIT    退出"
echo ""
echo "可在 菜单栏 > 设置 中自定义快捷键。"
