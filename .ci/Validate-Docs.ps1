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

Write-Output "HTML $($pages.Count) ページを検査しました。"
if ($problems.Count -gt 0)
{
    foreach ($problem in $problems) { Write-Output "NG: $problem" }
    throw "$($problems.Count) 件の問題が見つかりました。"
}
Write-Output "OK: バージョン表記とリンクに問題は見つかりませんでした。"
