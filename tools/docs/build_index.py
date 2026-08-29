# -*- coding: utf-8 -*-
"""docs/index.html の左の一覧と「内容別ページ」を page-map.json から作り直します。

本文（このマニュアルの使い方／主な機能／使えない環境と注意事項／収録物）と
対象バージョンの表記は、いまの index.html からそのまま運びます。
**対象バージョンは Set-Version.ps1 と Validate-Docs.ps1 が見ているので触りません。**

    python tools/docs/build_index.py                 # docs/index.html を作り直す
    python tools/docs/build_index.py --out _check    # 比較用に別の場所へ出す
"""
import argparse, io, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# カードの説明文。ページの狙いを1行で書きます（page-map.json の lead を短くしたもの）。
CARD_LEAD = {
    "01_install.html": "必要環境とImport手順、導入できたかの確かめ方",
    "02_sample.html": "設定済みPrefabを置いて、動くところまでを確かめる",
    "03_apply.html": "使うShaderを選び、自分の壁・床へ割り当てる",
    "04_controller.html": "10個の折りたたみの構成と、設定を保存するボタン",
    "05_motion.html": "回り方、反射光の強さ・色、距離による減衰",
    "06_spots.html": "光点1つの形と大きさ、同時に光る割合、複数形状のアトラス",
    "07_cookie.html": "光点の代わりに模様を投影する。Sceneビューでの確認",
    "08_surface.html": "不透明面の設定。座標方式と材質の応答",
    "09_glass.html": "透過面の設定。描画方式と深度フェード",
    "10_body.html": "本体球の鏡片の見え方と、暗い場所での担保",
    "11_emission.html": "面そのものを光らせる。光点を出さないエリアの指定",
    "12_audiolink.html": "音に合わせて明るさ・サイズ・色を動かす",
    "13_presets.html": "演出をまとめて切り替える。作り方と切替イベント",
    "14_udon.html": "ワールドのギミックから動かす。同期範囲と所有権",
    "21_uibridge.html": "ワールドのボタンで電源とプリセットを切り替える",
    "15_show.html": "曲ごとの切り替え、結果の読み取り、複数台の同時操作",
    "16_integrations.html": "連携版Shaderと、アバターへ実際の光を当てる",
    "17_translate.html": "既存の壁・ガラスMaterialを変換する",
    "18_troubleshoot.html": "症状から原因へたどる。Import時のエラーも",
    "19_heavy.html": "CPUかGPUかを確かめてから手を打つ",
    "20_release.html": "診断ウィンドウと、公開前に見る項目",
}

TEMPLATE = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MirrorBallLightController マニュアル</title>
<link rel="stylesheet" href="manual.css">
</head>
<body>
<a class="skip" href="#content">本文へ</a>
<header class="topbar">
<div class="brand"><a href="index.html">MirrorBallLight マニュアル</a></div>
<div class="searchbox">
<input id="q" type="search" placeholder="マニュアル内を検索（/ で移動）" autocomplete="off" aria-label="マニュアル内を検索">
<div id="results" class="results" role="listbox"></div>
</div>
<nav class="pager" aria-label="前後のページ">
<a href="%(first)s">%(firstshort)s →</a>
</nav>
</header>
<div class="shell">
%(sidebar)s
<main id="content">
<div class="page">
<div class="eyebrow">VRChat WORLD SYSTEM</div>
<h1>MirrorBallLightController 完全マニュアル</h1>
<p class="lead">%(lead)s</p>
<p>%(version)s</p>
%(gh)s
%(body)s
<nav class="pagenav" aria-label="前後のページ">
<span></span>
<a href="%(first)s">%(firsth1)s →</a>
</nav>
</div>
</main>
</div>
<footer>MirrorBallLightController マニュアル</footer>
<a class="totop" href="#content">↑ 上へ</a>
<script src="assets/search-index.js"></script>
<script src="assets/manual.js"></script>
</body>
</html>
"""


def block_from_h2(text, hid):
    """<h2 id=...> から、次の見出しか節の終わりまでを取り出します。"""
    i = text.index('<h2 id="%s">' % hid)
    j = text.find("<h2", i + 5)
    k = text.index("</section>", i)
    end = min(x for x in (j, k) if x > i)
    return text[i:end].rstrip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=os.path.join(ROOT, "docs", "index.html"),
                    help="本文と対象バージョンを運んでくる元")
    ap.add_argument("--out", default=os.path.join(ROOT, "docs"))
    args = ap.parse_args()

    spec = json.load(io.open(os.path.join(HERE, "page-map.json"), encoding="utf-8"))
    pages = spec["pages"]
    cur = io.open(args.source, encoding="utf-8").read()

    version = re.search(r'<span class="version">[^<]*</span>', cur).group(0)
    lead = re.search(r'<p class="lead">(.*?)</p>', cur, re.S).group(1).strip()
    gh = re.search(r'<p><a href="https://github\.com[^"]*manual/README\.md">[^<]*</a></p>', cur)
    gh = gh.group(0) if gh else ""

    side = ['<nav class="sidebar" aria-label="ページ一覧">',
            '<button class="toggle" aria-expanded="false">ページ一覧を開く</button>',
            '<div class="panel">',
            '<a class="home" aria-current="page" href="index.html">目次</a>',
            '<ul class="inpage">\n%s\n</ul>' % "\n".join(
                '<li><a href="#%s">%s</a></li>' % (i, t) for i, t in
                [("s1", "このマニュアルの使い方"), ("features", "主な機能"),
                 ("pages", "内容別ページ"), ("limits", "使えない環境と注意事項"), ("s3", "収録物")]),
            "<h2>やりたいこと</h2>"]
    group = None
    for p in pages:
        if p["group"] != group:
            if group is not None:
                side.append("</ul></div>")
            group = p["group"]
            side.append('<div class="grp"><div class="grp-name">%s</div><ul>' % group)
        side.append('<li><a href="%s">%s</a></li>' % (p["file"], p["short"]))
    side.append("</ul></div>")
    side.append("</div></nav>")

    cards = ["<section>", '<h2 id="pages">内容別ページ</h2>']
    group = None
    for p in pages:
        if p["group"] != group:
            if group is not None:
                cards.append("</div>")
            group = p["group"]
            n = sum(1 for q in pages if q["group"] == group)
            cards.append('<div class="grp-head"><strong>%s</strong><span>%d ページ</span></div>' % (group, n))
            cards.append('<div class="grp-grid">')
        cards.append('<a class="card" href="%s">\n<strong>%s</strong>\n<span>%s</span>\n</a>'
                     % (p["file"], p["h1"], CARD_LEAD.get(p["file"], "")))
    cards.append("</div>")
    cards.append("</section>")

    body = "\n".join([
        "<section>", block_from_h2(cur, "s1"), "</section>",
        "<section>", block_from_h2(cur, "features"), "</section>",
        "\n".join(cards),
        "<section>", block_from_h2(cur, "limits"), "</section>",
        "<section>", block_from_h2(cur, "s3"), "</section>",
    ])

    html = TEMPLATE % dict(sidebar="\n".join(side), lead=lead, version=version, gh=gh, body=body,
                           first=pages[0]["file"], firstshort=pages[0]["short"], firsth1=pages[0]["h1"])
    os.makedirs(args.out, exist_ok=True)
    io.open(os.path.join(args.out, "index.html"), "w", encoding="utf-8", newline="").write(html)
    print("index.html を書きました（カード %d 枚）" % len(pages))


main()
