# Run on Windows with Flutter, Visual Studio C++ tools, and NuGet on PATH.
[CmdletBinding()]
param([switch]$Run)
$ErrorActionPreference = 'Stop'
function Invoke-Flutter {
    & flutter @args
    if ($LASTEXITCODE -ne 0) { throw "Flutter failed with exit code $LASTEXITCODE" }
}
$repoRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mytube-windows-' + [guid]::NewGuid().ToString('N'))
foreach ($tool in @('flutter', 'nuget')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required tool missing from PATH: $tool" }
}
Invoke-Flutter create --org com.custom.ytadfree --project-name adfree_youtube --platforms=windows $buildRoot
Copy-Item (Join-Path $repoRoot 'pubspec.yaml') (Join-Path $buildRoot 'pubspec.yaml') -Force
Copy-Item (Join-Path $repoRoot 'lib/main.dart') (Join-Path $buildRoot 'lib/main.dart') -Force
# The template test targets the template counter app, not this application.
Remove-Item (Join-Path $buildRoot 'test/widget_test.dart')
Push-Location $buildRoot
try {
    Invoke-Flutter pub get
    Invoke-Flutter analyze
    Invoke-Flutter build windows --release --verbose
    $release = Join-Path $buildRoot 'build/windows/x64/runner/Release'
    if (-not (Test-Path (Join-Path $release 'adfree_youtube.exe'))) { throw 'Expected executable was not produced.' }
    $artifacts = Join-Path $repoRoot 'artifacts'
    New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
    $archive = Join-Path $artifacts 'MyTube-Music-Windows-x64.zip'
    Compress-Archive -Path (Join-Path $release '*') -DestinationPath $archive -Force
    Write-Host "Packaged app: $archive"
    Write-Host "Build project retained at: $buildRoot"
    if ($Run) { & (Join-Path $release 'adfree_youtube.exe') }
} finally {
    Pop-Location
}
