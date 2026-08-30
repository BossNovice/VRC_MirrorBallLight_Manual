param(
    [string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$CoreRepositoryPath = ""
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
if ([string]::IsNullOrWhiteSpace($CoreRepositoryPath)) {
    $CoreRepositoryPath = Join-Path (Split-Path -Parent $repository) "VRC_MirrorBallLight_publish"
}
$validator = Join-Path $repository ".ci/Validate-InspectorCoverage.ps1"

& pwsh -NoProfile -File $validator -RepositoryPath $repository `
    -CoreRepositoryPath $CoreRepositoryPath -Strict
if ($LASTEXITCODE -ne 0) { throw "故障注入前の説明網羅検査が失敗しました" }

$temporary = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("mb_manual_coverage_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
try {
    New-Item -ItemType Directory -Force (Join-Path $temporary "docs") | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $repository "docs")) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $temporary "docs") -Recurse -Force
    }

    $target = Join-Path $temporary "docs/05_motion.html"
    $text = Get-Content -LiteralPath $target -Raw
    $needle = "ディザの粒度"
    if (!$text.Contains($needle)) { throw "故障注入対象が見つかりません: $needle" }
    Set-Content -LiteralPath $target -NoNewline -Value ($text.Replace($needle, "ディザ設定"))

    $output = & pwsh -NoProfile -File $validator -RepositoryPath $temporary `
        -CoreRepositoryPath $CoreRepositoryPath -Strict 2>&1
    $joined = $output -join "`n"
    if ($LASTEXITCODE -eq 0) { throw "説明を削除したのに網羅検査が成功しました" }
    if ($joined -notmatch [regex]::Escape("ディザの粒度 の説明が見つかりません")) {
        throw "狙った説明漏れではなく別の理由で失敗しました"
    }
    Write-Output "INSPECTOR_COVERAGE_FAULT_RESULT: PASS"
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
