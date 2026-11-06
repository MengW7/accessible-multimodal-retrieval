param(
    [Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][string]$Bridge,
    [Parameter(Mandatory)][string]$RuntimeRoot
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$sdk = (Resolve-Path -LiteralPath $SdkRoot).Path
$bridgePath = (Resolve-Path -LiteralPath $Bridge).Path
$runtime = [IO.Path]::GetFullPath($RuntimeRoot)
if (Test-Path -LiteralPath $runtime) { throw "Choose a new runtime directory: $runtime" }

$files = [ordered]@{
    'bin/amr_onnx.dll' = $bridgePath
    'bin/onnxruntime.dll' = Join-Path $sdk 'lib/onnxruntime.dll'
    'bin/onnxruntime_providers_shared.dll' = Join-Path $sdk 'lib/onnxruntime_providers_shared.dll'
    'bin/LICENSE' = Join-Path $sdk 'LICENSE'
    'bin/ThirdPartyNotices.txt' = Join-Path $sdk 'ThirdPartyNotices.txt'
}
foreach ($model in @(
    'models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json',
    'models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/onnx/model.onnx',
    'models/raw/image/mobileclip-s0/tokenizer.json',
    'models/raw/image/mobileclip-s0/onnx/vision_model.onnx',
    'models/raw/image/mobileclip-s0/onnx/text_model.onnx'
)) {
    $files[$model] = Join-Path $repo $model
}
foreach ($source in $files.Values) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing file: $source" }
}
$tika = Join-Path $repo 'tools/tika-app'
foreach ($entry in 'tika-app-4.0.0.jar', 'lib/tika-parser-pdf-module-4.0.0.jar') {
    if (-not (Test-Path -LiteralPath (Join-Path $tika $entry) -PathType Leaf)) {
        throw "Missing Tika resource: $entry"
    }
}

foreach ($entry in $files.GetEnumerator()) {
    $destination = Join-Path $runtime $entry.Key
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $entry.Value -Destination $destination
}
$tools = Join-Path $runtime 'tools'
New-Item -ItemType Directory -Path $tools | Out-Null
Copy-Item -LiteralPath $tika -Destination $tools -Recurse
Write-Output $runtime
