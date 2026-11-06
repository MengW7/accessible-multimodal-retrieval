param(
    [string]$Dart = 'dart',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repo 'reports/week6/benchmarks'
}
$out = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$dartCommand = (Get-Command $Dart -CommandType Application | Select-Object -First 1).Source
if ([IO.Path]::GetExtension($dartCommand) -eq '.bat') {
    $dartCommand = Join-Path (Split-Path $dartCommand) 'cache/dart-sdk/bin/dart.exe'
}
$report = Join-Path $out 'D1_windows_development.json'
$packageConfig = Join-Path $PSScriptRoot '../.dart_tool/package_config.json'
$program = Join-Path $PSScriptRoot 'week6_baseline.dart'
$arguments = @(
    ('"--packages={0}"' -f $packageConfig),
    ('"{0}"' -f $program),
    ('"{0}"' -f $report)
)

$process = Start-Process -FilePath $dartCommand -ArgumentList $arguments `
    -WorkingDirectory $env:SystemRoot -WindowStyle Hidden -PassThru
$clock = [Diagnostics.Stopwatch]::StartNew()
$memory = [Collections.Generic.List[object]]::new()
while (-not $process.HasExited) {
    try {
        $process.Refresh()
        $tree = @($process)
        $candidates = @(Get-Process -Name dart*,python*,java* -ErrorAction SilentlyContinue |
            Where-Object Id -ne $process.Id)
        foreach ($candidate in $candidates) {
            $candidate | Add-Member -NotePropertyName BaselineParentId `
                -NotePropertyValue $candidate.Parent.Id
        }
        for ($index = 0; $index -lt $tree.Count; $index++) {
            $tree += $candidates | Where-Object BaselineParentId -eq $tree[$index].Id
        }
        $rows = @(
            foreach ($member in $tree) {
                if (-not $member.HasExited) {
                    [ordered]@{ name = $member.ProcessName; pid = $member.Id;
                        workingSetBytes = $member.WorkingSet64 }
                }
            }
        )
        $memory.Add([ordered]@{ elapsedMs = $clock.ElapsedMilliseconds; processes = $rows })
    } catch [InvalidOperationException] {
        # A short-lived worker can exit between enumeration and sampling.
    }
    Start-Sleep -Milliseconds 100
}
$process.WaitForExit()
ConvertTo-Json -InputObject $memory.ToArray() -Depth 5 | Set-Content -LiteralPath `
    (Join-Path $out 'D1_windows_process_memory.json') -Encoding utf8
if ($process.ExitCode -ne 0) { exit $process.ExitCode }
$sampledNames = @($memory | ForEach-Object { $_.processes.name } | Sort-Object -Unique)
if (-not ($sampledNames -like 'python*') -or -not ($sampledNames -like 'java*')) {
    Write-Warning 'Process-tree samples do not include both Python and Java. Check process-query permissions before using the memory results.'
}
Get-Content -LiteralPath $report -Raw -Encoding utf8 | ConvertFrom-Json |
    Select-Object ok, workingDirectory, query, dartPeakRssBytes
