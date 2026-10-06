# Runs the MCP server against a live app with a hard timeout.
#
# Piping JSON lines straight into `dart run ... serve` is not safe on its own:
# if the server leaks a socket the process never exits and the calling shell
# waits forever. This wrapper always kills the child, so a hang becomes a
# readable timeout instead of a stuck session.
#
# Usage (PowerShell):
#   pwsh tool\probe_mcp.ps1 -Target <vm-service-uri> -Call mcp_get_interactive_elements
param(
  [Parameter(Mandatory = $true)][string]$Target,
  [string]$Call = 'capability',
  [string]$Arguments = '{}',
  [string]$ArgumentsFile,
  [int]$TimeoutSec = 90,
  [switch]$ListTools
)

# -Call a,b arrives as one string from some shells, so split it here rather than
# trusting the binder to produce an array.
$callNames = @($Call -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Nested JSON does not survive a round trip through a command-line argument, so
# a file is the reliable way to pass real tool arguments.
$resolvedArgs = if ($ArgumentsFile) {
  Get-Content -LiteralPath $ArgumentsFile -Raw
} else {
  $Arguments
}

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $root 'packages\flutter-e2e-mcp'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("e2e-probe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$stdinPath = Join-Path $tmp 'in.jsonl'
$stdoutPath = Join-Path $tmp 'out.jsonl'
$stderrPath = Join-Path $tmp 'err.log'

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
$lines.Add('{"jsonrpc":"2.0","method":"notifications/initialized"}')
$id = 2
foreach ($name in $callNames) {
  $lines.Add((@{ jsonrpc = '2.0'; id = $id; method = 'tools/call';
                 params = @{ name = $name; arguments = ($resolvedArgs | ConvertFrom-Json) } } |
    ConvertTo-Json -Compress -Depth 8))
  $id++
}
# Ask the server to shut down cleanly so it releases the app socket.
$lines.Add('{"jsonrpc":"2.0","id":9999,"method":"shutdown","params":{}}')
Set-Content -LiteralPath $stdinPath -Value $lines -Encoding utf8

$argList = @('run', 'bin/server.dart', 'serve', '--connect', $Target, '--verbose')
if ($ListTools) { $argList = @('run', 'bin/server.dart', 'serve', '--list-tools') }

$proc = Start-Process -FilePath 'dart' -ArgumentList $argList -WorkingDirectory $serverDir `
  -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath `
  -RedirectStandardError $stderrPath -PassThru -NoNewWindow

if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
  Write-Output "TIMEOUT after ${TimeoutSec}s - killing server."
  try { $proc.Kill($true) } catch { }
  Start-Sleep -Milliseconds 500
}

if ($ListTools) {
  Get-Content $stdoutPath -EA SilentlyContinue
} else {
  Get-Content $stdoutPath -EA SilentlyContinue | ForEach-Object {
    $r = $_ | ConvertFrom-Json
    if ($r.error) {
      Write-Output ("id={0} ERROR {1}: {2}" -f $r.id, $r.error.code, $r.error.message)
    } else {
      Write-Output ("id={0} OK {1}" -f $r.id, ($r.result | ConvertTo-Json -Compress -Depth 6))
    }
  }
}

$err = Get-Content $stderrPath -EA SilentlyContinue
if ($err) { Write-Output '--- stderr ---'; $err | Select-Object -Last 12 }

Remove-Item -Recurse -Force $tmp -EA SilentlyContinue
