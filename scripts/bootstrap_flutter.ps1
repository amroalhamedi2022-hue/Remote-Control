# Bootstraps a new Flutter Android+Windows app from supplied Liquid Fusion source.
# Requires Flutter SDK and platform toolchains installed on Windows.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appDir = Join-Path $root 'app'
if (Test-Path $appDir) {
  throw "Refusing to overwrite an existing app folder: $appDir"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK not found on PATH. Install Flutter stable and retry.'
}
Write-Host 'Creating native Android/Windows scaffold...'
flutter create --platforms=android,windows --project-name liquid_remote_control $appDir
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
Copy-Item -Path (Join-Path $root 'flutter\pubspec.yaml') -Destination (Join-Path $appDir 'pubspec.yaml') -Force
Copy-Item -Path (Join-Path $root 'flutter\lib\*') -Destination (Join-Path $appDir 'lib') -Recurse -Force
# The generated template test references its deleted MyApp widget; replace it.
$generatedTest = Join-Path $appDir 'test\widget_test.dart'
if (Test-Path $generatedTest) { Remove-Item $generatedTest -Force }
Copy-Item -Path (Join-Path $root 'flutter\test\*') -Destination (Join-Path $appDir 'test') -Recurse -Force
# Replace only generated native launcher artwork (Android + Windows).
foreach ($density in @('mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi')) {
  $source = Join-Path $root ("flutter\assets\icons\ic_launcher_" + $density + ".png")
  $dest = Join-Path $appDir ("android\app\src\main\res\mipmap-" + $density + "\ic_launcher.png")
  if (-not (Test-Path $source) -or -not (Test-Path (Split-Path $dest))) {
    throw "Missing Remote Control launcher image or destination: $source -> $dest"
  }
  Copy-Item -Path $source -Destination $dest -Force
}
$windowsIcon = Join-Path $appDir 'windows\runner\resources\app_icon.ico'
if (-not (Test-Path (Split-Path $windowsIcon))) { throw 'Missing Windows runner icon directory' }
Copy-Item -Path (Join-Path $root 'flutter\assets\icons\app_icon.ico') -Destination $windowsIcon -Force
$manifestPath = Join-Path $appDir 'android\app\src\main\AndroidManifest.xml'
$manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8
if ($manifest -notmatch 'android.permission.INTERNET') {
  $permissions = "`n    <uses-permission android:name=`"android.permission.INTERNET`" />`n    <uses-permission android:name=`"android.permission.ACCESS_NETWORK_STATE`" />"
  $manifest = [regex]::Replace($manifest, '<manifest\b[^>]*>', '$0' + $permissions, 1)
  [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
}
# Device-bound Keystore keys cannot be restored after reinstall; never backup pairing blobs.
if ($manifest -match 'android:allowBackup=') {
  $manifest = [regex]::Replace($manifest, 'android:allowBackup="[^"]*"', 'android:allowBackup="false"', 1)
} else {
  $manifest = [regex]::Replace($manifest, '<application\b', '<application android:allowBackup="false"', 1)
}
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
# flutter_secure_storage >=11 requires minSdk 23; do not rely on Flutter default.
$gradleKts = Join-Path $appDir 'android\app\build.gradle.kts'
$gradleGroovy = Join-Path $appDir 'android\app\build.gradle'
if (Test-Path $gradleKts) {
  $gradleContents = Get-Content -Path $gradleKts -Raw -Encoding UTF8
  if (-not $gradleContents.Contains('minSdk = flutter.minSdkVersion')) { throw 'Unknown Kotlin Gradle minSdk template' }
  $gradleContents = $gradleContents.Replace('minSdk = flutter.minSdkVersion','minSdk = 23')
  [System.IO.File]::WriteAllText($gradleKts, $gradleContents, [System.Text.UTF8Encoding]::new($false))
} elseif (Test-Path $gradleGroovy) {
  $gradleContents = Get-Content -Path $gradleGroovy -Raw -Encoding UTF8
  if (-not $gradleContents.Contains('minSdkVersion flutter.minSdkVersion')) { throw 'Unknown Groovy Gradle minSdk template' }
  $gradleContents = $gradleContents.Replace('minSdkVersion flutter.minSdkVersion','minSdkVersion 23')
  [System.IO.File]::WriteAllText($gradleGroovy, $gradleContents, [System.Text.UTF8Encoding]::new($false))
} else { throw 'Android app Gradle file not found' }
Set-Location $appDir
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed. Fix analyzer findings before release.' }
Write-Host 'Flutter scaffold created. Use: flutter run -d windows (or flutter run -d <android-device>)'
