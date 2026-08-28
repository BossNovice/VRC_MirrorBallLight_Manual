# -*- coding: utf-8 -*-
"""page-map.json のとおりに docs/*.html を組み立てます。

使い方は同じフォルダの README.md にあります。組み直す前のページを入れた
フォルダ（既定は `_olddocs`）を渡すと、docs/ を作り直します。

    python tools/docs/build_docs.py --old-docs _olddocs
    python tools/docs/build_docs.py --old-docs _olddocs --out _check   # 比較用

`--out` を付けると docs/ を書き換えず、そのフォルダへ出します。いまの docs/ と
差が無いことを確かめてから本番へ流す、という使い方を想定しています。
索引・リンク・index.html は別のスクリプトです（README.md 参照）。
"""
import argparse, io, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def load_sections(old_dir):
    """組み直す前のページから、節を (ファイル名, 節ID) で引けるようにします。

    id を持たない <section> は h2 の id を使います。**どちらも無い節を
    黙って飛ばすと、節がまるごと落ちます**（実際に4節落としました）。
    そのときは連番のIDを振って必ず拾います。
    """
    store = {}
    for name in sorted(os.listdir(old_dir)):
        if not name.endswith(".html"):
            continue
        text = io.open(os.path.join(old_dir, name), encoding="utf-8").read()
        body = re.search(r"<main[^>]*>(.*?)</main>", text, re.S).group(1)
        auto = 0
        for part in re.split(r"(?=<section)", body):
            m = re.match(r'<section(?:\s+id="([^"]+)")?\s*>(.*?)</section>', part, re.S)
            if not m:
                continue
            inner = m.group(2).strip()
            sid = m.group(1)
            if not sid:
                h = re.search(r'<h2[^>]*[ ]id="([^"]+)"', inner)
                sid = h.group(1) if h else None
            if not sid:
                auto += 1
                sid = "auto%d" % auto
            store[(name, sid)] = inner
    return store


def title_of(html):
    m = re.search(r"<h2[^>]*>(.*?)</h2>", html, re.S)
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", m.group(1))).strip() if m else ""


def prepare(html, title, mode):
    # h2 自身のIDは外します。飛び先は section 側へ一本化します
    # （両方に残すと同じページに同じIDが2つ並びます）。
    html = re.sub(r'<h2\s+id="[^"]+"\s*>', "<h2>", html, count=1)
    if title:
        html = re.sub(r"<h2[^>]*>.*?</h2>", "<h2>%s</h2>" % title, html, count=1, flags=re.S)
    if mode == "h3":
        t = title or title_of(html)
        html = "<h3>%s</h3>\n%s" % (t, re.sub(r"<h2[^>]*>.*?</h2>\s*", "", html, count=1, flags=re.S))
    return html


HEAD = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%(title)s</title>
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
%(pager)s
</nav>
</header>
<div class="shell">
%(sidebar)s
<main id="content">
<div class="page">
%(head)s
%(body)s
<nav class="pagenav" aria-label="前後のページ">
%(pagenav)s
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


def sidebar_html(pages, current, inpage):
    out = ['<nav class="sidebar" aria-label="ページ一覧">',
           '<button class="toggle" aria-expanded="false">ページ一覧を開く</button>',
           '<div class="panel">',
           '<a class="home"%s href="index.html">目次</a>' % (' aria-current="page"' if current == "index.html" else ""),
           "<h2>やりたいこと</h2>"]
    group = None
    for p in pages:
        if p["group"] != group:
            if group is not None:
                out.append("</ul></div>")
            group = p["group"]
            out.append('<div class="grp"><div class="grp-name">%s</div><ul>' % group)
        mark = ' aria-current="page"' if p["file"] == current else ""
        out.append('<li><a%s href="%s">%s</a>' % (mark, p["file"], p["short"]))
        if p["file"] == current and inpage:
            out.append(inpage)
        out.append("</li>")
    out.append("</ul></div>")
    out.append("</div></nav>")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old-docs", default=os.path.join(ROOT, "_olddocs"))
    ap.add_argument("--out", default=os.path.join(ROOT, "docs"))
    ap.add_argument("--map", default=os.path.join(ROOT, "tools", "docs", "legacy-map.json"),
                    help="旧ページ・旧アンカーから新しい飛び先への対応表の出力先")
    args = ap.parse_args()

    if not os.path.isdir(args.old_docs):
        sys.exit("組み直す前のページが見つかりません: %s（README.md の手順で取り出してください）" % args.old_docs)
    os.makedirs(args.out, exist_ok=True)

    spec = json.load(io.open(os.path.join(HERE, "page-map.json"), encoding="utf-8"))
    store = load_sections(args.old_docs)
    pages = spec["pages"]
    legacy = {}

    for p in pages:
        secs, items, seen = [], [], set()
        pending = None   # 直前の節（h3 はここへ足します）
        for part in p["parts"]:
            key = (part["src"], part["id"])
            if key not in store:
                sys.exit("節が見つかりません: %s#%s" % key)
            html = prepare(store[key], part.get("title"), part.get("mode", "section"))
            if part.get("mode") == "h3":
                if pending is None:
                    sys.exit("h3 の直前に節がありません: %s#%s" % key)
                secs[-1] = secs[-1].replace("\n</section>", "\n%s\n</section>" % html)
                legacy["%s#%s" % key] = "%s#%s" % (p["file"], pending)
                continue
            sid = part["id"]
            while sid in seen:
                sid += "-2"
            seen.add(sid)
            pending = sid
            secs.append('<section id="%s">\n%s\n</section>' % (sid, html))
            items.append((sid, title_of(html)))
            legacy["%s#%s" % key] = "%s#%s" % (p["file"], sid)
        p["_secs"] = "\n".join(secs)
        p["_items"] = items

    for i, p in enumerate(pages):
        prev = pages[i - 1] if i > 0 else None
        nxt = pages[i + 1] if i + 1 < len(pages) else None
        pager = ['<a href="%s">← %s</a>' % (prev["file"], prev["short"]) if prev
                 else '<a href="index.html">← 目次</a>']
        if nxt:
            pager.append('<a href="%s">%s →</a>' % (nxt["file"], nxt["short"]))
        pagenav = ['<a href="%s">← %s</a>' % (prev["file"], prev["h1"]) if prev
                   else '<a href="index.html">← 目次</a>',
                   '<a href="%s">%s →</a>' % (nxt["file"], nxt["h1"]) if nxt
                   else '<a href="index.html">目次へ戻る →</a>']
        inpage = '<ul class="inpage">\n%s\n</ul>' % "\n".join(
            '<li><a href="#%s">%s</a></li>' % (sid, t) for sid, t in p["_items"])
        html = HEAD % dict(
            title="%s | MirrorBallLight" % p["h1"],
            pager="\n".join(pager),
            sidebar=sidebar_html(pages, p["file"], inpage),
            head='<div class="eyebrow">%s</div>\n<h1>%s</h1>\n<p class="lead">%s</p>'
                 % (p["group"], p["h1"], p["lead"]),
            body=p["_secs"], pagenav="\n".join(pagenav))
        io.open(os.path.join(args.out, p["file"]), "w", encoding="utf-8", newline="").write(html)

    io.open(args.map, "w", encoding="utf-8", newline="").write(
        json.dumps(legacy, ensure_ascii=False, indent=1) + "\n")
    print("%d ページを %s へ書きました（対応表 %d 件）" % (len(pages), args.out, len(legacy)))


main()
