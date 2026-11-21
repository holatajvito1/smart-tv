#!/bin/bash
# Builds launcher/android into build/smarttv-home.apk without Gradle:
# aapt2 (resources + manifest) -> javac -> d8 (dex) -> zipalign -> apksigner.
# The web UI in ../web is bundled as assets/www.
set -euo pipefail
cd "$(dirname "$0")"

SDK=$HOME/.local/android/sdk
BT=$SDK/build-tools/34.0.0
ANDROID_JAR=$SDK/platforms/android-30/android.jar
export JAVA_HOME=${JAVA_HOME:-$(ls -d "$HOME"/.local/jdk/*/Contents/Home | head -1)}
export PATH="$JAVA_HOME/bin:$BT:$PATH"
KEYSTORE=debug.keystore   # keep this file: updates must be signed with the same key

rm -rf build && mkdir -p build/gen build/classes build/assets/www build/dex

# Web UI -> assets (skip macOS junk)
rsync -a --exclude '.DS_Store' ../web/ build/assets/www/

aapt2 compile --dir res -o build/res.zip
aapt2 link -o build/unaligned.apk \
  -I "$ANDROID_JAR" \
  --manifest AndroidManifest.xml \
  -A build/assets \
  --java build/gen \
  --min-sdk-version 26 --target-sdk-version 30 \
  -0 jpg -0 png -0 woff2 -0 wav \
  build/res.zip

javac --release 8 -Xlint:-options -encoding UTF-8 \
  -classpath "$ANDROID_JAR" -d build/classes \
  $(find src build/gen -name '*.java')

d8 --release --min-api 26 --lib "$ANDROID_JAR" --output build/dex $(find build/classes -name '*.class')
(cd build/dex && zip -q -u ../unaligned.apk classes.dex)

zipalign -f -p 4 build/unaligned.apk build/aligned.apk

if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
    -alias home -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=smart-tv home" >/dev/null 2>&1
fi
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --ks-key-alias home \
  --out build/smarttv-home.apk build/aligned.apk
apksigner verify build/smarttv-home.apk
ls -lh build/smarttv-home.apk | awk '{print "Built", $NF, $5}'
