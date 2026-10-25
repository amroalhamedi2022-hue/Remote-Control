// Validates scaffold automation structure with a FAKE Flutter binary.
// Does NOT test Flutter source compilation or produce an APK.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root=resolve(fileURLToPath(new URL('../../',import.meta.url)));
test('Linux bootstrap copies Liquid Fusion source, writes permissions and minSdk=23, refuses overwrite',
  {skip:process.platform==='win32'},()=>{
  const tmp=mkdtempSync(join(tmpdir(),'liquid-flutter-scaffold-'));
  try {
    mkdirSync(join(tmp,'scripts'),{recursive:true});
    cpSync(join(root,'scripts','bootstrap_flutter.sh'),join(tmp,'scripts','bootstrap_flutter.sh'));
    cpSync(join(root,'flutter'),join(tmp,'flutter'),{recursive:true});
    // The bootstrap now requires the versioned native SAF overlay as input.
    cpSync(join(root,'android_overlay'),join(tmp,'android_overlay'),{recursive:true});
    const bin=join(tmp,'bin');mkdirSync(bin);
    const flutterStub=join(bin,'flutter');
    writeFileSync(flutterStub,`#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1}" == 'create' ]]; then
  app="\${!#}"
  mkdir -p "$app/android/app/src/main" "$app/android/app" "$app/lib" "$app/test"
  # Flutter's real Android template includes density-specific mipmap directories.
  for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    mkdir -p "$app/android/app/src/main/res/mipmap-$density"
  done
  cat > "$app/android/app/src/main/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="Lab" /></manifest>
MANIFEST
  echo 'android { defaultConfig { minSdk = flutter.minSdkVersion } }' > "$app/android/app/build.gradle.kts"
  echo 'template' > "$app/test/widget_test.dart"
fi
`,{mode:0o755});
    const env={...process.env,PATH:`${bin}:${process.env.PATH}`};
    execFileSync('bash',[join(tmp,'scripts','bootstrap_flutter.sh')],{env,stdio:'pipe'});
    const manifest=readFileSync(join(tmp,'app/android/app/src/main/AndroidManifest.xml'),'utf8');
    const gradle=readFileSync(join(tmp,'app/android/app/build.gradle.kts'),'utf8');
    assert.match(manifest,/android.permission.INTERNET/);
    assert.match(manifest,/android.permission.ACCESS_NETWORK_STATE/);
    assert.match(manifest,/android:allowBackup="false"/);
    assert.match(gradle,/minSdk = 23/);
    assert.ok(existsSync(join(tmp,'app/lib/security/pairing_lab.dart')));
    assert.ok(existsSync(join(tmp,'app/android/app/src/main/kotlin/com/example/liquid_remote_control/MainActivity.kt')));
    assert.ok(existsSync(join(tmp,'app/android/app/src/main/kotlin/com/example/liquid_remote_control/SafReceivePolicy.kt')));
    assert.ok(existsSync(join(tmp,'app/test/liquid_ui_smoke_test.dart')));
    assert.ok(!existsSync(join(tmp,'app/test/widget_test.dart')));
    assert.throws(()=>execFileSync('bash',[join(tmp,'scripts/bootstrap_flutter.sh')],{env,stdio:'pipe'}),/already|Existing/);
  } finally {rmSync(tmp,{recursive:true,force:true});}
});
