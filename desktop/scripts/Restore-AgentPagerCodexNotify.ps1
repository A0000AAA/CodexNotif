[CmdletBinding()]
param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot '..\app\bin\Release\net8.0-windows\publish\AgentPager.exe'),
    [string]$ConfigPath = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\config.toml'),
    [string]$StatePath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AgentPager\codex-notify-state.json')
)

$ErrorActionPreference = 'Stop'

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$resolvedConfig = [IO.Path]::GetFullPath($ConfigPath)
$resolvedState = [IO.Path]::GetFullPath($StatePath)

$process = Start-Process `
    -FilePath $resolvedExecutable `
    -ArgumentList @(
        '--restore-codex-notify',
        ('"{0}"' -f $resolvedConfig),
        ('"{0}"' -f $resolvedState)
    ) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

if ($process.ExitCode -eq 2) {
    throw 'Codex notify changed after AgentPager installation. Restore was refused to protect the newer config.'
}

if ($process.ExitCode -ne 0) {
    throw "AgentPager Codex notify restore failed with exit code $($process.ExitCode)."
}

Write-Host 'Codex notify was restored to its pre-AgentPager state.' -ForegroundColor Green
Write-Host "Config: $resolvedConfig"
