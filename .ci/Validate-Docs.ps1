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

# --- id の重複（2026-08-28のレビューで追加） --------------------------------
# 同じ id が1ページに2つあると、**アンカーは最初の1つへしか飛びません。**
# リンクは切れていないので、リンク切れの検査では見つかりません。
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $seen = @{}
    foreach ($hit in [regex]::Matches($text, '[ ]id="([^"]+)"'))
    {
        $id = $hit.Groups[1].Value
        if ($seen.ContainsKey($id))
        {
            $problems.Add("id が重複しています: $($page.Name) → $id")
        }
        $seen[$id] = $true
    }
}

# --- 番号付き見出しの抜け（2026-08-29で追加） --------------------------------
# 手順を「1.」「2.」と振った小見出しで、統合や削除のときに番号が飛ぶことがあります。
# **番号が飛んでいても表示は崩れないので、読んだ人が数え直すまで気づけません。**
#
# 半角の「数字＋ピリオド」で始まる <h3> だけを数えます。同じ <h2> の下に2つ以上
# あるときだけ、1から始まって抜けが無いことを見ます。番号を振っていない <h3> が
# 間に挟まっていても構いません。
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $main = [regex]::Match($text, '(?s)<main.*?</main>')
    if (!$main.Success) { continue }

    $heading = ""
    $numbers = New-Object 'System.Collections.Generic.List[int]'
    $check = {
        if ($numbers.Count -lt 2) { return }
        $expected = 1..$numbers.Count
        if (($numbers -join ",") -ne ($expected -join ","))
        {
            $problems.Add("番号付き見出しが 1 から連続していません: " +
                "$($page.Name)「$heading」→ $($numbers -join ', ')")
        }
    }

    foreach ($hit in [regex]::Matches($main.Value, '(?s)<h([23])[^>]*>(.*?)</h\1>'))
    {
        $plain = [regex]::Replace($hit.Groups[2].Value, '<[^>]*>', '').Trim()
        if ($hit.Groups[1].Value -eq "2")
        {
            & $check
            $heading = $plain
            $numbers.Clear()
            continue
        }
        $numbered = [regex]::Match($plain, '^(\d+)\.')
        if ($numbered.Success) { $numbers.Add([int]$numbered.Groups[1].Value) }
    }
    & $check
}

# --- アンカーの飛び先が実在するか（2026-08-28のレビューで追加） --------------
# ページ内目次の href="#..." と、他ページの href="page.html#..." の両方を見ます。
# **飛び先が無いリンクは、押しても何も起きません。** 押すまで気づけません。
$idsByPage = @{}
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $set = @{}
    foreach ($hit in [regex]::Matches($text, '[ ]id="([^"]+)"')) { $set[$hit.Groups[1].Value] = $true }
    $idsByPage[$page.Name] = $set
}
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    foreach ($hit in [regex]::Matches($text, 'href="([^"]*)#([^"]+)"'))
    {
        $targetPage = $hit.Groups[1].Value
        $anchor = $hit.Groups[2].Value
        if ($targetPage -match '^(https?:|mailto:|//)') { continue }
        $pageName = if ([string]::IsNullOrWhiteSpace($targetPage)) { $page.Name } else { Split-Path -Leaf $targetPage }
        if (!$idsByPage.ContainsKey($pageName))
        {
            $problems.Add("アンカーの参照先ページが docs/ にありません: $($page.Name) → $targetPage#$anchor")
            continue
        }
        if (!$idsByPage[$pageName].ContainsKey($anchor))
        {
            $problems.Add("アンカーの飛び先がありません: $($page.Name) → $targetPage#$anchor")
        }
    }
}

# --- 本文から自分のページへのリンク（2026-08-29で追加） ----------------------
# 15ページを20ページへ組み直したとき、別ページを指していたリンクの何本かが
# **統合先＝いま開いているページ自身**になりました。押しても何も起きないので、
# リンク切れの検査には引っかかりません。文言も「詳細ページへ」のまま残ります。
#
# アンカー付き（#見出し）は同じページ内の移動なので見逃します。左のページ一覧は
# 現在地を示すために自分自身を指すので、<main> の中だけを見ます。
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $main = [regex]::Match($text, '(?s)<main.*?</main>')
    if (!$main.Success) { continue }
    $body = [regex]::Replace($main.Value, '(?s)<nav.*?</nav>', '')

    foreach ($hit in [regex]::Matches($body, '(?s)<a href="([^"#]+)">(.*?)</a>'))
    {
        if ($hit.Groups[1].Value -ne $page.Name) { continue }
        $label = [regex]::Replace($hit.Groups[2].Value, '<[^>]*>', '').Trim()
        $problems.Add("本文のリンクが同じページを指しています（押しても動きません）: " +
            "$($page.Name) →「$label」")
    }
}

