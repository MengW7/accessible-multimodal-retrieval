param(
    [Parameter(Mandatory)][string]$Probe,
    [Parameter(Mandatory)][ValidateSet('build','measure','lifecycle')][string]$Mode,
    [Parameter(Mandatory)][string]$Scratch,
    [Parameter(Mandatory)][string]$Report,
    [Parameter(Mandatory)][string]$RuntimeRoot,
    [switch]$ObserveTcp
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$exe = (Resolve-Path -LiteralPath $Probe).Path
$work = [IO.Path]::GetFullPath($Scratch)
$out = [IO.Path]::GetFullPath($Report)
$runtime = (Resolve-Path -LiteralPath $RuntimeRoot).Path
if (Test-Path -LiteralPath $out) { throw "Report already exists: $out" }

$temp = Join-Path $work "temp-$([IO.Path]::GetFileNameWithoutExtension($out))"
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$raw = Join-Path $temp ([IO.Path]::GetFileName($out))
$arguments = @($Mode, $repo, $work, $raw) | ForEach-Object { '"{0}"' -f $_ }
$process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru `
    -WorkingDirectory $env:SystemRoot -WindowStyle Hidden `
    -Environment @{AMR_RUNTIME_ROOT=$runtime; AMR_DEV_ROOT=$null; TEMP=$temp; TMP=$temp} `
    -RedirectStandardOutput "$out.stdout" -RedirectStandardError "$out.stderr"
$clock = [Diagnostics.Stopwatch]::StartNew()
$memory = [Collections.Generic.List[object]]::new()
$sampledNames = [Collections.Generic.HashSet[string]]::new()
$tcpRows = [Collections.Generic.HashSet[string]]::new()
$sampledChildren = [Collections.Generic.HashSet[int]]::new()
$tcpSamples = 0
$tcpErrors = 0
$peak = 0
while (-not $process.HasExited) {
    try {
        $process.Refresh()
        # This production path starts Java only; the worker and ORT share the probe PID.
        $members = @($process) + @(Get-Process -Name java* -ErrorAction SilentlyContinue |
            Where-Object { $_.Parent.Id -eq $process.Id })
        $bytes = 0
        foreach ($member in $members) {
            if (-not $member.HasExited) {
                $bytes += $member.WorkingSet64
                $null = $sampledNames.Add($member.ProcessName)
                if ($member.Id -ne $process.Id) { $null = $sampledChildren.Add($member.Id) }
            }
        }
        $peak = [Math]::Max($peak, $bytes)
        $memory.Add(@($clock.ElapsedMilliseconds, $bytes))
        if ($ObserveTcp) {
            $ids = @($members.Id)
            $lines = & (Join-Path $env:SystemRoot 'System32/netstat.exe') -ano
            if ($LASTEXITCODE -eq 0) {
                $tcpSamples++
                foreach ($line in $lines) {
                    if ($line -match '^\s*TCP\s+\S+\s+\S+\s+\S+\s+(\d+)\s*$' -and
                        [int]$Matches[1] -in $ids) {
                        $null = $tcpRows.Add(($line.Trim() -replace '\s+', ' '))
                    }
                }
            } else { $tcpErrors++ }
        }
    } catch [InvalidOperationException] {
        # A child can exit between enumeration and sampling.
    }
    Start-Sleep -Milliseconds 100
}
$process.WaitForExit()
if (Test-Path -LiteralPath $raw) {
    Copy-Item -LiteralPath $raw -Destination $out
    Remove-Item -LiteralPath $raw
}
[ordered]@{
    probeSha256 = (Get-FileHash -LiteralPath $exe).Hash
    status = $process.ExitCode
    elapsedMs = $clock.ElapsedMilliseconds
    sampledNames = @($sampledNames | Sort-Object)
    peakWorkingSetBytes = $peak
    columns = @('elapsedMs','workingSetBytes')
    memory = $memory.ToArray()
    tcpSamples = $tcpSamples
    tcpErrors = $tcpErrors
    tcpRows = @($tcpRows | Sort-Object)
    sampledChildPids = @($sampledChildren | Sort-Object)
    childPidsStillRunning = @($sampledChildren | Where-Object {
        (Get-Process -Id $_ -ErrorAction SilentlyContinue).ProcessName -like 'java*'
    })
    tempRemaining = @(Get-ChildItem -LiteralPath $temp -File -Recurse | ForEach-Object {
        [IO.Path]::GetRelativePath($temp, $_.FullName)
    })
} | ConvertTo-Json -Depth 4 -Compress | Set-Content -Encoding utf8 -LiteralPath "$out.monitor.json"
if ($process.ExitCode -ne 0) {
    Get-Content -LiteralPath "$out.stderr" -Encoding UTF8
    exit $process.ExitCode
}
Get-Content -LiteralPath "$out.stdout" -Encoding UTF8


