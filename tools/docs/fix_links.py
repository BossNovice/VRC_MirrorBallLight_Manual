# -*- coding: utf-8 -*-
"""組み直す前のページ名を指すリンクを、新しいページへ張り替えます。

build_docs.py が書いた legacy-map.json（旧ページ#旧節ID → 新ページ#新節ID）を使います。
アンカーが無いリンクは、そのページの節がいちばん多く移った先へ向けます。

    python tools/docs/fix_links.py --dir docs
"""
import argparse, collections, io, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "docs"))
    ap.add_argument("--map", default=os.path.join(HERE, "legacy-map.json"))
    args = ap.parse_args()

    mapping = json.load(io.open(args.map, encoding="utf-8"))
    per_page = collections.defaultdict(collections.Counter)
    for src, dst in mapping.items():
        per_page[src.split("#")[0]][dst.split("#")[0]] += 1
    primary = {old: c.most_common(1)[0][0] for old, c in per_page.items()}

    fixed = collections.Counter()
    unresolved = collections.Counter()
    for path in sorted(os.listdir(args.dir)):
        if not path.endswith(".html"):
            continue
        full = os.path.join(args.dir, path)
        text = io.open(full, encoding="utf-8").read()
        before = text

        def rep(mo):
            href = mo.group(1)
            page, _, anchor = href.partition("#")
            if not page or os.path.exists(os.path.join(args.dir, page)):
                return mo.group(0)
            key = "%s#%s" % (page, anchor) if anchor else None
            if key and key in mapping:
                fixed[key] += 1
                return 'href="%s"' % mapping[key]
            if page in primary:
                new = primary[page]
                if anchor:
                    new = "%s#%s" % (new, anchor)
                fixed[page] += 1
                return 'href="%s"' % new
            if "/" not in page:
                # assets/ 配下などは組み直しの対象外なので数えません。
                unresolved[href] += 1
            return mo.group(0)

        text = re.sub(r'href="([^"]+\.html(?:#[^"]*)?)"', rep, text)
        if text != before:
            io.open(full, "w", encoding="utf-8", newline="").write(text)

    print("張り替え %d 件（種類 %d）" % (sum(fixed.values()), len(fixed)))
    if unresolved:
        print("行き先が分からなかったリンク:", dict(unresolved))


main()
