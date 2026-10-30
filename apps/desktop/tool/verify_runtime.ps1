param(
    [string]$Executable,
    [string]$DevRoot,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $Executable) {
    $Executable = Join-Path $repository 'apps\desktop\build\windows\x64\runner\Release\desktop.exe'
}
if (-not $DevRoot) { $DevRoot = $repository }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repository 'reports\week5\logs'
}
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$DevRoot = (Resolve-Path -LiteralPath $DevRoot).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

# Every run gets new fixtures and new databases. No existing index is cleared.
$scratch = Join-Path $repository ('tmp\w05-runtime-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $scratch 'fixtures'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null
# Use a genuinely non-repository working directory for the executable.
$outside = [IO.Path]::GetTempPath()
Set-Content -LiteralPath (Join-Path $fixtures 'smoke.txt') -Encoding utf8 -Value '离线检索验证：本地内容可以在没有云服务的情况下建立索引。'
foreach ($name in @('sample.pdf', 'sample.docx', 'sample.png')) {
    Copy-Item -LiteralPath (Join-Path $repository "datasets\samples\$name") -Destination $fixtures
}

$names = @('AMR_DEV_ROOT', 'AMR_DATA_DIR', 'AMR_SMOKE_OUTPUT', 'AMR_SMOKE_FIXTURES', 'AMR_JAVA')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

function Invoke-RuntimeCase([string]$Name, [string]$Root, [bool]$ExpectedSuccess, [string]$Java = 'java') {
    [Environment]::SetEnvironmentVariable('AMR_DEV_ROOT', $Root, 'Process')
    [Environment]::SetEnvironmentVariable('AMR_JAVA', $Java, 'Process')
    $data = Join-Path $scratch $Name
    [Environment]::SetEnvironmentVariable('AMR_DATA_DIR', $data, 'Process')
    $output = Join-Path $OutputDirectory ("A_runtime_$Name.json")
    [Environment]::SetEnvironmentVariable('AMR_SMOKE_OUTPUT', $output, 'Process')
    [Environment]::SetEnvironmentVariable('AMR_SMOKE_FIXTURES', $fixtures, 'Process')
    $process = Start-Process -FilePath $Executable -ArgumentList '--runtime-smoke' -WorkingDirectory $outside -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(240000)) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw "Runtime case $Name timed out."
    }
    $process.Refresh()
    if (-not (Test-Path -LiteralPath $output)) { throw "No report produced for $Name." }
    $report = Get-Content -LiteralPath $output -Raw -Encoding utf8 | ConvertFrom-Json
    if ($ExpectedSuccess -ne [bool]$report.ok) { throw "Unexpected result for ${Name}: $($report.error)" }
    $expectedExit = if ($ExpectedSuccess) { 0 } else { 1 }
    if ($process.ExitCode -ne $expectedExit) { throw "Unexpected exit code for ${Name}: $($process.ExitCode)" }
    [pscustomobject]@{ case = $Name; expectedSuccess = $ExpectedSuccess; actualSuccess = $report.ok;
        exitCode = $process.ExitCode; report = $output; workingDirectory = $outside }
}

try {
    $results = @(
        Invoke-RuntimeCase 'development' $DevRoot $true
        Invoke-RuntimeCase 'release_gap' '' $false
        Invoke-RuntimeCase 'missing_resources' (Join-Path $scratch 'absent-runtime') $false
        Invoke-RuntimeCase 'missing_java' $DevRoot $false (Join-Path $scratch 'no-java.exe')
    )
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'A_build_smoke.json') -Encoding utf8
    $results | Format-Table -AutoSize
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
