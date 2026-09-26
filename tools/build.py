#!/usr/bin/env python3
"""Builds the release shader pack zip (shaders/ folder + license/readme) into dist/."""
import os
import zipfile

VERSION = "1.0.1"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
OUT = os.path.join(REPO, "dist", f"Yukitus-Shader-v{VERSION}.zip")


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    count = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for base, _, files in os.walk(os.path.join(REPO, "shaders")):
            for f in sorted(files):
                full = os.path.join(base, f)
                rel = os.path.relpath(full, REPO).replace(os.sep, "/")
                z.write(full, rel)
                count += 1
        for extra in ("LICENSE", "README.md"):
            p = os.path.join(REPO, extra)
            if os.path.exists(p):
                z.write(p, extra)
                count += 1
    print(f"wrote {OUT} ({count} files, {os.path.getsize(OUT) // 1024} KiB)")


if __name__ == "__main__":
    main()
