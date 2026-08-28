# -*- coding: utf-8 -*-
"""組み直す前のページ名で、移動先を案内する小さなHTMLを置きます。

**zipで配って各自のPCで開いてもらう形なので、サーバ側のリダイレクトを置けません。**
Discordの書き込みや動画の説明欄に貼られた古いリンクは、そのまま残ります。
移動先が1つに決まるページは自動で移動し、複数へ散ったページは行き先を並べます。
アンカー付き（例: 08_materials.html#facet）も legacy-map.json で拾います。

    python tools/docs/make_legacy_stubs.py
"""
import argparse, collections, io, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

TEMPLATE = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>移動しました | MirrorBallLight</title>
<link rel="stylesheet" href="manual.css">
%(refresh)s
</head>
<body>
<header class="topbar">
<div class="brand"><a href="index.html">MirrorBallLight マニュアル</a></div>
</header>
<div class="shell" style="grid-template-columns:minmax(0,1fr)">
<main id="content">
<div class="page">
<div class="eyebrow">移動のお知らせ</div>
<h1>このページは移動しました</h1>
<p class="lead">マニュアルを「やりたいこと」別に組み直したため、<code>%(old)s</code> の内容は次のページへ移りました。</p>
%(body)s
<p><a href="index.html">目次へ</a></p>
</div>
</main>
</div>
<footer>MirrorBallLightController マニュアル</footer>
<script>
// アンカー付きで開かれたときは、その節の移動先へ送ります。
(function () {
  var map = %(anchors)s;
  var hash = location.hash.replace(/^#/, "");
  if (hash && map[hash]) { location.replace(map[hash]); }
})();
</script>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "docs"))
    ap.add_argument("--map", default=os.path.join(HERE, "legacy-map.json"))
    args = ap.parse_args()

    mapping = json.load(io.open(args.map, encoding="utf-8"))
    spec = json.load(io.open(os.path.join(HERE, "page-map.json"), encoding="utf-8"))
    h1 = {p["file"]: p["h1"] for p in spec["pages"]}

    by_old = collections.defaultdict(dict)          # 旧ページ -> {旧節ID: 新しい飛び先}
    dests = collections.defaultdict(collections.Counter)
    for src, dst in mapping.items():
        old_page, _, old_id = src.partition("#")
        by_old[old_page][old_id] = dst
        dests[old_page][dst.split("#")[0]] += 1

    written = 0
    for old_page, anchors in sorted(by_old.items()):
        targets = [f for f, _ in dests[old_page].most_common()]
        if len(targets) == 1:
            refresh = '<meta http-equiv="refresh" content="0; url=%s">' % targets[0]
            body = ('<p><a href="%s">%s へ移動します</a>（自動で移動しない場合はこのリンクから）</p>'
                    % (targets[0], h1.get(targets[0], targets[0])))
        else:
            refresh = ""
            rows = "\n".join(
                '<li><a href="%s">%s</a>（%d節）</li>' % (f, h1.get(f, f), dests[old_page][f])
                for f in targets)
            body = ("<p><strong>内容は複数のページへ分かれました。</strong>"
                    "節ごとの移動先はリンクのアンカーで判別します。</p>\n<ul>\n%s\n</ul>" % rows)

        html = TEMPLATE % dict(
            old=old_page, refresh=refresh, body=body,
            anchors=json.dumps(anchors, ensure_ascii=False, sort_keys=True))
        io.open(os.path.join(args.dir, old_page), "w", encoding="utf-8", newline="").write(html)
        written += 1

    print("旧ページ名の案内を %d 件書きました" % written)


main()
