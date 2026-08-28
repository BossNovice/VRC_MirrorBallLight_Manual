# docs/ を組み立てる道具

HTMLマニュアルのページ構成を作り直すための一式です。**普段の文章の直しには要りません。**
本文を直すときは `docs/*.html` を直接編集してください。ここを使うのは、
**ページの割り方そのものを変えるとき**だけです。

## なぜ置いてあるか

2026-08-29に15ページを20ページへ組み直しました。そのとき使った手順を残していないと、
次に構成を触る人が「なぜこの束ね方なのか」を追えません。成果物のHTMLだけが残っていて
手順が消えている、という状態を避けるために置いています。

割り方そのものは [`page-map.json`](page-map.json) が正です。どの節をどのページへ移したか、
どの見出しを改題したか、どれを1つへ統合したかが全部書いてあります。

## ファイル

| ファイル | 役割 |
| --- | --- |
| `page-map.json` | **ページの割り方の正本。** 新しいページと、そこへ入る旧ページの節 |
| `build_docs.py` | `page-map.json` のとおりに `docs/*.html` を組み立てる |
| `fix_links.py` | 旧ページ名を指すリンクを新しいページへ張り替える |
| `build_index.py` | `docs/index.html` の左の一覧と「内容別ページ」を作り直す |
| `make_legacy_stubs.py` | 旧ファイル名で、移動先を案内する小さなページを置く |
| `legacy-map.json` | 旧ページ#旧節ID → 新ページ#新節ID の対応表（`build_docs.py` が書く） |

## 組み直す前のページを取り出す

`build_docs.py` は、組み直す前のページ（節の実体）を必要とします。
`page-map.json` の `source_commit` から取り出してください。

```bash
mkdir -p _olddocs
for f in $(git ls-tree --name-only <source_commit> docs/ | grep '\.html$'); do
  git show <source_commit>:$f > "_olddocs/$(basename $f)"
done
```

## 通し方

```bash
python tools/docs/build_docs.py --old-docs _olddocs --out _check   # まず別の場所へ
python tools/docs/build_index.py --out _check
python tools/docs/fix_links.py --dir _check
diff -r _check docs                                                # 差を見る（改行の違いは無視して比べます）
python tools/docs/build_docs.py --old-docs _olddocs                # 問題なければ docs/ へ
python tools/docs/build_index.py                                   # 先に index.html を作る
python tools/docs/fix_links.py --dir docs                          # そのうえでリンクを張り替える
python tools/docs/make_legacy_stubs.py
pwsh ./.ci/Build-SearchIndex.ps1
pwsh ./.ci/Build-ManualZip.ps1
pwsh ./.ci/Validate-Docs.ps1
```

**いきなり `docs/` へ書かないでください。** `--out` で別の場所へ出して差を見てから流す、
という順にしてあります。2026-08-29の作業では、`rm docs/0[1-9]_*.html` が新旧どちらの
ファイル名にも当たり、**作ったばかりのページを消しました。**

## 旧ページ名の案内について

zipを配って各自のPCで開いてもらう形なので、**サーバ側のリダイレクトを置けません。**
Discordの書き込みや動画の説明欄に貼られた古いリンクはそのまま残ります。
そのため、旧ファイル名のページを `docs/` に残し、移動先を案内しています。

- 移動先が1つに決まるページは `meta refresh` で自動的に移動します
- 複数へ分かれたページは行き先を並べます
- アンカー付き（`08_materials.html#facet` など）は `legacy-map.json` を見て、その節の移動先へ送ります

飛び先が生きているかは `Validate-Docs.ps1` が見ています。案内ページを消したり、
対応表の飛び先が無くなったりすると落ちます。

## 気をつけること

- **節IDは飛び先です。** 旧アンカーを生かすため、組み直しても元の節IDをそのまま使っています。
  節IDを変えると、外から貼られた古いリンクが黙って効かなくなります
- **id を持たない `<section>` があります。** 2026-08-29の作業では、これを読み飛ばして
  4節を落としました。`build_docs.py` は連番のIDを振って必ず拾います
- **`docs/index.html` の対象バージョン表記は触りません。** `Set-Version.ps1` の
  書き換え対象であり、`Validate-Docs.ps1` の検査対象でもあります
