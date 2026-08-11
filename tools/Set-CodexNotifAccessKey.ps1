[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$UseClipboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CodexNotifAccessKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -lt 32) {
        return $false
    }

    foreach ($character in $Value.ToCharArray()) {
        if ([char]::IsWhiteSpace($character) -or [char]::IsControl($character)) {
            return $false
        }
    }

    return $true
}

if ($UseClipboard) {
    $key = (Get-Clipboard -Raw).TrimEnd("`r", "`n")
}
else {
    $bytes = New-Object byte[] 32
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    $key = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

if (-not (Test-CodexNotifAccessKey -Value $key)) {
    throw '访问密钥无效：必须至少 32 个字符，且不能包含空白或控制字符。'
}

if ($PSCmdlet.ShouldProcess(
        '当前 Windows 用户',
        '设置 CODEXNOTIF_ACCESS_KEY 并复制到剪贴板')) {
    [Environment]::SetEnvironmentVariable(
        'CODEXNOTIF_ACCESS_KEY',
        $key,
        'User')
    Set-Clipboard -Value $key
    Write-Host '访问密钥已写入 Windows 用户环境变量并复制到剪贴板。密钥内容未输出。'
    Write-Host '请将剪贴板内容粘贴到服务器环境变量，然后重启服务器、CodexNotif 和 Codex。'
}
