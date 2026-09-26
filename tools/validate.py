#!/usr/bin/env python3
"""Static consistency checks for the shader pack options, menus, profiles and lang files."""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders")
errors = []

settings = open(os.path.join(ROOT, "lib", "settings.glsl")).read()
props = open(os.path.join(ROOT, "shaders.properties")).read()

options = {}  # name -> (default, values or None for bool)
for m in re.finditer(r"^(//)?#define[ \t]+(\w+)(?:[ \t]+([^\s/]+))?[ \t]*(?://[ \t]*\[([^\]]*)\])?", settings, re.M):
    commented, name, default, values = m.groups()
    if name.endswith("_GLSL"):
        continue
    if default is None:
        options[name] = ("off" if commented else "on", None)
    elif values is not None:
        options[name] = (default, values.split())
for m in re.finditer(r"^const\s+\w+\s+(\w+)\s*=\s*([^;]+);\s*//\s*\[([^\]]*)\]", settings, re.M):
    options[m.group(1)] = (m.group(2).strip(), m.group(3).split())

for name, (default, values) in options.items():
    if values is not None and default not in values:
        errors.append(f"default of {name} ({default}) not in {values}")

def prop(key):
    m = re.search(r"^%s\s*=\s*(.*)$" % re.escape(key), props, re.M)
    return m.group(1).split() if m else []

screen_items = set()
for m in re.finditer(r"^screen(\.\w+)?\s*=\s*(.*)$", props, re.M):
    if m.group(1) == ".columns":
        continue
    for item in m.group(2).split():
        if item.startswith("[") or item.startswith("<"):
            continue
        screen_items.add(item)
        if item not in options:
            errors.append(f"screen item {item} is not an option")
for name in options:
    if name not in screen_items:
        errors.append(f"option {name} not reachable in any screen")
for sub in re.findall(r"\[(\w+)\]", props):
    if not re.search(r"^screen\.%s\s*=" % sub, props, re.M):
        errors.append(f"sub screen {sub} not defined")

for s in prop("sliders"):
    if s not in options:
        errors.append(f"slider {s} is not an option")
    elif options[s][1] is None:
        errors.append(f"slider {s} is a boolean")

for m in re.finditer(r"^profile\.(\w+)\s*=\s*(.*)$", props, re.M):
    for item in m.group(2).split():
        n = item.lstrip("!").split("=")[0]
        if n not in options:
            errors.append(f"profile {m.group(1)}: unknown option {n}")
        elif "=" in item:
            v = item.split("=", 1)[1]
            if options[n][1] is None or v not in options[n][1]:
                errors.append(f"profile {m.group(1)}: invalid value {item}")
        elif options[n][1] is not None:
            errors.append(f"profile {m.group(1)}: {n} is not boolean")

for lang in ("en_US.lang", "de_DE.lang"):
    text = open(os.path.join(ROOT, "lang", lang), encoding="utf-8").read()
    for name in options:
        if f"option.{name}=" not in text:
            errors.append(f"{lang}: missing option.{name}")
    for sub in re.findall(r"\[(\w+)\]", props):
        if f"screen.{sub}=" not in text:
            errors.append(f"{lang}: missing screen.{sub}")

# every program referenced by the wrappers exists
for dim in ("world0", "world-1", "world1"):
    for f in os.listdir(os.path.join(ROOT, dim)):
        src = open(os.path.join(ROOT, dim, f)).read()
        if not src.startswith("#version"):
            errors.append(f"{dim}/{f}: #version must be the first line")
        for inc in re.findall(r'#include\s+"([^"]+)"', src):
            if not os.path.exists(os.path.join(ROOT, inc.lstrip("/"))):
                errors.append(f"{dim}/{f}: missing include {inc}")

for e in errors:
    print("ERROR:", e)
print(f"{len(options)} options checked, {len(errors)} errors")
sys.exit(1 if errors else 0)
