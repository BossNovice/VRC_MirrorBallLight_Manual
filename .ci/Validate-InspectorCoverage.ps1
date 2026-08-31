param(
    [string]$RepositoryPath = (Join-Path $PSScriptRoot ".."),
    [string]$CoreRepositoryPath = "",
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
# --- 本体リポジトリを探す ---------------------------------------------------
#
# **名前を1つしか知らないと、置き場所を変えただけで検査が飛びます。**
# 2026-08-31に実際に起きました。本体の clone が VRC_MirrorBallLight_publish から
# VRC_MirrorBallLight へ移り、この検査は SKIP のまま exit 0 していました。
# 呼び出し元の Validate-Docs.ps1 は全体を「OK」と表示するので、**135項目の説明網羅を
# 誰も見ていない状態が緑に見えていました。**
#
# 名前だけで決めず、Controllerのソースがあることまで確かめます。同名の別物を
# つかむと、あとの正規表現が何も拾わず「網羅0件でPASS」になります。
$coreMarker = "Assets/MirrorBallLight/Scripts/MirrorBallLightController.cs"
$searched = New-Object 'System.Collections.Generic.List[string]'
function Test-CoreRepository([string]$path)
{
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (!(Test-Path -LiteralPath $path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $path $coreMarker))
}

if (![string]::IsNullOrWhiteSpace($CoreRepositoryPath))
{
    # 明示的に渡された場合は、黙って落とさず理由を出します。
    $searched.Add($CoreRepositoryPath)
    if (!(Test-CoreRepository $CoreRepositoryPath))
    {
        # **明示的に渡されたのに中身が違うのは、環境の都合ではなく指定ミスです。**
        # ここをSKIPにすると、パスを間違えたまま緑になります。落とします。
        Write-Output ("INSPECTOR_COVERAGE_RESULT: FAIL 指定された本体リポジトリに " +
            "$coreMarker がありません: $CoreRepositoryPath")
        exit 1
    }
}
else
{
    $parent = Split-Path -Parent $repository
    foreach ($name in @("VRC_MirrorBallLight_publish", "VRC_MirrorBallLight"))
    {
        $candidate = Join-Path $parent $name
        $searched.Add($candidate)
        if (Test-CoreRepository $candidate) { $CoreRepositoryPath = $candidate; break }
    }
}

if ([string]::IsNullOrWhiteSpace($CoreRepositoryPath))
{
    # **マニュアル単独のCIでは、ここを通るのが正常です。** 本体はPrivateで読めません。
    # ただし「検査していない」ことは、結果を読む人に分かる形で残します。
    Write-Output "INSPECTOR_COVERAGE_RESULT: SKIP 本体リポジトリが見つかりません"
    foreach ($path in $searched) { Write-Output "  探した場所: $path" }
    Write-Output "  **この実行では説明網羅を検査していません。** 手元で確かめるときは"
    Write-Output "  -CoreRepositoryPath で本体リポジトリのパスを渡してください。"
    exit 0
}

$core = (Resolve-Path -LiteralPath $CoreRepositoryPath).Path
$sourceFiles = @(
    @{ kind = "Controller"; path = "Assets/MirrorBallLight/Scripts/MirrorBallLightController.cs"; editor = "Assets/MirrorBallLight/Editor/MirrorBallLightControllerEditor.cs" },
    @{ kind = "Preset"; path = "Assets/MirrorBallLight/Scripts/MirrorBallLightPreset.cs"; editor = "Assets/MirrorBallLight/Editor/MirrorBallLightPresetEditor.cs" },
    @{ kind = "UI Bridge"; path = "Assets/MirrorBallLight/Scripts/MirrorBallLightUIBridge.cs"; editor = "Assets/MirrorBallLight/Editor/MirrorBallLightUIBridgeEditor.cs" }
)
$editorPath = Join-Path $core "Assets/MirrorBallLight/Editor/MirrorBallLightControllerEditor.cs"
$docs = Get-ChildItem -LiteralPath (Join-Path $repository "docs") -Filter "*.html" -File
$pageText = @{}
$pageHtml = @{}
foreach ($page in $docs) {
    $html = Get-Content -LiteralPath $page.FullName -Raw
    $pageHtml[$page.Name] = $html
    $plain = [regex]::Replace($html, '(?s)<script.*?</script>|<style.*?</style>|<[^>]+>', ' ')
    $pageText[$page.Name] = [System.Net.WebUtility]::HtmlDecode($plain)
}

function Find-Page([string]$Needle) {
    foreach ($name in ($pageText.Keys | Sort-Object)) {
        if ($pageText[$name].Contains($Needle)) { return $name }
    }
    return $null
}

$rows = New-Object 'System.Collections.Generic.List[object]'
foreach ($source in $sourceFiles) {
    $path = Join-Path $core $source.path
    if (!(Test-Path -LiteralPath $path)) { throw "検査対象がありません: $path" }
    $text = Get-Content -LiteralPath $path -Raw
    $editorText = Get-Content -LiteralPath (Join-Path $core $source.editor) -Raw
    $visibleNames = @{}
    foreach ($hit in [regex]::Matches($editorText, '(?:DrawProperty|FindProperty)\("([^"]+)"')) {
        $visibleNames[$hit.Groups[1].Value] = $true
    }
    foreach ($hit in [regex]::Matches($text,
        '(?s)\[InspectorName\("([^"]+)"\)\](.{0,240}?)\bpublic\s+[\w<>\[\].]+\s+(\w+)\s*(?:=|;)')) {
        $label = $hit.Groups[1].Value
        $fieldName = $hit.Groups[3].Value
        if (!$visibleNames.ContainsKey($fieldName)) { continue }
        if ($label -match 'Palette|パレット') { continue }
        $rows.Add([pscustomobject]@{
            kind = $source.kind
            label = $label
            page = Find-Page $label
        })
    }
}

$foldouts = New-Object 'System.Collections.Generic.List[object]'
$editor = Get-Content -LiteralPath $editorPath -Raw
foreach ($hit in [regex]::Matches($editor, 'DrawFoldout\([^,]+,\s*"(\d+\.\s*[^"]+)"\)')) {
    $title = $hit.Groups[1].Value
    $parts = [regex]::Match($title, '^(\d+)\.\s*(.+)$')
    $page = $null
    foreach ($name in ($pageText.Keys | Sort-Object)) {
        if (!$pageText[$name].Contains($parts.Groups[2].Value)) { continue }
        if ($pageHtml[$name] -notmatch ('<td>\s*' + [regex]::Escape($parts.Groups[1].Value) + '\s*</td>')) { continue }
        $page = $name
        break
    }
    $foldouts.Add([pscustomobject]@{ kind = "Foldout"; label = $title; page = $page })
}

$missing = @($rows | Where-Object { $null -eq $_.page })
$missingFoldouts = @($foldouts | Where-Object { $null -eq $_.page })
$duplicates = @($rows | Group-Object kind, label | Where-Object Count -gt 1)

Write-Output "Inspector説明網羅: fields=$($rows.Count) covered=$($rows.Count - $missing.Count) missing=$($missing.Count) foldouts=$($foldouts.Count) foldoutMissing=$($missingFoldouts.Count)"
foreach ($row in $missing) { Write-Output "WARN: [$($row.kind)] $($row.label) の説明が見つかりません" }
foreach ($row in $missingFoldouts) { Write-Output "WARN: [Foldout] $($row.label) の見出しが見つかりません" }
if ($duplicates.Count -gt 0) {
    Write-Output "INFO: 同じコンポーネント内の重複ラベル=$($duplicates.Count)（説明は1箇所で可）"
}

$problemCount = $missing.Count + $missingFoldouts.Count
if ($problemCount -gt 0 -and $Strict) {
    Write-Output "INSPECTOR_COVERAGE_RESULT: FAIL problems=$problemCount"
    exit 1
}
if ($problemCount -gt 0) {
    Write-Output "INSPECTOR_COVERAGE_RESULT: WARN problems=$problemCount"
    exit 0
}

Write-Output "INSPECTOR_COVERAGE_RESULT: PASS fields=$($rows.Count) foldouts=$($foldouts.Count)"
exit 0
