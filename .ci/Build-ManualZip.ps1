<#
.SYNOPSIS
    docs/ のHTMLマニュアルを zip にまとめます。

.DESCRIPTION
    このリポジトリでは **GitHub Pages を有効にしていません。** そのため
    docs/index.html へのリンクを開いても、HTMLのソースが表示されるだけで読めません。
    zipで配布し、リンクもzipを指すようにしています（2026-08-23の決定）。

    **docs/ のHTMLソースは消さないでください。** 対象バージョンの唯一の正が
    docs/index.html の <span class="version"> で、本体の Set-Version.ps1 のアンカーに
    なっています。Validate-Docs.ps1 の検査もすべてのページに依存しています。
    ソースを消すと版管理と検査の両方が壊れます。

    zipは配布物であって正ではありません。docs/ を変えたら必ず作り直してください。
    作り直し忘れは Validate-Docs.ps1 が検出します。

.PARAMETER Verify
    作り直さず、既存のzipが docs/ と一致しているかだけを確認します。
    一致していなければ終了コード1です。
#>
param(
    [string]$RepositoryPath = (Join-Path $PSScriptRoot ".."),
    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
$docs = Join-Path $repository "docs"
$zipPath = Join-Path $repository "docs_html.zip"

if (!(Test-Path -LiteralPath $docs)) {
    Write-Output "NG: docs/ がありません: $docs"
    exit 1
}

# 中身が同じでもzipのバイト列は作成時刻などで変わるため、バイト比較はしません。
# 「どのファイルが、どんな中身で入っているか」で比べます。
function Get-DocsFingerprint {
    param([string]$Root)
    $entries = New-Object 'System.Collections.Generic.List[string]'
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
        $entries.Add("$relative $hash")
    }
    return ($entries -join "`n")
}

$fingerprint = Get-DocsFingerprint $docs
$fingerprintPath = Join-Path $repository "docs_html.zip.contents"

if ($Verify) {
    if (!(Test-Path -LiteralPath $zipPath)) {
        Write-Output "NG: docs_html.zip がありません。./.ci/Build-ManualZip.ps1 で作成してください。"
        exit 1
    }
    if (!(Test-Path -LiteralPath $fingerprintPath)) {
        Write-Output "NG: docs_html.zip.contents がありません。./.ci/Build-ManualZip.ps1 で作り直してください。"
        exit 1
    }
    $recorded = Get-Content -LiteralPath $fingerprintPath -Raw
    if ($recorded.TrimEnd() -ne $fingerprint.TrimEnd()) {
        Write-Output "NG: docs_html.zip が docs/ と食い違っています。"
        Write-Output "    docs/ を変更したら ./.ci/Build-ManualZip.ps1 で作り直してください。"
        exit 1
    }
    Write-Output "OK: docs_html.zip は docs/ と一致しています。"
    exit 0
}

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $docs "*") -DestinationPath $zipPath -CompressionLevel Optimal
[System.IO.File]::WriteAllText($fingerprintPath, $fingerprint + "`n",
    [System.Text.UTF8Encoding]::new($false))

$fileCount = (Get-ChildItem -LiteralPath $docs -Recurse -File).Count
$sizeKb = [int]((Get-Item -LiteralPath $zipPath).Length / 1024)
Write-Output "MANUAL_ZIP_RESULT: PASS files=$fileCount size=${sizeKb}KB"
exit 0