# --- zip に入らないローカルファイルへのリンク（2026-08-28のレビューで追加） --
# 配るのは docs/ を固めた zip です。**リポジトリには在るが zip には入らない**
# ファイルを指すと、リポジトリ上では通り、受け取った人の手元だけで切れます。
# ここでリポジトリだけを見ていたため、../manual/README.md を見逃していました。
$docsFull = (Resolve-Path -LiteralPath $docs).Path.TrimEnd('')
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    foreach ($hit in [regex]::Matches($text, '(?:href|src)="([^"#:]+)"'))
    {
        $target = $hit.Groups[1].Value
        if ($target -match '^(https?:|mailto:|//)') { continue }
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $page.DirectoryName $target))
        if (!$resolved.StartsWith($docsFull, [System.StringComparison]::OrdinalIgnoreCase))
        {
            $problems.Add("zip に入らないファイルを指しています（docs/ の外）: $($page.Name) → $target。" +
                "公開URLにするか、docs/ の中へ置いてください。")
        }
    }
}

# --- Markdownの相対リンクと画像リンク（R28.1で追加） -------------------------
# HTMLだけを見ていたため、manual/README.md のリンク切れを検出できませんでした。
$markdowns = @()
foreach ($name in @("manual", "docs", "archive", ".")) {
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

# --- compatibility.json との整合（R28.1で追加） ------------------------------
# 本体リポジトリはこのファイルを取得して版対応を照合します（本体はPrivate、
# マニュアルはPublicなので、相互照合は本体のCIで行います）。
# こちら側では、docs/index.html の対象バージョンと一致しているかだけを見ます。
$compatibilityPath = Join-Path $repository "compatibility.json"
if (!(Test-Path -LiteralPath $compatibilityPath))
{
    $problems.Add("compatibility.json がありません。本体との版対応の照合に使うため必要です。")
}
elseif ($versionMatches.Count -eq 1)
{
    $compatibility = Get-Content -LiteralPath $compatibilityPath -Raw | ConvertFrom-Json
    $declared = [regex]::Match($versionMatches[0].Groups[1].Value, 'R[0-9][0-9.]*')
    if ($declared.Success -and $compatibility.manual -ne $declared.Value)
    {
        $problems.Add("compatibility.json の manual が docs/index.html の対象バージョンと一致しません: " +
            "compatibility.json=$($compatibility.manual) / docs/index.html=$($declared.Value)")
    }
    if ([string]::IsNullOrWhiteSpace($compatibility.coreExpected))
    {
        $problems.Add("compatibility.json の coreExpected が空です。対応する本体の版を書いてください。")
    }
}

# --- 動作確認表の「未確認」の残り（R28.2で追加） -----------------------------
# 本体の Set-Version.ps1 -Scaffold は、動作確認表へ新しい版の行を「未確認」で追加します。
# 実機確認の実績を自動で「済」と書かないためです。ただし、そのままリリースされると
# 表が意味を失います。**現行版の行に「未確認」が残っていたら落とします。**
# 過去の版の行は対象外です（そのときに確認できなかった事実の記録なので残します）。
#
# 「未確認」と「未実施」は別物として扱います。
#   未確認 … Scaffoldが置いたままで、まだ誰も見ていない。リリースを止めます
#   未実施 … 確認しないと判断した。理由を書くことを条件に通します
# 「未実施」を素通しにすると、確認しない理由を書かずに済ませられてしまうため、
# 現行版に「未実施」があるときは理由の記載を必須にします。
$readmePath = Join-Path $repository "manual/README.md"
if ((Test-Path -LiteralPath $readmePath) -and (Test-Path -LiteralPath $compatibilityPath))
{
    $currentVersion = (Get-Content -LiteralPath $compatibilityPath -Raw | ConvertFrom-Json).manual
    if (![string]::IsNullOrWhiteSpace($currentVersion))
    {
        $pending = Get-Content -LiteralPath $readmePath |
            Where-Object { $_ -match "^\|\s*$([regex]::Escape($currentVersion))\s*\|" -and $_ -match "未確認" }
        foreach ($row in $pending)
        {
            $problems.Add("動作確認表に $currentVersion の未確認が残っています。確認した結果を書くか、" +
                "確認しない判断なら理由付きで「未実施」にしてください: $($row.Trim())")
        }

        # 「未実施」は理由を書けば通りますが、それだけだと「理由を書けば永久に通る」に
        # なります。期限と延長回数まで機械的に見て、放置と無限延長を検出します。
        $lines = Get-Content -LiteralPath $readmePath
        $notRun = $lines | Where-Object {
            $_ -match "^\|\s*$([regex]::Escape($currentVersion))\s*\|" -and $_ -match "未実施"
        }
        $blockStarts = @()
        for ($i = 0; $i -lt $lines.Count; $i++)
        {
            if ($lines[$i] -match "^\*\*未実施\*\*:") { $blockStarts += $i }
        }

        if ($notRun -and $blockStarts.Count -eq 0)
        {
            $problems.Add("動作確認表に $currentVersion の未実施がありますが、理由が書かれていません。" +
                "``**未実施**:`` で始まるブロックに、理由種別・理由詳細・期限・担当・次アクション・" +
                "更新日・延長回数を書いてください。")
        }

        # 期限は「今日」と比べます。リリース時だけでなく、mainへ向いたPRのたびに見ます。
        # 放置を検出したいので、実行日基準でなければ意味がありません。
        $today = [datetime]::Now.Date
        $seenTrackingIds = @{}
        foreach ($start in $blockStarts)
        {
            $label = ($lines[$start] -replace "^\*\*未実施\*\*:\s*", "").Trim()

            # ブロックは箇条書きが途切れるまでです。
            $body = New-Object 'System.Collections.Generic.List[string]'
            for ($i = $start + 1; $i -lt $lines.Count; $i++)
            {
                if ($lines[$i] -match "^\s*-\s" -or $lines[$i] -match "^\s+\S") { $body.Add($lines[$i]) }
                elseif ([string]::IsNullOrWhiteSpace($lines[$i])) { break }
                else { break }
            }
            $text = $body -join "`n"

            function Get-Field { param([string]$Name)
                $m = [regex]::Match($text, "(?m)^\s*-\s*$Name\s*:\s*(.+)$")
                if ($m.Success) { return $m.Groups[1].Value.Trim() }
                return $null
            }

            foreach ($required in @("追跡ID", "理由種別", "理由詳細", "期限", "担当", "次アクション", "更新日", "延長回数"))
            {
                if (!(Get-Field $required))
                {
                    $problems.Add("未実施ブロック『$label』に $required がありません。")
                }
            }

            # 追跡IDは公開して差し支えない識別子です。本体リポジトリはPrivateなので、
            # Issue番号を公開マニュアルへ必須で載せても読者は開けません。IDだけを共通の
            # 目印にして、Issueとの対応は本体側で持ちます。
            $trackingId = Get-Field "追跡ID"
            if ($trackingId)
            {
                if ($trackingId -notmatch '^R[0-9][0-9.]*-UNEXEC-[0-9]{2}$')
                {
                    $problems.Add("未実施ブロック『$label』の追跡IDが書式に合いません: $trackingId " +
                        "（R28.2-UNEXEC-01 の形式）")
                }
                elseif ($seenTrackingIds.ContainsKey($trackingId))
                {
                    $problems.Add("追跡ID $trackingId が重複しています。1つの未実施につき1つにしてください。")
                }
                else { $seenTrackingIds[$trackingId] = $true }
            }

            $kind = Get-Field "理由種別"
            if ($kind -and $kind -notin @("ENV_UNAVAILABLE", "EXTERNAL_BLOCKER", "TIMEBOX"))
            {
                $problems.Add("未実施ブロック『$label』の理由種別が想定外です: $kind " +
                    "（ENV_UNAVAILABLE / EXTERNAL_BLOCKER / TIMEBOX のいずれか）")
            }

            $deadline = Get-Field "期限"
            if ($deadline)
            {
                $parsed = [datetime]::MinValue
                if (![datetime]::TryParseExact($deadline, "yyyy-MM-dd", $null,
                        [System.Globalization.DateTimeStyles]::None, [ref]$parsed))
                {
                    $problems.Add("未実施ブロック『$label』の期限が YYYY-MM-DD ではありません: $deadline")
                }
                elseif ($parsed.Date -lt $today)
                {
                    $problems.Add("未実施ブロック『$label』の期限が過ぎています: $deadline。" +
                        "確認して表を更新するか、理由詳細に延長の理由を追記したうえで期限・更新日・" +
                        "延長回数を更新してください。")
                }
            }

            $extensions = Get-Field "延長回数"
            if ($extensions)
            {
                $count = 0
                if (![int]::TryParse($extensions, [ref]$count))
                {
                    $problems.Add("未実施ブロック『$label』の延長回数が数値ではありません: $extensions")
                }
                elseif ($count -gt 2)
                {
                    $problems.Add("未実施ブロック『$label』の延長回数が $count 回です。" +
                        "3回以上の延長は認めていません。確認するか、確認しないと決めて表から行を外してください。")
                }
            }
        }
    }
}

# --- 旧ページ名からの案内が生きているか（2026-08-29で追加） ------------------
# ページを「やりたいこと」別へ組み直したとき、ファイル名が全部変わりました。
# **zipで配る形なのでサーバ側のリダイレクトを置けません。** 旧ファイル名の
# 案内ページを docs/ に残していますが、放っておくと飛び先だけが古くなります。
# 飛び先はJavaScriptの中にも書いてあり、上のリンク検査では見ていません。
$legacyMapPath = Join-Path $repository "tools/docs/legacy-map.json"
if (Test-Path -LiteralPath $legacyMapPath)
{
    $legacy = Get-Content -LiteralPath $legacyMapPath -Raw | ConvertFrom-Json
    $oldPages = @{}
    foreach ($entry in $legacy.PSObject.Properties)
    {
        $oldPage = ($entry.Name -split "#")[0]
        $oldPages[$oldPage] = $true

        $parts = $entry.Value -split "#"
        $targetPath = Join-Path $docs $parts[0]
        if (!(Test-Path -LiteralPath $targetPath))
        {
            $problems.Add("旧ページからの案内先がありません: $($entry.Name) → $($entry.Value)")
            continue
        }
        if ($parts.Count -gt 1)
        {
            $targetText = Get-Content -LiteralPath $targetPath -Raw
            if ($targetText -notmatch [regex]::Escape("id=""$($parts[1])"""))
            {
                $problems.Add("旧ページからの案内先に飛び先がありません: $($entry.Name) → $($entry.Value)")
            }
        }
    }
    foreach ($oldPage in $oldPages.Keys)
    {
        if (!(Test-Path -LiteralPath (Join-Path $docs $oldPage)))
        {
            $problems.Add("旧ページ名の案内が置かれていません: $oldPage。" +
                "tools/docs/make_legacy_stubs.py で作り直してください。")
        }
    }
}

# --- 旧ページ案内の遷移が1本になっているか（2026-08-29で追加） --------------
# 移動は JavaScript だけで行い、`meta refresh` は noscript の中へ置いています。
# **両方が生きていると、アンカー付きで開かれたときに meta 側が先に走り、
# 節を失ったページ先頭へ飛びます。** どちらが勝つかは保証されません。
foreach ($page in $pages)
{
    $text = Get-Content -LiteralPath $page.FullName -Raw
    if ($text -notmatch "このページは移動しました") { continue }

    foreach ($hit in [regex]::Matches($text, '<meta http-equiv="refresh"[^>]*>'))
    {
        $before = $text.Substring(0, $hit.Index)
        $opened = ([regex]::Matches($before, "<noscript>")).Count
        $closed = ([regex]::Matches($before, "</noscript>")).Count
        if ($opened -le $closed)
        {
            $problems.Add("旧ページ案内の meta refresh が noscript の外にあります: $($page.Name)。" +
                "JavaScript側の移動と競合し、アンカーが失われます。")
        }
    }
    if ($text -notmatch "var fallback = ")
    {
        $problems.Add("旧ページ案内に移動先の指定がありません: $($page.Name)。" +
            "tools/docs/make_legacy_stubs.py で作り直してください。")
    }
}

# --- 検索の索引が docs/ と一致しているか -------------------------------------
# 索引は生成物です。docs/ を変えたのに作り直さないと、**検索結果だけが古いまま**に
# なります。ページを開いても見た目には分からないので、ここで検出します。
$searchCheck = & pwsh -NoProfile -File (Join-Path $repository ".ci/Build-SearchIndex.ps1") `
    -RepositoryPath $repository -Verify 2>&1
if ($LASTEXITCODE -ne 0)
{
    foreach ($line in $searchCheck) { $problems.Add(($line | Out-String).Trim()) }
}

# --- docs_html.zip が docs/ と一致しているか（2026-08-23で追加） --------------
# GitHub Pages を有効にしていないため、docs/index.html へのリンクを開いても
# HTMLのソースが表示されるだけで読めません。zipで配布し、リンクもzipを指します。
# **zipは配布物であって正ではありません。** docs/ を変えたら作り直す必要があり、
# 忘れると古い内容が配られ続けます。ここで検出します。
$zipCheck = & pwsh -NoProfile -File (Join-Path $repository ".ci/Build-ManualZip.ps1") `
    -RepositoryPath $repository -Verify 2>&1
if ($LASTEXITCODE -ne 0)
{
    foreach ($line in $zipCheck) { $problems.Add(($line | Out-String).Trim()) }
}

Write-Output "HTML $($pages.Count) ページ、Markdown $($markdowns.Count) ファイルを検査しました。"
if ($problems.Count -gt 0)
{
    foreach ($problem in $problems) { Write-Output "NG: $problem" }
    throw "$($problems.Count) 件の問題が見つかりました。"
}
Write-Output "OK: バージョン表記とリンクに問題は見つかりませんでした。"
