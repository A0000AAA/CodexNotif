[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$MavenRepository = (Join-Path $env:USERPROFILE '.m2\repository')
)

$ErrorActionPreference = 'Stop'

if (-not $RepositoryRoot) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$dependencyFile = Join-Path $RepositoryRoot 'server\app\target\maven-runtime-dependencies.txt'
$reportFile = Join-Path $RepositoryRoot 'docs\server-dependency-licenses.md'
$licenseRoot = Join-Path $RepositoryRoot 'third_party\licenses\maven'

if (-not (Test-Path -LiteralPath $dependencyFile)) {
    throw "Maven dependency list not found: $dependencyFile"
}

function Get-ChildText {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$Name
    )

    $child = $Node.SelectSingleNode("*[local-name()='$Name']")
    if ($null -eq $child) { return '' }
    return $child.InnerText.Trim()
}

function Get-PomPath {
    param(
        [string]$GroupId,
        [string]$ArtifactId,
        [string]$Version
    )

    $groupPath = $GroupId.Replace('.', [IO.Path]::DirectorySeparatorChar)
    return Join-Path $MavenRepository "$groupPath\$ArtifactId\$Version\$ArtifactId-$Version.pom"
}

function Resolve-LicenseId {
    param(
        [string]$Name,
        [string]$Url
    )

    $value = "$Name $Url".ToLowerInvariant()
    if ($value -match 'apache.*2(\.0)?|apache\.org/licenses/license-2\.0') { return 'Apache-2.0' }
    if ($value -match 'mozilla public license.*2|\bmpl\s*2|mozilla\.org/.*/mpl/2\.0') { return 'MPL-2.0' }
    if ($value -match 'eclipse public license.*2|epl-2\.0') { return 'EPL-2.0' }
    if ($value -match 'eclipse public license.*1|\bepl\s*1|epl-v10|epl-1\.0') { return 'EPL-1.0' }
    if ($value -match 'eclipse distribution license.*1|edl-v10|edl-1\.0') { return 'BSD-3-Clause' }
    if ($value -match 'mit license|opensource\.org/license/mit') { return 'MIT' }
    if ($value -match 'bsd 2|2-clause bsd|simplified bsd') { return 'BSD-2-Clause' }
    if ($value -match 'bsd|3-clause') { return 'BSD-3-Clause' }
    if ($value -match 'cddl.*1\.1') { return 'CDDL-1.1' }
    if ($value -match 'cddl') { return 'CDDL-1.0' }
    if ($value -match 'lgpl.*2\.1.*later') { return 'LGPL-2.1-or-later' }
    if ($value -match 'lgpl.*2\.1|lesser general public license.*2\.1') { return 'LGPL-2.1-only' }
    if ($value -match 'gpl.*2.*classpath|classpath exception') { return 'GPL-2.0-only WITH Classpath-exception-2.0' }
    return 'UNKNOWN'
}

$licenseCache = @{}
function Get-PomLicenses {
    param(
        [string]$GroupId,
        [string]$ArtifactId,
        [string]$Version,
        [int]$Depth = 0
    )

    $key = "$GroupId`:$ArtifactId`:$Version"
    if ($licenseCache.ContainsKey($key)) { return @($licenseCache[$key]) }
    if ($Depth -gt 12) { return @() }

    $pomPath = Get-PomPath -GroupId $GroupId -ArtifactId $ArtifactId -Version $Version
    if (-not (Test-Path -LiteralPath $pomPath)) { return @() }

    [xml]$pom = Get-Content -LiteralPath $pomPath -Raw -Encoding UTF8
    $project = $pom.DocumentElement
    $licenses = @()
    foreach ($license in $project.SelectNodes("*[local-name()='licenses']/*[local-name()='license']")) {
        $name = Get-ChildText -Node $license -Name 'name'
        $url = Get-ChildText -Node $license -Name 'url'
        $licenses += [pscustomobject]@{
            Name = $name
            Url = $url
            Spdx = Resolve-LicenseId -Name $name -Url $url
        }
    }

    if ($licenses.Count -eq 0) {
        $parent = $project.SelectSingleNode("*[local-name()='parent']")
        if ($null -ne $parent) {
            $parentGroup = Get-ChildText -Node $parent -Name 'groupId'
            $parentArtifact = Get-ChildText -Node $parent -Name 'artifactId'
            $parentVersion = Get-ChildText -Node $parent -Name 'version'
            if ($parentGroup -and $parentArtifact -and $parentVersion -and $parentVersion -notmatch '^\$\{') {
                $licenses = @(Get-PomLicenses -GroupId $parentGroup -ArtifactId $parentArtifact -Version $parentVersion -Depth ($Depth + 1))
            }
        }
    }

    $licenseCache[$key] = @($licenses)
    return @($licenses)
}

