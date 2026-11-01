[CmdletBinding()]
param(
    [string]$BuildDir = "build/windows/x64/runner/Release",
    [string]$OutputDir = "dist/windows-nsis",
    [string]$Nsis = "makensis.exe",
    [string]$NsiScript = "installer/windows.nsi",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path

# Multiple make invocations can reach packaging at the same time.  NSIS writes
# a single output path, so serialize the compressor across PowerShell processes.
# The OS releases the named mutex automatically if a process is terminated.
$nsisMutex = New-Object System.Threading.Mutex($false, "Local\DclashWindowsNsis")
try {
    try {
        $null = $nsisMutex.WaitOne()
    }
    catch [System.Threading.AbandonedMutexException] {
        # The previous packager exited while holding the mutex; ownership is
        # transferred to this process and the output can be rebuilt safely.
    }
}
catch {
    $nsisMutex.Dispose()
    throw
}

function Resolve-ProjectPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Find-Nsis([string]$Requested) {
    if ($Requested -and (Test-Path $Requested)) {
        return (Resolve-Path $Requested).Path
    }
    $command = Get-Command $Requested -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $candidates = @(
        (Join-Path ${env:ProgramFiles} "NSIS\makensis.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "NSIS\makensis.exe"),
        (Join-Path ${env:LOCALAPPDATA} "Programs\NSIS\3.13\Bin\makensis.exe")
    )
    $candidate = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($candidate) {
        return (Resolve-Path $candidate).Path
    }
    throw "未找到 NSIS（makensis.exe）。请安装 NSIS，或使用 NSIS=C:\path\to\makensis.exe 指定路径。"
}

function Convert-ToNsisPath([string]$Path) {
    return $Path.Replace('\', '/')
}

$buildPath = Resolve-ProjectPath $BuildDir
$nsiPath = Resolve-ProjectPath $NsiScript
$outputPath = Resolve-ProjectPath $OutputDir
$executable = Join-Path $buildPath "dclash.exe"
$legacyExecutable = Join-Path $buildPath "Cloudrift.exe"
$iconPath = Resolve-ProjectPath "windows/runner/resources/app_icon.ico"

if (Test-Path -LiteralPath $legacyExecutable -PathType Leaf) {
    throw "Windows Release 目录仍包含旧的 Cloudrift.exe：$legacyExecutable。请先执行 make windows-release，让构建缓存自动清理后再打包。"
}
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "未找到 Windows Release 构建产物：$executable。请先执行 make windows-release。"
}
foreach ($requiredName in @("DClashCore.exe", "DClashHelperService.exe", "manifest.json")) {
    $requiredPath = Join-Path $buildPath $requiredName
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Windows Release 目录缺少必需运行时文件：$requiredPath"
    }
}
if (-not (Test-Path -LiteralPath $nsiPath -PathType Leaf)) {
    throw "未找到 NSIS 配置文件：$nsiPath"
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "未找到 Windows 应用图标：$iconPath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Select-String -Path (Join-Path $root "pubspec.yaml") -Pattern "^version:\s*(.+)$" | Select-Object -First 1
    if (-not $versionLine) {
        throw "无法从 pubspec.yaml 读取应用版本。"
    }
    $Version = $versionLine.Matches[0].Groups[1].Value.Trim()
}

$displayVersion = $Version
$numericVersion = $Version.Split('+')[0]
$versionParts = $numericVersion.Split(".")
if ($versionParts.Count -gt 4 -or ($versionParts | Where-Object { $_ -notmatch '^\d+$' })) {
    throw "NSIS 版本号必须是数字形式，例如 0.1.0 或 0.1.0+1；当前值：$Version"
}
$numericVersion = (@($versionParts) + @("0", "0", "0", "0"))[0..3] -join "."
$safeVersion = $displayVersion -replace "[^0-9A-Za-z.+-]", "_"
$installer = Join-Path $outputPath "dclash-$safeVersion-windows-x64-setup.exe"
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$nsisPath = Find-Nsis $Nsis
$arguments = @(
    "/DAPP_NAME=dclash",
    "/DAPP_EXE=dclash.exe",
    "/DAPP_VERSION=$numericVersion",
    "/DDISPLAY_VERSION=$displayVersion",
    "/DBUILD_DIR=$(Convert-ToNsisPath $buildPath)",
    "/DOUTFILE=$(Convert-ToNsisPath $installer)",
    "/DINSTALLER_ICON=$(Convert-ToNsisPath $iconPath)",
    (Convert-ToNsisPath $nsiPath)
)

& $nsisPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "NSIS 打包失败，退出码：$LASTEXITCODE"
}

${sha256} = [Security.Cryptography.SHA256]::Create()
try {
    $stream = [IO.File]::OpenRead($installer)
    try {
        $hash = ([BitConverter]::ToString(${sha256}.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}
finally {
    ${sha256}.Dispose()
}
Set-Content -Path "$installer.sha256" -Value "$hash *$(Split-Path $installer -Leaf)" -Encoding ascii
Write-Host "NSIS 安装包：$installer"
Write-Host "SHA-256：$hash"
$nsisMutex.ReleaseMutex()
$nsisMutex.Dispose()
