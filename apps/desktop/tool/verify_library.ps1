param([string]$Executable, [string]$DevRoot, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $Executable) { $Executable = Join-Path $repository 'apps\desktop\build\windows\x64\runner\Release\desktop.exe' }
if (-not $DevRoot) { $DevRoot = $repository }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository 'reports\week5\logs' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$DevRoot = (Resolve-Path -LiteralPath $DevRoot).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$scratch = Join-Path $repository ('tmp\w05-library-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $scratch 'fixtures'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixtures 'good.txt') -Value '离线检索验证：本地文件夹中的内容应当建立索引。' -Encoding utf8
Set-Content -LiteralPath (Join-Path $fixtures 'bad.docx') -Value 'This is deliberately not a DOCX zip file.' -Encoding utf8
$names = @('AMR_DEV_ROOT', 'AMR_DATA_DIR', 'AMR_SMOKE_OUTPUT', 'AMR_SMOKE_FIXTURES')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:AMR_DEV_ROOT = $DevRoot
    $env:AMR_DATA_DIR = Join-Path $scratch 'index'
    $env:AMR_SMOKE_OUTPUT = Join-Path $OutputDirectory 'B_library_smoke.json'
    $env:AMR_SMOKE_FIXTURES = $fixtures
    $process = Start-Process -FilePath $Executable -ArgumentList '--library-smoke' -WorkingDirectory ([IO.Path]::GetTempPath()) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw 'Library smoke timed out.'
    }
    $process.Refresh()
    if (-not (Test-Path -LiteralPath $env:AMR_SMOKE_OUTPUT)) { throw 'No library smoke report was produced.' }
    $report = Get-Content -LiteralPath $env:AMR_SMOKE_OUTPUT -Raw -Encoding utf8 | ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or -not $report.ok) { throw "Library smoke failed: $($report.error)" }
    $report | Select-Object ok, elapsedMs, mainIsolateHeartbeats, sourceFilesPreserved
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