function Get-JarPath {
    param(
        [string]$GroupId,
        [string]$ArtifactId,
        [string]$Version
    )

    $groupPath = $GroupId.Replace('.', [IO.Path]::DirectorySeparatorChar)
    return Join-Path $MavenRepository "$groupPath\$ArtifactId\$Version\$ArtifactId-$Version.jar"
}

function Export-JarNotices {
    param(
        [string]$JarPath,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $JarPath)) { return @() }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($JarPath)
    try {
        $written = @()
        $usedNames = @{}
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notmatch '(?i)(^|/)META-INF/(LICENSE|NOTICE|DEPENDENCIES|COPYING)([._-].*)?$') { continue }
            if ($entry.Length -eq 0) { continue }

            $baseName = [IO.Path]::GetFileName($entry.FullName)
            if (-not $baseName) { continue }
            $safeName = $baseName -replace '[^A-Za-z0-9._-]', '_'
            if ($usedNames.ContainsKey($safeName)) {
                $usedNames[$safeName] += 1
                $safeName = "{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($safeName), $usedNames[$safeName], [IO.Path]::GetExtension($safeName)
            } else {
                $usedNames[$safeName] = 1
            }

            $target = Join-Path $Destination $safeName
            $input = $entry.Open()
            try {
                $output = [IO.File]::Create($target)
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally {
                $input.Dispose()
            }
            $written += $safeName
        }
        return @($written | Sort-Object -Unique)
    } finally {
        $archive.Dispose()
    }
}

if (Test-Path -LiteralPath $licenseRoot) {
    Remove-Item -LiteralPath $licenseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $licenseRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $reportFile) -Force | Out-Null

$ansiPattern = [char]27 + '\[[0-9;]*m'
$dependencies = @()
foreach ($line in Get-Content -LiteralPath $dependencyFile) {
    $clean = ($line -replace $ansiPattern, '') -replace '\s+--\s+.*$', ''
    $clean = $clean.Trim()
    if ($clean -notmatch '^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$') { continue }
    $dependencies += [pscustomobject]@{
        GroupId = $Matches[1]
        ArtifactId = $Matches[2]
        Type = $Matches[3]
        Version = $Matches[4]
        Scope = $Matches[5]
    }
}

$rows = @()
$unknown = @()
foreach ($dependency in $dependencies) {
    $coordinate = "$($dependency.GroupId):$($dependency.ArtifactId):$($dependency.Version)"
    $licenses = @(Get-PomLicenses -GroupId $dependency.GroupId -ArtifactId $dependency.ArtifactId -Version $dependency.Version)
    if ($licenses.Count -eq 0 -or @($licenses | Where-Object { $_.Spdx -eq 'UNKNOWN' }).Count -gt 0) {
        $unknown += $coordinate
    }

    $folderName = "$($dependency.GroupId)-$($dependency.ArtifactId)-$($dependency.Version)" -replace '[^A-Za-z0-9._-]', '_'
    $destination = Join-Path $licenseRoot $folderName
    $jarPath = Get-JarPath -GroupId $dependency.GroupId -ArtifactId $dependency.ArtifactId -Version $dependency.Version
    $notices = @(Export-JarNotices -JarPath $jarPath -Destination $destination)
    if ($notices.Count -eq 0 -and (Test-Path -LiteralPath $destination)) {
        Remove-Item -LiteralPath $destination -Force
    }

    $licenseText = if ($licenses.Count -gt 0) {
        (@($licenses | ForEach-Object { "$($_.Spdx) ($($_.Name))" }) -join '<br>')
    } else {
        'UNKNOWN'
    }
    $noticeText = if ($notices.Count -gt 0) {
        @($notices | ForEach-Object { "third_party/licenses/maven/$folderName/$_" }) -join '<br>'
    } else {
        'JAR 中未包含独立通知文件'
    }
    $rows += "| ``$coordinate`` | $($dependency.Scope) | $licenseText | $noticeText |"
}

$header = @(
    '# 服务端 Maven 运行时依赖许可清单',
    '',
    '> 本文件由 `tools/generate_maven_license_report.ps1` 根据 Maven 解析结果、本机 POM 元数据及 JAR 内随附通知生成。第三方组件仍适用各自的许可证；本清单不替代其原始许可文本。',
    '',
    "共记录 $($dependencies.Count) 个运行时构件。",
    '',
    '| Maven 坐标 | 作用域 | POM 许可证 | 随附文件 |',
    '| --- | --- | --- | --- |'
)
[IO.File]::WriteAllLines($reportFile, @($header + $rows), (New-Object Text.UTF8Encoding($false)))

if ($unknown.Count -gt 0) {
    Write-Error ("存在未确认的许可证：`n" + ($unknown -join "`n"))
    exit 1
}

Write-Output "Dependencies: $($dependencies.Count)"
Write-Output "Unknown licenses: 0"
Write-Output "Report: $reportFile"
