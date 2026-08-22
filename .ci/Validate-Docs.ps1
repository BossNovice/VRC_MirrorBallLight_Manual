<#
.SYNOPSIS
    HTMLマニュアルのバージョン表記とリンクを検証します。

.DESCRIPTION
    バージョン表記は `docs/index.html` の `<span class="version">` 1箇所だけが正です。
    サブページへ現行版を書くと、リリースのたびに14ページ分の更新が必要になり、
    実際にR25〜R27.2まで版がばらばらにドリフトしました。その再発を検出します。

    検査項目:
    - `<title>` にバージョン番号が入っていないこと
    - サブページに版付きの unitypackage ファイル名が書かれていないこと
      （配布済みパッケージから参照されると、版が変わった時点でリンク切れになるため）
    - `docs/index.html` に対象バージョンの記載が1つだけ存在すること
    - リポジトリ内の相対リンクが実在すること

    機能の履歴ラベル（「R25 表面Emission」など、どの版で入ったかを示す記述）は
    検査対象外です。これらは書き換えてはいけません。
#>
param(
    [string]$RepositoryPath = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
$docs = Join-Path $repository "docs"
$problems = New-Object 'System.Collections.Generic.List[string]'

if (!(Test-Path -LiteralPath $docs)) { throw "docs フォルダが見つかりません: $docs" }

$pages = Get-ChildItem -LiteralPath $docs -Filter "*.html" -File

# --- title に版が入っていないか ---------------------------------------------
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $titleMatch = [regex]::Match($text, '<title>(.*?)</title>')
    if (!$titleMatch.Success)
    {
        $problems.Add("title がありません: $($page.Name)")
        continue
    }
    # 「| R27.2」のような末尾の版表記だけを検出します。
    # 「11 R24ワールドShader拡張」のようにページ名へ含まれる版は、
    # どの版で入った機能かを示す履歴ラベルなので対象外です。
    if ($titleMatch.Groups[1].Value -match '\|\s*R\d+(\.\d+)?\s*$')
    {
        $problems.Add("title に対象バージョンが含まれています（index.htmlへ集約してください）: $($page.Name) → $($titleMatch.Groups[1].Value)")
    }
}

# --- 版付きパッケージ名が書かれていないか -----------------------------------
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $hits = [regex]::Matches($text, 'MirrorBallLightController_R[\d.]+\.(unitypackage|zip)')
    foreach ($hit in $hits)
    {
        $problems.Add("版付きのファイル名が書かれています（`MirrorBallLightController_*.unitypackage` のような版非依存の表記にしてください）: $($page.Name) → $($hit.Value)")
    }
}

# --- 対象バージョンの単一ソース ---------------------------------------------
$indexPath = Join-Path $docs "index.html"
$indexText = Get-Content -LiteralPath $indexPath -Raw
$versionMatches = [regex]::Matches($indexText, '<span class="version">([^<]*)</span>')
if ($versionMatches.Count -ne 1)
{
    $problems.Add("docs/index.html の対象バージョン表記が $($versionMatches.Count) 件あります。1件にしてください。")
}
elseif ($versionMatches[0].Groups[1].Value -notmatch 'R\d+(\.\d+)?')
{
    $problems.Add("docs/index.html の対象バージョン表記にバージョン番号がありません: $($versionMatches[0].Groups[1].Value)")
}
else
{
    Write-Output "対象バージョン: $($versionMatches[0].Groups[1].Value)"
}

# --- 相対リンクの実在確認 ---------------------------------------------------
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    foreach ($hit in [regex]::Matches($text, '(?:href|src)="([^"#:]+)"'))
    {
        $target = $hit.Groups[1].Value
        if ($target -match '^(https?:|mailto:|//)') { continue }
        $resolved = Join-Path $page.DirectoryName $target
        if (!(Test-Path -LiteralPath $resolved))
        {
            $problems.Add("リンク先が存在しません: $($page.Name) → $target")
        }
    }
}

