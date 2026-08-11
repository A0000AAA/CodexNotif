param(
    [ValidateSet('Worktree', 'Index', 'History')]
    [string]$Scope = 'Worktree'
)

$ErrorActionPreference = 'Stop'

$repository = (& git rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repository)) {
    throw '必须在 Git 仓库中运行。'
}

$findings = [Collections.Generic.List[object]]::new()
$binaryExtensions = @(
    '.gif', '.ico', '.jpeg', '.jpg', '.jar', '.png', '.wav', '.webp'
)
$blockedPathPattern = '(?i)(^|/)(\.env($|\.)|local\.properties$|[^/]+\.(pem|key|pfx|p12|jks|keystore|cer|crt)$|bin/|obj/|target/|build/|\.dart_tool/|\.idea/|\.vs/)'
$lineRules = [ordered]@{
    personal_namespace = '(?i)top\.aiot2008|aiot2008'
    old_android_package = '(?i)com\.example\.app|package:app/'
    old_server_port = '(?<!\d)18081(?!\d)'
    private_key = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    windows_user_path = '(?i)[A-Z]:\\Users\\[^\\\s]+'
    linux_home_path = '(?i)/(home|root)/[^/\s]+'
    production_path = '(?i)/www/wwwroot/(?!<DEPLOY_DIR>)'
}
$emailPattern = '(?i)\b[A-Z0-9._%+-]+@([A-Z0-9.-]+\.[A-Z]{2,})\b'
$ipv4Pattern = '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)'
$urlPattern = '(?i)https?://[A-Z0-9.-]+'
$longSecretPattern = '(?<![A-Za-z0-9])(?:[A-Fa-f0-9]{64}|(?=[A-Za-z0-9+_=-]{40,}(?![A-Za-z0-9]))(?=[A-Za-z0-9+_=-]*[A-Z])(?=[A-Za-z0-9+_=-]*[a-z])(?=[A-Za-z0-9+_=-]*[0-9])[A-Za-z0-9+_=-]{40,})(?![A-Za-z0-9])'
$allowedUrlHosts = @(
    '127.0.0.1',
    'localhost',
    'aka.ms',
    'api.flutter.dev',
    'api.nuget.org',
    'dart.dev',
    'developer.android.com',
    'developer.apple.com',
    'developers.openai.com',
    'docs.flutter.dev',
    'docs.gradle.org',
    'docs.microsoft.com',
    'flutter.dev',
    'forums.swift.org',
    'fsf.org',
    'graph.microsoft.com',
    'github.com',
    'go.microsoft.com',
    'h2database.com',
    'kotlinlang.org',
    'learn.microsoft.com',
    'login.microsoftonline.com',
    'maven.apache.org',
    'opensource.org',
    'platform.openai.com',
    'pub.dev',
    'schema.org',
    'schemas.android.com',
    'schemas.microsoft.com',
    'services.gradle.org',
    'spdx.org',
    'spring.io',
    'www.gnu.org',
    'www.apple.com',
    'www.w3.org'
)

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Path,
        [int]$Line = 0
    )

    $findings.Add([pscustomobject]@{
        Rule = $Rule
        Path = $Path.Replace('\', '/')
        Line = $Line
    })
}

