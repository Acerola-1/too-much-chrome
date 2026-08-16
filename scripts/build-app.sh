#!/bin/zsh
# ============================================================
# Too Much Chrome — 打包 / 签名 / 公证流水线
#
# 用法：
#   scripts/build-app.sh dev        开发自用：组装 .app（adhoc 签名）并启动
#   scripts/build-app.sh release    分发构建：Developer ID 签名（硬运行时 + 安全时间戳）
#   scripts/build-app.sh notarize   在 release 基础上：提交 Apple 公证 → staple 票据
#   scripts/build-app.sh dmg        在公证基础上：生成并公证 DMG（对外分发物）
#
# 所有配置可用环境变量覆盖（CI 注入用）；未提供 Developer ID 证书时
# 自动回退 adhoc 签名并跳过公证。
#
# 本地首次公证前需一次性存储凭证：
#   xcrun notarytool store-credentials tmc-notary \
#     --apple-id "你的AppleID" --team-id "VTQ6S5M4K3" --password "app专用密码"
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"

# ---- 配置（环境变量可覆盖）----
APP_NAME="TooMuchChrome"
DISPLAY_NAME="Too Much Chrome"
BUNDLE_ID="${BUNDLE_ID:-com.acerola.too-much-chrome}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: jiliang mo (VTQ6S5M4K3)}"
TEAM_ID="${TEAM_ID:-VTQ6S5M4K3}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tmc-notary}"
# CI 可用显式凭证替代 keychain profile
APPLE_ID="${APPLE_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"
# ---------------

APP=".build/${APP_NAME}.app"

echo "==> Release 构建 ${APP_NAME} ${VERSION} (${BUILD})"
swift build -c release --product "$APP_NAME"

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
EOF

# ---- 签名 ----
# 开发模式固定 adhoc；无证书环境（CI 未注入）同样回退 adhoc 并跳过公证
SKIP_NOTARY=0
SIGN_AVAILABLE=0
if [[ -n "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
  SIGN_AVAILABLE=1
fi

if [[ "$MODE" == "dev" || "$SIGN_AVAILABLE" -eq 0 ]]; then
  echo "==> adhoc 签名"
  codesign --force --sign - --options runtime "$APP"
  if [[ "$MODE" == "dev" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP"
    exit 0
  fi
  echo "⚠ 未找到 Developer ID 证书，已 adhoc 签名并跳过公证"
  SKIP_NOTARY=1
else
  echo "==> Developer ID 签名（hardened runtime + secure timestamp）"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  spctl --assess --type execute -v "$APP" || true
fi

if [[ "$MODE" == "release" ]]; then
  echo "✓ 完成：$APP"
  exit 0
fi

# ---- 公证 ----
if [[ "$MODE" == "notarize" || "$MODE" == "dmg" ]]; then
  if [[ "$SKIP_NOTARY" -eq 1 ]]; then
    echo "⚠ 跳过公证（无签名证书）"
  else
    NOTARY_ARGS=()
    if [[ -n "$APPLE_ID" && -n "$NOTARY_PASSWORD" ]]; then
      NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$TEAM_ID")
    else
      if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "✗ 未找到公证凭证 profile「${NOTARY_PROFILE}」。首次使用请先执行："
        echo "  xcrun notarytool store-credentials ${NOTARY_PROFILE} \\"
        echo "    --apple-id \"你的AppleID\" --team-id \"${TEAM_ID}\" --password \"app专用密码\""
        exit 1
      fi
      NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    fi

    ZIP=".build/${APP_NAME}-${VERSION}.zip"
    echo "==> 提交公证（${ZIP}）"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" "${NOTARY_ARGS[@]}" --wait

    echo "==> Staple 公证票据到 .app"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute -v "$APP"
  fi
fi

# ---- DMG ----
if [[ "$MODE" == "dmg" ]]; then
  DMG=".build/${APP_NAME}-${VERSION}.dmg"
  echo "==> 生成 DMG（${DMG}）"
  rm -f "$DMG"
  hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
  if [[ "$SKIP_NOTARY" -eq 0 ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
  fi
  echo "✓ 分发物就绪：$DMG"
fi
