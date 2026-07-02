#!/bin/bash
set -euo pipefail

# YunPat-Ai macOS App 打包脚本
# 用途: 从 SPM 可执行文件组装出可分发的 .app bundle
# 产出: .build/YunPatAi.app

APP_NAME="YunPatAi"
BUNDLE_ID="com.yunpat.ai"
VERSION="0.1.0"
BUILD_NUM="1"
COPYRIGHT="Copyright © 2026 YunPat. All rights reserved."

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"

echo "══════════════════════════════════════"
echo "  YunPat-Ai App 打包"
echo "  Version: $VERSION ($BUILD_NUM)"
echo "══════════════════════════════════════"

# 1. Release 编译
echo ""
echo "[1/6] Release 编译..."
cd "$PROJECT_DIR"
swift build -c release --product "$APP_NAME"

BINARY="$RELEASE_DIR/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "✗ 编译失败，未找到二进制: $BINARY"
    exit 1
fi
echo "  ✅ $BINARY ($(du -h "$BINARY" | cut -f1))"

# 2. 创建 .app bundle 目录结构
echo ""
echo "[2/6] 创建 App Bundle 目录结构..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
echo "  ✅ $APP_DIR"

# 3. 复制可执行文件
echo ""
echo "[3/6] 复制可执行文件..."
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
echo "  ✅ $MACOS_DIR/$APP_NAME"

# 4. 编译 Assets.xcassets → Assets.car
echo ""
echo "[4/6] 编译 Assets.xcassets..."
ASSETS_DIR="$PROJECT_DIR/App/Assets.xcassets"
ASSETS_CAR="$RES_DIR/Assets.car"

if [ -f "/usr/bin/actool" ]; then
    # Xcode 安装时可用
    /usr/bin/actool "$ASSETS_DIR" \
        --compile "$RES_DIR" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$BUILD_DIR/partial-info.plist" \
        2>/dev/null

    if [ -f "$ASSETS_CAR" ]; then
        echo "  ✅ Assets.car 已编译"
    else
        echo "  ⚠️  actool 未生成 Assets.car，尝试直接复制图标"
        cp "$PROJECT_DIR/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$RES_DIR/AppIcon.png" 2>/dev/null || true
    fi
else
    echo "  ⚠️  actool 不可用（需安装 Xcode），使用直接图标复制"
    cp "$PROJECT_DIR/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$RES_DIR/AppIcon.png" 2>/dev/null || true
fi

# 5. 写入 PkgInfo
echo ""
echo "[5/6] 写入 Info.plist 和 PkgInfo..."
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 合并 Info.plist（含 actool 生成的图标信息）
INFOPLIST="$PROJECT_DIR/App/Info.plist"
PARTIAL_INFO="$BUILD_DIR/partial-info.plist"

if [ -f "$PARTIAL_INFO" ]; then
    # 合并 partial info plist（图标信息）到主 Info.plist
    /usr/libexec/PlistBuddy -c "Merge $PARTIAL_INFO" "$INFOPLIST" 2>/dev/null || true
fi

cp "$INFOPLIST" "$CONTENTS_DIR/Info.plist"
echo "  ✅ Info.plist + PkgInfo"

# 6. 移除 .DS_Store
echo ""
echo "[6/6] 清理..."
find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# 完成
echo ""
echo "══════════════════════════════════════"
echo "  🎉 打包完成!"
echo ""
echo "  App:     $APP_DIR"
echo "  大小:    $(du -sh "$APP_DIR" | cut -f1)"
echo "  架构:    $(file "$MACOS_DIR/$APP_NAME" | cut -d: -f2-)"
echo ""
echo "  运行:    open $APP_DIR"
echo ""
echo "  如需代码签名:"
echo "    codesign --deep --force --verify --verbose \\"
echo "      --sign 'Developer ID Application: ...' \\"
echo "      --entitlements $PROJECT_DIR/App/App.entitlements \\"
echo "      --options runtime \\"
echo "      $APP_DIR"
echo ""
echo "  如需 DMG 打包:"
echo "    hdiutil create -volname YunPatAi -srcfolder $APP_DIR \\"
echo "      -ov -format UDZO $BUILD_DIR/YunPatAi-$VERSION.dmg"
echo "══════════════════════════════════════"