function Test-PathName {
    param([string]$Path)

    $normalized = $Path.Replace('\', '/')
    if ($normalized -match $blockedPathPattern) {
        Add-Finding -Rule 'blocked_path' -Path $normalized
    }
}

function Test-EmailAllowed {
    param(
        [string]$Address,
        [string]$Path
    )

    $normalizedPath = $Path.Replace('\', '/')
    if ($normalizedPath.StartsWith(
            'mobile/third_party/',
            [StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith(
            'third_party/licenses/',
            [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $Address -match '(?i)@(example\.com|example\.test|users\.noreply\.github\.com)$'
}

function Test-UrlAllowed {
    param([string]$Url)

    $urlHost = ([Uri]$Url).Host.ToLowerInvariant()
    return $urlHost -in $allowedUrlHosts -or
        $urlHost -eq 'example.com' -or
        $urlHost.EndsWith('.example.com', [StringComparison]::Ordinal)
}

function Test-Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $normalized = $Path.Replace('\', '/')
    $isDependencyReport = $normalized -match '(?i)^docs/(flutter|server)-dependency-licenses\.md$'
    $skipEntropy = $isDependencyReport -or
        $normalized -match '(?i)(^|/)(LICENSE|pubspec\.lock|gradle-wrapper\.properties)$'
    $containsRuleDefinitions = $normalized -eq 'tools/audit_public_repo.ps1'
    $lines = $Text -split "`r?`n"

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $lineNumber = $index + 1
        $isAssetFilename =
            $normalized -match '(?i)\.xcassets/.+/Contents\.json$' -and
            $line -match '"filename"\s*:'

        if (-not $containsRuleDefinitions) {
            foreach ($entry in $lineRules.GetEnumerator()) {
                if ($line -match $entry.Value) {
                    Add-Finding -Rule $entry.Key -Path $normalized -Line $lineNumber
                }
            }
        }

        if (-not $isAssetFilename) {
            foreach ($match in [regex]::Matches($line, $emailPattern)) {
                if (-not (Test-EmailAllowed -Address $match.Value -Path $normalized)) {
                    Add-Finding -Rule 'non_example_email' -Path $normalized -Line $lineNumber
                }
            }
        }

        if (-not $isDependencyReport) {
            foreach ($match in [regex]::Matches($line, $ipv4Pattern)) {
                if ($match.Value -notin @('127.0.0.1', '0.0.0.0', '192.0.2.1')) {
                    Add-Finding -Rule 'non_example_ipv4' -Path $normalized -Line $lineNumber
                }
            }
        }

        if (-not $normalized.StartsWith(
                'mobile/third_party/',
                [StringComparison]::OrdinalIgnoreCase) -and
            -not $normalized.StartsWith(
                'third_party/licenses/',
                [StringComparison]::OrdinalIgnoreCase)) {
            foreach ($match in [regex]::Matches($line, $urlPattern)) {
                if (-not (Test-UrlAllowed -Url $match.Value)) {
                    Add-Finding -Rule 'non_approved_url' -Path $normalized -Line $lineNumber
                }
            }
        }

        if (-not $skipEntropy -and $line -match $longSecretPattern) {
            Add-Finding -Rule 'high_entropy_value' -Path $normalized -Line $lineNumber
        }
    }
}

function Test-WorktreeFile {
    param([string]$Path)

    Test-PathName -Path $Path
    if ([IO.Path]::GetExtension($Path).ToLowerInvariant() -in $binaryExtensions) {
        return
    }

    $absolute = Join-Path $repository $Path
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        return
    }

    $bytes = [IO.File]::ReadAllBytes($absolute)
    if ($bytes -contains 0) {
        return
    }

    Test-Text -Path $Path -Text ([Text.Encoding]::UTF8.GetString($bytes))
}

function Get-GitBlobText {
    param([string]$Object)

    $content = & git cat-file -p $Object 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "无法读取 Git 对象：$Object"
    }
    return ($content -join "`n")
}

function Get-IndexBlobText {
    param([string]$Path)

    $content = & git show ":$Path" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "无法读取暂存对象：$Path"
    }
    return ($content -join "`n")
}

Push-Location $repository
try {
    switch ($Scope) {
        'Worktree' {
            $paths = @(& git -c core.quotepath=false ls-files --cached --others --exclude-standard)
            foreach ($path in $paths) {
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    Test-WorktreeFile -Path $path
                }
            }
        }
        'Index' {
            $paths = @(& git -c core.quotepath=false diff --cached --name-only --diff-filter=ACMR)
            foreach ($path in $paths) {
                if ([string]::IsNullOrWhiteSpace($path)) {
                    continue
                }

                Test-PathName -Path $path
                if ([IO.Path]::GetExtension($path).ToLowerInvariant() -in $binaryExtensions) {
                    continue
                }

                $text = Get-IndexBlobText -Path $path
                Test-Text -Path $path -Text $text
            }
        }
        'History' {
            $objects = @(& git -c core.quotepath=false rev-list --objects --all)
            $seen = [Collections.Generic.HashSet[string]]::new()
            foreach ($record in $objects) {
                if ($record -notmatch '^([0-9a-f]{40,64})\s+(.+)$') {
                    continue
                }

                $objectId = $Matches[1]
                $path = $Matches[2]
                if (-not $seen.Add($objectId)) {
                    continue
                }

                Test-PathName -Path $path
                if ([IO.Path]::GetExtension($path).ToLowerInvariant() -in $binaryExtensions) {
                    continue
                }

                $type = (& git cat-file -t $objectId 2>$null).Trim()
                if ($LASTEXITCODE -ne 0 -or $type -ne 'blob') {
                    continue
                }

                Test-Text -Path $path -Text (Get-GitBlobText -Object $objectId)
            }

            $authors = @(& git log --format='%ae')
            foreach ($author in $authors) {
                if ($author -ne 'codexnotif@users.noreply.github.com') {
                    Add-Finding -Rule 'non_project_commit_email' -Path '.git/history'
                }
            }
        }
    }
}
finally {
    Pop-Location
}

$unique = @($findings | Sort-Object Rule, Path, Line -Unique)
if ($unique.Count -gt 0) {
    foreach ($finding in $unique) {
        $suffix = if ($finding.Line -gt 0) { " | line $($finding.Line)" } else { '' }
        Write-Output "$($finding.Rule) | $($finding.Path)$suffix"
    }
    exit 1
}

Write-Output 'PASS: no blocked public data'
exit 0
