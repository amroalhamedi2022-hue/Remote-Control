# View-only H.264/MPEG-TS laboratory; NOT production remote desktop.
# Runs in foreground and ALWAYS asks for BOTH pairing-code consent and H264 sharing consent.
param(
  [switch]$TestPattern,
  [switch]$EnableFlutterJpegView,
  [ValidateSet('libx264','h264_nvenc')][string]$Encoder='libx264'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22+ required' }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'FFmpeg required on PATH' }
Write-Host 'Liquid Fusion H.264 ENCRYPTED VIDEO LAB - not production; view only' -ForegroundColor Cyan
Write-Host 'Security: Node agent stores identity keys as local lab files, not platform-secure storage.' -ForegroundColor Yellow
Write-Host 'No remote input, audio, clipboard, or unattended access. Ctrl+C stops sharing.'
Write-Host 'The host now announces itself over UDP 43827 and responds to PING on TCP 43828.'
Write-Host 'Pairing remains separate on TCP 43829; Windows private-network firewall may prompt.'
Write-Host 'You must compare pairing codes on both devices and type H264 for EVERY screen session.'
$argsList = @((Join-Path $root 'tools\lan_probe\pair_agent.mjs'), '--listen', '--share-h264', "--encoder=$Encoder")
if ($TestPattern) { $argsList += '--test-pattern' }
# Flutter experimental screen preview currently consumes JPEG frames (STREAM_START),
# not H.264 (H264_START). Keep this path opt-in, with its own SHARE confirmation.
if ($EnableFlutterJpegView) {
  Write-Host 'Experimental Flutter MJPEG view enabled; every request needs SHARE approval.' -ForegroundColor Yellow
  $argsList += '--share-screen'
}
& node @argsList
