#!/usr/bin/env python3
"""Check relative links and #anchors across the repo's markdown files."""
import os
import re
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


def slug(text):
    text = text.strip().lower()
    text = re.sub(r"`|\*|_|\[|\]|\(|\)", "", text)
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"\s+", "-", text)
    return text


def anchors(path):
    out = set()
    counts = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = HEADING.match(line)
            if not m:
                continue
            base = slug(m.group(2))
            n = counts.get(base, 0)
            out.add(base if n == 0 else f"{base}-{n}")
            counts[base] = n + 1
    return out


def main():
    md_files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", "vendor", "models", "dist", "legacy"}]
        for name in filenames:
            if name.endswith(".md"):
                md_files.append(os.path.join(dirpath, name))

    broken = []
    checked = 0
    for path in sorted(md_files):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for raw in LINK.findall(text):
            if raw.startswith(("http://", "https://", "mailto:", "tel:")):
                continue
            target, _, frag = raw.partition("#")
            target = urllib.parse.unquote(target)
            dest = path if not target else os.path.normpath(os.path.join(os.path.dirname(path), target))
            checked += 1
            if not os.path.exists(dest):
                broken.append(f"{os.path.relpath(path, ROOT)}: missing {raw}")
                continue
            if frag and dest.endswith(".md"):
                if frag not in anchors(dest):
                    broken.append(f"{os.path.relpath(path, ROOT)}: bad anchor {raw}")

    print(f"checked {len(md_files)} files, {checked} relative links, {len(broken)} broken")
    for item in broken:
        print(" ", item)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
