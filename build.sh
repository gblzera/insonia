#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="Insônia.app"
ZIP="Insonia.zip"
EXE="Insonia"

echo "▸ Compilando…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    # Universal — precisa de Xcode completo (ex.: no runner do GitHub Actions).
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXE"
else
    # Só Command Line Tools instaladas: compila pra arquitetura desta máquina.
    echo "  (sem Xcode completo — compilando só pra arquitetura nativa)"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/$EXE"
fi
echo "  arquiteturas: $(lipo -archs "$BIN")"

echo "▸ Montando $APP…"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp Info.plist "$APP/Contents/Info.plist"

echo "▸ Assinando (ad-hoc, pra rodar local sem aviso)…"
codesign --force --sign - "$APP" 2>/dev/null || echo "  (codesign pulado)"

echo "▸ Compactando para a Release ($ZIP)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo ""
echo "✅ Pronto:"
echo "   App:  $(pwd)/$APP        (rode com: open \"$APP\")"
echo "   Zip:  $(pwd)/$ZIP   ← este arquivo é o que sobe pro GitHub Releases"
