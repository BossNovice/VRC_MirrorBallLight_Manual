param(
    [string]$RepositoryPath = (Join-Path $PSScriptRoot ".."),
    [string]$CoreRepositoryPath = "",
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
if ([string]::IsNullOrWhiteSpace($CoreRepositoryPath)) {
    $candidate = Join-Path (Split-Path -Parent $repository) "VRC_MirrorBallLight_publish"
    if (Test-Path -LiteralPath $candidate) { $CoreRepositoryPath = $candidate }
}
if ([string]::IsNullOrWhiteSpace($CoreRepositoryPath) -or !(Test-Path -LiteralPath $CoreRepositoryPath)) {
    Write-Output "INSPECTOR_COVERAGE_RESULT: SKIP 本体リポジトリが無いため説明網羅を検査できません"
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
