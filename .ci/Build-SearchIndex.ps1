<#
.SYNOPSIS
docs/assets/search-index.js を docs/*.html から作り直します。

.DESCRIPTION
マニュアル内の検索は、この索引を読んで動きます。GitHub Pages を有効にしていないため
zip を配って各自のPCで開いてもらう前提で、外部から何も読み込まない作りにしています。
索引は **生成物であって正ではありません。** docs/ を変えたら作り直す必要があり、
忘れると検索結果だけが古いままになります。見た目には気づけません。

そのため Validate-Docs.ps1 から -Verify で呼び、docs/ と食い違っていたら止めます。
docs_html.zip と同じ扱いです。

.PARAMETER Verify
書き換えずに、いまの索引が docs/ と一致しているかだけを確かめます。
#>
[CmdletBinding()]
param(
    [string]$RepositoryPath,
    [switch]$Verify
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryPath))
{
    $RepositoryPath = Split-Path -Parent $PSScriptRoot
}
$docs = Join-Path $RepositoryPath "docs"
$indexPath = Join-Path $docs "assets/search-index.js"

# 左の一覧と同じ並び・同じ短い名前を使います。ここを変えるときは
# docs 側の並びも一緒に変えてください。
$pages = [ordered]@{
    "index.html"                           = "目次"
    "01_installation.html"                 = "導入"
    "02_quickstart.html"                   = "サンプル"
    "03_controller.html"                   = "Controller"
    "04_effects.html"                      = "反射・光点"
    "05_audiolink.html"                    = "AudioLink"
    "06_shapes_cookie.html"                = "形状・Cookie"
    "07_presets.html"                      = "プリセット"
    "08_materials.html"                    = "Material"
    "09_integrations.html"                 = "連携"
    "10_optimization_troubleshooting.html" = "最適化・対処"
    "11_r24_world_shader.html"             = "ワールドShader"
    "12_material_translate.html"           = "Material変換"
    "13_surface_emission_mask.html"        = "表面Emission"
    "14_performance_tips.html"             = "重い場合のTips"
    "15_advanced_usage.html"               = "拡張的な使い方"
}

function Remove-Markup([string]$html)
{
    $text = [regex]::Replace($html, "<[^>]*>", " ")
    $text = $text -replace "&lt;", "<" -replace "&gt;", ">" -replace "&amp;", "&" -replace "&nbsp;", " "
    return ([regex]::Replace($text, "\s+", " ")).Trim()
}

$entries = New-Object System.Collections.Generic.List[object]
foreach ($name in $pages.Keys)
{
    $path = Join-Path $docs $name
    if (!(Test-Path -LiteralPath $path))
    {
        throw "ページがありません: $name"
    }
    $html = Get-Content -LiteralPath $path -Raw

    # 本文だけを見ます。左の一覧や上部バーは索引へ入れません。
    $mainMatch = [regex]::Match($html, "<main[^>]*>(.*?)</main>", "Singleline")
    if (!$mainMatch.Success) { throw "main が見つかりません: $name" }
    $body = $mainMatch.Groups[1].Value

    $headings = [regex]::Matches($body, "<h2[^>]*>(.*?)</h2>", "Singleline")
    $sections = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $headings.Count; $i++)
    {
        $h = $headings[$i]

        # 飛び先は **h2 自身の id を優先** します。無いときだけ、囲っている section の id です。
        #
        # 以前は section を先に見ていました。1つの section に h2 が2つ以上あると、
        # **どの見出しも同じ飛び先になり**、目次から正しい位置へ移動できません。
        # 見た目には分からないため気づけませんでした（2026-08-28のレビュー指摘）。
        $id = ""
        $own = [regex]::Match($h.Value, '<h2[^>]*[ ]id="([^"]+)"')
        if ($own.Success)
        {
            $id = $own.Groups[1].Value
        }
        else
        {
            $before = $body.Substring(0, $h.Index)
            $opens = [regex]::Matches($before, '<section id="([^"]+)"')
            $closes = [regex]::Matches($before, "</section>")
            if ($opens.Count -gt 0 -and ($closes.Count -eq 0 -or $opens[$opens.Count - 1].Index -gt $closes[$closes.Count - 1].Index))
            {
                $id = $opens[$opens.Count - 1].Groups[1].Value
            }
        }
        if ([string]::IsNullOrWhiteSpace($id))
        {
            throw "飛び先の id がない見出しがあります: $name / $(Remove-Markup $h.Groups[1].Value)"
        }

        # 節の本文は、この見出しから次の見出しの直前までです。
        $start = $h.Index
        $end = if ($i + 1 -lt $headings.Count) { $headings[$i + 1].Index } else { $body.Length }
        $text = Remove-Markup $body.Substring($start, $end - $start)
        if ($text.Length -gt 1400) { $text = $text.Substring(0, 1400) }

        $sections.Add([ordered]@{
            id = $id
            ti = Remove-Markup $h.Groups[1].Value
            tx = $text
        })
    }
    # 左の「ページ内」目次と、本文の見出しが一致しているかを確かめます。
    # **ここがずれても見た目では気づけません。** 片方だけ直したときに出ます。
    $tocLinks = [regex]::Matches($html, '<ul class="inpage">(.*?)</ul>', "Singleline")
    if ($tocLinks.Count -gt 0)
    {
        $listed = [regex]::Matches($tocLinks[0].Value, '<a href="#([^"]+)">(.*?)</a>', "Singleline")
        if ($listed.Count -ne $sections.Count)
        {
            throw ("左のページ内目次と本文の見出しの数が違います: $name " +
                "（目次 $($listed.Count) 件 / 本文 $($sections.Count) 件）")
        }
        for ($k = 0; $k -lt $listed.Count; $k++)
        {
            $linkId = $listed[$k].Groups[1].Value
            $linkText = Remove-Markup $listed[$k].Groups[2].Value
            if ($linkId -ne $sections[$k].id -or $linkText -ne $sections[$k].ti)
            {
                throw ("左のページ内目次と本文の見出しが食い違っています: $name " +
                    "（目次「$linkText」#$linkId / 本文「$($sections[$k].ti)」#$($sections[$k].id)）")
            }
        }
    }

    $entries.Add([ordered]@{ p = $name; t = $pages[$name]; s = $sections })
}

$json = $entries | ConvertTo-Json -Depth 6 -Compress
$content = "window.MANUAL_INDEX=$json;`n"

$sectionCount = ($entries | ForEach-Object { $_.s.Count } | Measure-Object -Sum).Sum

if ($Verify)
{
    if (!(Test-Path -LiteralPath $indexPath))
    {
        Write-Output "NG: docs/assets/search-index.js がありません。./.ci/Build-SearchIndex.ps1 で作ってください。"
        exit 1
    }
    $current = Get-Content -LiteralPath $indexPath -Raw
    if ($current.Replace("`r`n", "`n") -ne $content.Replace("`r`n", "`n"))
    {
        Write-Output "NG: 検索の索引が docs/ と食い違っています。"
        Write-Output "NG: docs/ を変更したら ./.ci/Build-SearchIndex.ps1 で作り直してください。"
        exit 1
    }
    Write-Output "SEARCH_INDEX_RESULT: PASS pages=$($entries.Count) sections=$sectionCount"
    exit 0
}

Set-Content -LiteralPath $indexPath -Value $content -Encoding utf8NoBOM -NoNewline
Write-Output "SEARCH_INDEX_RESULT: PASS pages=$($entries.Count) sections=$sectionCount size=$([math]::Round($content.Length / 1024))KB"
