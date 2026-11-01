#!/usr/bin/env bash
# Fork only: re-packs the upstream Android APK with this fork's Java code and manifest (direct-launch shortcuts),
# keeping upstream's native libraries, game tables and icon as they are. No NDK, no ROM, no game build: the fork
# follows upstream's release and only the Java side is its own.
#
#   tools/android/repack.sh <upstream.apk> <out.apk> [versionCode]
#
# Env: ANDROID_SDK (build-tools;34.0.0 and platforms;android-34), SSR_ANDROID_KEY (signing key file, made on the
# first run), SDL_SRC (the SDL2-2.32.10 source folder, for SDL's Java code).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$HERE"
UP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
VCODE="${3:-}"
SDK="${ANDROID_SDK:?ANDROID_SDK}"
KEY="${SSR_ANDROID_KEY:?SSR_ANDROID_KEY}"
SDL="${SDL_SRC:?SDL_SRC}"
BT="$SDK/build-tools/34.0.0"
JAR="$SDK/platforms/android-34/android.jar"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/up" "$W/res" "$W/classes" "$W/dex"
unzip -q "$UP" -d "$W/up"

# Upstream's icon, as it is (compiled resources: aapt2 wants them back under res/mipmap-<density>/).
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    mkdir -p "$W/res/mipmap-$d"
    cp "$W/up/res/mipmap-$d-v4/ic_launcher.png" "$W/up/res/mipmap-$d-v4/ic_launcher_background.png" "$W/res/mipmap-$d/"
done
mkdir -p "$W/res/mipmap-anydpi-v26"
cat > "$W/res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@android:color/transparent" />
</adaptive-icon>
XML

cp tools/android/allgames/AndroidManifest.xml "$W/AndroidManifest.xml"
[ -z "$VCODE" ] || sed -i.bak "s/android:versionCode=\"[0-9]*\"/android:versionCode=\"$VCODE\"/" "$W/AndroidManifest.xml"
"$BT/aapt2" compile --dir "$W/res" -o "$W/res.zip"
"$BT/aapt2" link -o "$W/base.apk" -I "$JAR" --manifest "$W/AndroidManifest.xml" \
    --min-sdk-version 24 --target-sdk-version 34 "$W/res.zip"
javac -nowarn --release 11 -cp "$JAR" -d "$W/classes" \
    $(find "$SDL/android-project/app/src/main/java" tools/android/allgames/java -name '*.java') 2>&1 | grep -v '^Note:' || true
for c in GameActivity PinShortcutActivity; do
    [ -f "$W/classes/io/github/mamesj/pokemonds/$c.class" ] || { echo "error: $c did not compile" >&2; exit 1; }
done
"$BT/d8" --release --min-api 24 --lib "$JAR" --output "$W/dex" $(find "$W/classes" -name '*.class')
(cd "$W/dex" && zip -q -X "$W/base.apk" classes.dex)

# Upstream's native libraries and assets go in untouched.
FILES=()
while IFS= read -r f; do FILES+=("$f=$W/up/$f"); done < <(cd "$W/up" && find lib assets -type f | sort)
python3 - "$W/base.apk" "$KEY" "$OUT" "${FILES[@]}" <<'PY'
import sys
sys.path.insert(0, 'tools/android')
import apk
skeleton, key, out = sys.argv[1:4]
files = [tuple(a.split('=', 1)) for a in sys.argv[4:]]
apk.build_files(skeleton, files, key, out)
PY
"$BT/apksigner" verify --verbose "$OUT" | head -3
ls -l "$OUT"
