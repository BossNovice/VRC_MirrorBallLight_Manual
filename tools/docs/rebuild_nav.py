# -*- coding: utf-8 -*-
"""左のページ一覧と前後のリンクだけを、page-map.json のとおりに作り直します。

**本文には触れません。** build_docs.py はページの中身ごと組み直すので、あとから手で
書いたページ（parts が空のもの）を消してしまいます。ページを1枚足したときに要るのは、
実際には次の3か所だけです。

    <nav class="sidebar">   全ページの左の一覧
    <nav class="pager">     ヘッダの前後リンク
    <nav class="pagenav">   本文末尾の前後リンク

ページ内の目次（<ul class="inpage">）は、そのページ自身の <section id> と <h2> から
作り直します。build_docs.py と同じ作り方です。

    python tools/docs/rebuild_nav.py            # docs/ を書き換える
    python tools/docs/rebuild_nav.py --check    # 書き換えず、差が出るページ名だけ出す

**行の折り方は、いまの docs/ に合わせてあります。** ページ側は </li> を次の行へ、
index.html は1行にまとめる、という違いが元からあります。揃えないと、中身を変えて
いないページまで差分だらけになり、本当の変更が埋もれます。
"""
import argparse, io, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NL = chr(10)

# index.html のページ内目次は本文が固定なので、build_index.py と同じ並びを持ちます。
INDEX_INPAGE = [("s1", "このマニュアルの使い方"), ("features", "主な機能"),
                ("pages", "内容別ページ"), ("limits", "使えない環境と注意事項"), ("s3", "収録物")]


def inpage_items(text):
    """そのページの <section id="X"> と、その中の最初の <h2> を拾います。

    **h2 が節の先頭にあるとは限りません。** 18_troubleshoot.html の #udon は h3 から
    始まっていて、直後の h2 だけを見る書き方では丸ごと落ちました。節の中を探します。
    """
    main = re.search(r"(?s)<main.*?</main>", text)
    if not main:
        return []
    items = []
    for m in re.finditer(r'(?s)<section id="([^"]+)">(.*?)</section>', main.group(0)):
        h2 = re.search(r"(?s)<h2[^>]*>(.*?)</h2>", m.group(2))
        if not h2:
            continue
        title = re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", h2.group(1))).strip()
        items.append((m.group(1), title))
    return items


def inpage_list(items):
    rows = NL.join('<li><a href="#%s">%s</a></li>' % (i, t) for i, t in items)
    return '<ul class="inpage">' + NL + rows + NL + "</ul>"


def sidebar_html(pages, current, items):
    out = ['<nav class="sidebar" aria-label="ページ一覧">',
           '<button class="toggle" aria-expanded="false">ページ一覧を開く</button>',
           '<div class="panel">',
           '<a class="home"%s href="index.html">目次</a>'
           % (' aria-current="page"' if current == "index.html" else "")]
    if current == "index.html":
        out.append(inpage_list(items))
    out.append("<h2>やりたいこと</h2>")
    group = None
    for p in pages:
        if p["group"] != group:
            if group is not None:
                out.append("</ul></div>")
            group = p["group"]
            out.append('<div class="grp"><div class="grp-name">%s</div><ul>' % group)
        mark = ' aria-current="page"' if p["file"] == current else ""
        row = '<li><a%s href="%s">%s</a>' % (mark, p["file"], p["short"])
        if p["file"] == current and items:
            out.append(row)
            out.append(inpage_list(items))
            out.append("</li>")
        elif current == "index.html":
            out.append(row + "</li>")
        else:
            out.append(row)
            out.append("</li>")
    out.append("</ul></div>")
    out.append("</div></nav>")
    return NL.join(out)


def replace_block(text, opening, new):
    """<nav class="..."> から対応する </nav> までを差し替えます。

    **nav は入れ子になりません**（左の一覧の中にあるのは ul だけです）。最初の </nav> までを取ります。
    """
    i = text.index(opening)
    j = text.index("</nav>", i) + len("</nav>")
    return text[:i] + new + text[j:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "docs"))
    ap.add_argument("--check", action="store_true", help="書き換えず、差が出るページ名だけ出す")
    args = ap.parse_args()

    spec = json.load(io.open(os.path.join(HERE, "page-map.json"), encoding="utf-8"))
    pages = spec["pages"]

    targets = ["index.html"] + [p["file"] for p in pages]
    changed = []
    for i, name in enumerate(targets):
        path = os.path.join(args.dir, name)
        if not os.path.exists(path):
            raise SystemExit("ページがありません: %s（page-map.json と docs/ が食い違っています）" % name)
        text = io.open(path, encoding="utf-8").read()
        before = text

        if name == "index.html":
            items = INDEX_INPAGE
            prev, nxt = None, pages[0]
        else:
            items = inpage_items(text)
            k = i - 1
            prev = pages[k - 1] if k > 0 else None
            nxt = pages[k + 1] if k + 1 < len(pages) else None

        text = replace_block(text, '<nav class="sidebar"', sidebar_html(pages, name, items))

        pager = ['<nav class="pager" aria-label="前後のページ">']
        # **index.html には「← 目次」を出しません。** そのページ自身が目次です。
        if prev:
            pager.append('<a href="%s">← %s</a>' % (prev["file"], prev["short"]))
        elif name != "index.html":
            pager.append('<a href="index.html">← 目次</a>')
        if nxt:
            pager.append('<a href="%s">%s →</a>' % (nxt["file"], nxt["short"]))
        pager.append("</nav>")
        text = replace_block(text, '<nav class="pager"', NL.join(pager))

        nav = ['<nav class="pagenav" aria-label="前後のページ">']
        if name == "index.html":
            nav.append("<span></span>")
            nav.append('<a href="%s">%s →</a>' % (nxt["file"], nxt["h1"]))
        else:
            nav.append('<a href="%s">← %s</a>' % (prev["file"], prev["h1"]) if prev
                       else '<a href="index.html">← 目次</a>')
            nav.append('<a href="%s">%s →</a>' % (nxt["file"], nxt["h1"]) if nxt
                       else '<a href="index.html">目次へ戻る →</a>')
        nav.append("</nav>")
        text = replace_block(text, '<nav class="pagenav"', NL.join(nav))

        if text != before:
            changed.append(name)
            if not args.check:
                io.open(path, "w", encoding="utf-8", newline="").write(text)

    if args.check:
        print("差が出るページ %d 件: %s" % (len(changed), ", ".join(changed) or "なし"))
    else:
        print("左の一覧と前後リンクを %d ページで書き直しました（対象 %d ページ）"
              % (len(changed), len(targets)))


main()
