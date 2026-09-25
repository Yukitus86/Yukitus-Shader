"""Compile every program with every boolean option flipped and every enum value."""
import re, os, sys, time
sys.argv = [sys.argv[0]]
import iris_emu as E

settings = open(os.path.join(E.SHADERS, "lib", "settings.glsl")).read()
configs = []
for m in re.finditer(r"^(//)?#define[ \t]+(\w+)[ \t]*$", settings, re.M):
    name = m.group(2)
    if name.endswith("_GLSL"): continue
    configs.append({name: bool(m.group(1))})  # flip
for m in re.finditer(r"^#define[ \t]+(\w+)[ \t]+(\d+)[ \t]*//[ \t]*\[([^\]]*)\]", settings, re.M):
    name, default, vals = m.group(1), m.group(2), m.group(3).split()
    for v in vals:
        if v != default and re.fullmatch(r"\d+", v):
            configs.append({name: v})
# a couple of combined "everything off"/"everything on" configs
configs.append({"SHADOWS": False, "VOLUMETRIC_CLOUDS": False, "TAA": False, "BLOOM": False, "SSAO": False, "VOLUMETRIC_LIGHT": False, "AUTO_EXPOSURE": False})
configs.append({"DEPTH_OF_FIELD": True, "MOTION_BLUR": True, "GENERATED_NORMALS": True, "PBR_MODE": "1", "SHADOW_FILTER": "3"})
t = time.time()
fails = 0
start = int(os.environ.get('START', 0))
for cfg in configs[start:]:
    n, errs = E.compile_all(cfg)
    status = "ok" if not errs else f"{len(errs)} ERRORS"
    print(f"{cfg}: {n} programs {status}", flush=True)
    for e in errs[:3]:
        print(e[:1500])
    fails += len(errs)
print(f"{len(configs)} configs, {fails} failures, {time.time()-t:.0f}s")
sys.exit(1 if fails else 0)
