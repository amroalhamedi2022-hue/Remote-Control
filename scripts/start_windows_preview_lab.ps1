# Explicitly opt-in Windows screen sharing laboratory host, NOT a background service.
# Run after inspecting the source; requires Node 22+ and FFmpeg on PATH.
param([switch]$TestPattern)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22+ required.' }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'FFmpeg required. Check ffmpeg -version.' }
Write-Host 'Remote Control v0.5 SCREEN PREVIEW LAB — local-only diagnostic' -ForegroundColor Cyan
Write-Host 'SECURITY: identity private key is kept in a local plaintext test file. Do not expose to Internet.' -ForegroundColor Yellow
Write-Host 'A pairing code must be approved at BOTH ends, then you must type SHARE for this session.'
Write-Host 'Only low-FPS JPEG view is enabled. No input, clipboard, audio, or files.'
Write-Host 'Stop immediately with Ctrl+C. Windows Firewall may require local network access.'
$argsList = @((Join-Path $root 'tools\lan_probe\pair_agent.mjs'), '--listen', '--share-screen')
if ($TestPattern) { $argsList += '--test-pattern' }
& node @argsList
