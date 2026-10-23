#!/usr/bin/env bash
# Reproducible Linux/CI bootstrap for the Liquid Fusion Android app.
# Does NOT overwrite an existing app/ directory; no signing credentials required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
command -v flutter >/dev/null || { echo >&2 'Flutter SDK not found on PATH'; exit 2; }
command -v python3 >/dev/null || { echo >&2 'Python3 required for AndroidManifest update'; exit 2; }
[[ ! -e "$APP" ]] || { echo >&2 "Existing $APP: refusing to overwrite"; exit 3; }
flutter create --platforms=android --project-name liquid_remote_control "$APP"
cp "$ROOT/flutter/pubspec.yaml" "$APP/pubspec.yaml"
cp -R "$ROOT/flutter/lib/." "$APP/lib/"
rm -f "$APP/test/widget_test.dart"
cp -R "$ROOT/flutter/test/." "$APP/test/"
python3 - "$APP/android/app/src/main/AndroidManifest.xml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text()
perms=['android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE']
new=''.join(f'    <uses-permission android:name="{x}" />\n' for x in perms if x not in text)
if new:
    pos=text.index('>')+1
    text=text[:pos]+'\n'+new+text[pos:]
    p.write_text(text)
# Prevent Android Auto Backup from restoring encrypted pairing blobs without
# matching device-bound Keystore keys. A reinstall requires a new pairing.
import re
p=Path(sys.argv[1]); text=p.read_text()
m=re.search(r'<application\b[^>]*>', text)
if not m: raise SystemExit('Android application element missing')
tag=m.group(0)
if 'android:allowBackup=' in tag:
    tag=re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', tag)
else:
    tag=tag.replace('<application', '<application android:allowBackup="false"', 1)
p.write_text(text[:m.start()]+tag+text[m.end():])
PY
# flutter_secure_storage >=11 requires Android minSdk 23.
python3 - "$APP" <<'PYANDROID'
from pathlib import Path
import sys
base=Path(sys.argv[1])/'android/app'
for file in (base/'build.gradle.kts',base/'build.gradle'):
    if not file.exists(): continue
    s=file.read_text()
    old='minSdk = flutter.minSdkVersion' if file.suffix=='.kts' else 'minSdkVersion flutter.minSdkVersion'
    new='minSdk = 23' if file.suffix=='.kts' else 'minSdkVersion 23'
    if old not in s:
        raise SystemExit(f'Unexpected Gradle minSdk declaration in {file}; check template manually')
    file.write_text(s.replace(old,new,1))
    break
else: raise SystemExit('Android app Gradle file not found')
PYANDROID
(cd "$APP" && flutter pub get && flutter analyze && flutter test)
echo "Flutter Android scaffold created: $APP"
echo 'To produce a real APK: (cd app && flutter build apk --debug)'