# --- Markdownの相対リンクと画像リンク（R28.1で追加） -------------------------
# HTMLだけを見ていたため、manual/README.md のリンク切れを検出できませんでした。
$markdowns = @()
foreach ($name in @("manual", "docs", ".")) {
    $dir = Join-Path $repository $name
    if (!(Test-Path -LiteralPath $dir)) { continue }
    $markdowns += Get-ChildItem -LiteralPath $dir -Filter "*.md" -File
}
foreach ($markdown in $markdowns)
{
    $text = Get-Content -LiteralPath $markdown.FullName -Raw
    foreach ($hit in [regex]::Matches($text, '\]\(([^)\s]+)\)'))
    {
        $target = $hit.Groups[1].Value
        if ($target -match '^(https?:|mailto:|#)') { continue }
        $target = ($target -split '#')[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $resolved = Join-Path $markdown.DirectoryName $target
        if (!(Test-Path -LiteralPath $resolved))
        {
            $problems.Add("Markdownのリンク先が存在しません: $($markdown.Name) → $target")
        }
    }
}

# --- ファイル名の大文字・小文字不一致 ---------------------------------------
# WindowsのNTFSは大小を区別しないため、Test-Pathだけでは通ってしまいます。
# GitHub Pages（Linux）では区別されるので、実ファイル名と一致するか個別に確認します。
function Test-ExactPath
{
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($full)
    $leaf = [System.IO.Path]::GetFileName($full)
    if (!(Test-Path -LiteralPath $directory)) { return $false }
    $entries = Get-ChildItem -LiteralPath $directory -Force | ForEach-Object { $_.Name }
    return ($entries -ccontains $leaf)
}

foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    foreach ($hit in [regex]::Matches($text, '(?:href|src)="([^"#:]+)"'))
    {
        $target = $hit.Groups[1].Value
        if ($target -match '^(https?:|mailto:|//)') { continue }
        $resolved = Join-Path $page.DirectoryName $target
        if ((Test-Path -LiteralPath $resolved) -and !(Test-ExactPath $resolved))
        {
            $problems.Add("大文字・小文字が実ファイルと一致しません（GitHub Pagesで壊れます）: $($page.Name) → $target")
        }
    }
}

# --- docs/assets の参照切れ -------------------------------------------------
$docsAssets = Join-Path $docs "assets"
if (Test-Path -LiteralPath $docsAssets)
{
    foreach ($page in $pages)
    {
        $text = Get-Content -LiteralPath $page.FullName -Raw
        foreach ($hit in [regex]::Matches($text, '(?:href|src)="(assets/[^"#:]+)"'))
        {
            $resolved = Join-Path $page.DirectoryName $hit.Groups[1].Value
            if (!(Test-Path -LiteralPath $resolved))
            {
                $problems.Add("docs/assets の参照が存在しません: $($page.Name) → $($hit.Groups[1].Value)")
            }
        }
    }
}

# --- 通常の導入手順に版付きパッケージ名が残っていないか ---------------------
# HTMLは上で見ていますが、manual/README.md が対象外でした。
# 歴史説明・変更履歴・移行ガイドの記述は残すため、「導入」節だけを見ます。
$manualReadme = Join-Path $repository "manual/README.md"
if (Test-Path -LiteralPath $manualReadme)
{
    $lines = Get-Content -LiteralPath $manualReadme
    $inInstall = $false
    for ($i = 0; $i -lt $lines.Count; $i++)
    {
        $line = $lines[$i]
        if ($line -match '^##\s') { $inInstall = ($line -match '導入') }
        if (!$inInstall) { continue }
        $hit = [regex]::Match($line, 'MirrorBallLightController_R[0-9][0-9.]*\.unitypackage')
        if ($hit.Success)
        {
            $problems.Add("導入手順に版付きのファイル名が残っています（`MirrorBallLightController_*.unitypackage` にしてください）: manual/README.md の $($i + 1) 行目 → $($hit.Value)")
        }
    }
}

# --- 本体リポジトリ・成果物へのダウンロードリンクを置かない -----------------
# ユーザー方針です。マニュアルは配布物の入手先を案内しません。
$linkTargets = @()
$linkTargets += $pages
$linkTargets += $markdowns
foreach ($file in $linkTargets)
{
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in @(
        'https?://github\.com/[^"\s)]*VRC_MirrorBallLight(?!_Manual)[^"\s)]*/releases[^"\s)]*',
        'https?://[^"\s)]*\.unitypackage',
        'https?://[^"\s)]*MirrorBallLightController[^"\s)]*\.zip'))
    {
        foreach ($hit in [regex]::Matches($text, $pattern))
        {
            $problems.Add("本体リポジトリ／成果物のダウンロードリンクは置かない方針です: $($file.Name) → $($hit.Value)")
        }
    }
}

# --- 対象バージョンがマニュアル内で一致しているか ---------------------------
# 本体リポジトリはCIから参照できないため、マニュアル内の整合だけを見ます。
# docs/index.html の対象バージョンが、manual/README.md の対応表にも載っていること。
if ((Test-Path -LiteralPath $manualReadme) -and $versionMatches.Count -eq 1)
{
    $declared = [regex]::Match($versionMatches[0].Groups[1].Value, 'R[0-9][0-9.]*')
    if ($declared.Success)
    {
        $readmeText = Get-Content -LiteralPath $manualReadme -Raw
        if ($readmeText -notmatch [regex]::Escape($declared.Value))
        {
            $problems.Add("docs/index.html の対象バージョン $($declared.Value) が manual/README.md に出てきません。対応表と移行ガイドを更新してください。")
        }
    }
}

Write-Output "HTML $($pages.Count) ページ、Markdown $($markdowns.Count) ファイルを検査しました。"
if ($problems.Count -gt 0)
{
    foreach ($problem in $problems) { Write-Output "NG: $problem" }
    throw "$($problems.Count) 件の問題が見つかりました。"
}
Write-Output "OK: バージョン表記とリンクに問題は見つかりませんでした。"
