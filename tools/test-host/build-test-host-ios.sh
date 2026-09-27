#!/bin/sh
# Builds PsdkTests.app, a minimal iOS host that runs one released Pokemon
# SDK game on the PSDK core of one Ruby.
#
# There is no Xcode project. An iOS app bundle is a directory with a
# Mach-O binary, an Info.plist and resources, so this script assembles
# one by hand. The link line is the one README.md gives to a host.
#
# Usage:
#   tools/test-host/build-test-host-ios.sh [--ruby 3.0]
#
# Prerequisite: make SDK=iphonesimulator
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/tools/test-host"

SDK=iphonesimulator
ARCH=arm64
MIN_OS=26.0
RUBY=3.0

while [ "$#" -gt 0 ]
do
    case "$1" in
        --ruby)
            RUBY="$2"
            shift 2
            ;;
        *)
            echo "build-test-host-ios: unknown argument $1" >&2
            exit 2
            ;;
    esac
done

NN="$(echo "$RUBY" | tr -d .)"
LIB="$ROOT/out/$SDK/libpsdk$NN.a"
SUPPORT="$ROOT/out/support/$RUBY"
ANGLE="$ROOT/downloads/angle/$SDK/lib"
if [ ! -f "$LIB" ] || [ ! -d "$SUPPORT" ]
then
    echo "build-test-host-ios: $LIB or $SUPPORT missing. Run: make SDK=$SDK RUBIES=$NN" >&2
    exit 1
fi

OUT="$ROOT/build/test-host/$NN"
APP="$OUT/PsdkTests.app"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK" -f clang)"
FLAGS="-isysroot $SYSROOT -target $ARCH-apple-ios$MIN_OS-simulator -arch $ARCH"

rm -rf "$OUT"
mkdir -p "$APP"

echo "[psdk-host] Compiling and linking with Ruby $RUBY..."
"$CC" $FLAGS -fobjc-arc -O2 -I"$ROOT/src" -c "$HERE/host.m" -o "$OUT/host.o"
"$CC" $FLAGS -o "$APP/PsdkTests" "$OUT/host.o" "$LIB" \
    -L"$ANGLE" -lANGLE_static -lEGL_static -lGLESv2_static \
    -lc++ -lz -lbz2 -liconv \
    -framework Foundation -framework UIKit -framework CoreFoundation \
    -framework CoreGraphics -framework CoreVideo -framework CoreAudio \
    -framework AudioToolbox -framework AVFoundation -framework Metal \
    -framework QuartzCore -framework GameController -framework CoreMotion \
    -framework IOSurface \
    -weak_framework CoreBluetooth -weak_framework CoreHaptics

cp "$HERE/Info.plist" "$APP/Info.plist"
cp "$HERE/prelude.rb" "$APP/prelude.rb"
cp -R "$SUPPORT" "$APP/support"

# An unsigned bundle installs on some simulator runtimes and not on
# others. An ad-hoc signature works everywhere and needs no identity.
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "[psdk-host] Done: $APP"
