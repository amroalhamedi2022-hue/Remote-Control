# Viewing node: Windows/Mac/Linux with Node 22+ and FFplay installed.
# The remote host MUST separately authorize the pairing code and H264 sharing.
param(
  [Parameter(Mandatory=$true)][string]$HostIp,
  [ValidateRange(1,10)][int]$Seconds = 3,
  [string]$SaveAs = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22+ is required' }
if (-not (Get-Command ffplay -ErrorAction SilentlyContinue)) { throw 'FFplay is required' }
if ($HostIp -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') { throw 'Enter the LAN IPv4 address, without a port' }
Write-Host 'Liquid Fusion • experimental live H.264 view-only client' -ForegroundColor Cyan
Write-Host 'Use only on a trusted local network. Both devices must approve the pairing code.'
Write-Host 'The Windows host must approve H264 separately. No mouse/keyboard commands are sent.'
$argsList = @((Join-Path $root 'tools\lan_probe\pair_agent.mjs'), "--connect=$HostIp", '--watch-h264', "--max-seconds=$Seconds")
if ($SaveAs) {
  if (-not $SaveAs.EndsWith('.ts', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Saved video needs a .ts filename' }
  if (Test-Path $SaveAs) { throw 'Output already exists; refusing to overwrite' }
  $argsList += "--output=$SaveAs"
}
& node @argsList
if ($LASTEXITCODE -ne 0) { throw "Viewer failed with exit code $LASTEXITCODE" }
