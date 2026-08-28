# VRC MirrorBallLight Manual

VRChat World向け `VRC_MirrorBallLight` のマニュアル専用リポジトリです。
対象バージョンは [HTML版マニュアル（zip）](https://github.com/BossNovice/VRC_MirrorBallLight_Manual/raw/main/docs_html.zip) の目次に記載しています。
**zipをダウンロードして展開し、`index.html` をブラウザで開いてください。**
このリポジトリはGitHub Pagesを使っていないため、HTMLを直接開いてもソースが表示されるだけです。

## 現行マニュアル

- [GitHub版・導入から全設定まで](manual/README.md)
- [HTML版・内容別マニュアル（zip）](https://github.com/BossNovice/VRC_MirrorBallLight_Manual/raw/main/docs_html.zip)
- [過去の版の変更履歴・移行ガイド](archive/RELEASE_NOTES.md)（**最新版だけを使う場合は不要です**）
- [サンプル形状アトラス](assets/ShapeAtlas/SampleShapeAtlas_4x2.png)
- [サンプルCookie・マスク](assets/CookieMasks/README_サンプルCookie.html)

## フォルダ構成

- `manual/README.md`: GitHub上で読む最新版Markdownマニュアル
- `docs/`: 最新版の複数ページHTMLマニュアル
- `assets/`: GitHub版マニュアルで使用する画像・サンプルTexture
- `docs/assets/`: GitHub Pages版HTMLから参照する同一サンプルの公開用コピー
- `archive/`: 旧版のマニュアルと図解、[過去の版の変更履歴](archive/RELEASE_NOTES.md)
- `R25/README.md`: 配布済みUnityPackage内のリンク互換用の移転案内。中身は最新版とアーカイブへの誘導だけです

## 更新方針

- `VRC_MirrorBallLight` の機能更新時は、関連するGitHub版とHTML版を同時に更新します。
- `docs/` と `manual/` は現行版だけを扱います。
- 旧版は参照用として `archive/` に保存しますが、今後の本体リリースZIP／UnityPackageには同梱しません。
