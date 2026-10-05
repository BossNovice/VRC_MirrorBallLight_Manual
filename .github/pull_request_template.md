<!--
ブランチ名は内容を表しません（work/YYYYMMDD-NN）。
何をしたPRなのかは、タイトルと以下の本文で表現してください。
編集ルールは CONTRIBUTING.md を参照してください。
-->

## 対応する本体バージョン

<!-- 例: R__.__ / 本体側の変更を伴わない場合はその旨 -->

## 変更内容

<!-- 追加・更新したページと、その要点 -->

## 確認

- [ ] `pwsh ./.ci/Validate-Docs.ps1` が通る（本体のcloneが隣にあれば `-CoreRepositoryPath` も付けて、Inspector説明網羅まで見る）
- [ ] `docs/` を変えた場合、`pwsh ./.ci/Build-SearchIndex.ps1` と `pwsh ./.ci/Build-ManualZip.ps1` でzipと検索索引を作り直した
- [ ] 版を更新した場合、直前の版の `manual/README.md` を `archive/R<版>_GitHub_Manual/` へ**コピー**した
- [ ] 版を更新した場合、`docs/index.html` の対象バージョンと `compatibility.json`（`manual` / `coreExpected`）を更新した
- [ ] 動作確認表は、確認した結果だけを「済」にした（版を上げただけで書き換えていない）

## 本体リポジトリ側の対応

<!--
マニュアルのフォルダ名は固定なので、本体側のリンク張り替えは不要です。
本体の README や CHANGELOG の記述（対応バージョンの説明など）を変える必要がある場合は、
このPRのマージ後に本体側を更新してください。不要な場合は「不要」と書いてください。
-->
