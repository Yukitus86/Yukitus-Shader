#!/usr/bin/env python3
"""
Minimal Iris/OptiFine pipeline emulator used to test the Yukitus shader pack headlessly.

- compiles + links every program of every dimension (optionally with option overrides)
- renders a small voxel test scene through the full pipeline
  (shadow -> gbuffers opaque -> deferred -> gbuffers translucent -> composite* -> final)
  and writes PNG screenshots

Needs an X display (Xvfb) with Mesa, PyOpenGL, numpy and Pillow.
"""
import ctypes
import math
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHADERS = os.path.abspath(os.path.join(HERE, "..", "..", "shaders"))
GLCTX = os.environ.get("GLCTX_SO", "/tmp/claude-0/glctx.so")

os.environ.setdefault("DISPLAY", ":99")
os.environ.setdefault("PYOPENGL_PLATFORM", "glx")

W, H = int(os.environ.get("EMU_W", 960)), int(os.environ.get("EMU_H", 540))

_ctx = ctypes.CDLL(GLCTX)
if _ctx.init_ctx(W, H) != 0:
    raise SystemExit("could not create GL context")

from OpenGL.GL import *  # noqa: E402

#===================================================================================================
# Source handling
#===================================================================================================
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"', re.M)


def read_source(path, overrides, depth=0):
    if depth > 20:
        raise RuntimeError("include depth exceeded")
    with open(path) as fh:
        text = fh.read()
    if os.path.basename(path) == "settings.glsl":
        text = apply_overrides(text, overrides)

    def repl(m):
        inc = m.group(1)
        p = os.path.join(SHADERS, inc.lstrip("/")) if inc.startswith("/") else os.path.join(os.path.dirname(path), inc)
        return read_source(p, overrides, depth + 1)
    return INCLUDE_RE.sub(repl, text)


def apply_overrides(text, overrides):
    for name, val in (overrides or {}).items():
        if val is True:
            text, n = re.subn(r"^//\s*#define\s+%s\b" % name, "#define %s" % name, text, flags=re.M)
        elif val is False:
            text, n = re.subn(r"^#define\s+%s\b" % name, "//#define %s" % name, text, flags=re.M)
        else:
            text, n = re.subn(r"^(#define\s+%s\s+)\S+" % name, r"\g<1>%s" % val, text, flags=re.M)
            if n == 0:
                text, n = re.subn(r"^(const\s+\w+\s+%s\s*=\s*)[^;]+" % name, r"\g<1>%s" % val, text, flags=re.M)
        if n == 0 and val is not False:
            raise KeyError("unknown option " + name)
    return text


def parse_rendertargets(src):
    found = re.findall(r"/\*\s*(?:RENDERTARGETS|DRAWBUFFERS)\s*:\s*([0-9,\s]+)\*/", src)
    if len(found) > 1:
        raise RuntimeError("multiple RENDERTARGETS directives: " + str(found))
    if not found:
        return [0]
    s = found[0].strip()
    if "," in s:
        return [int(x) for x in s.split(",") if x.strip()]
    return [int(c) for c in s]


def parse_consts(src):
    consts = {}
    for m in re.finditer(r"const\s+(int|bool|float|vec4)\s+(\w+)\s*=\s*([^;]+);", src):
        consts[m.group(2)] = m.group(3).strip()
    return consts


#===================================================================================================
# GL helpers
#===================================================================================================
def _s(x):
    return x.decode(errors="replace") if isinstance(x, bytes) else str(x)


def compile_shader(src, stage, label):
    sh = glCreateShader(stage)
    glShaderSource(sh, src)
    glCompileShader(sh)
    ok = glGetShaderiv(sh, GL_COMPILE_STATUS)
    log = _s(glGetShaderInfoLog(sh))
    if not ok:
        raise RuntimeError(f"[{label}] compile error:\n{annotate(log, src)}")
    return sh, log


def annotate(log, src):
    lines = src.split("\n")
    out = []
    for l in log.strip().split("\n"):
        out.append(l)
        m = re.match(r"\d+:(\d+)\(\d+\)", l)
        if m:
            ln = int(m.group(1))
            if 0 < ln <= len(lines):
                out.append("    >> " + lines[ln - 1].strip())
    return "\n".join(out)


ATTRIBS = {"mc_Entity": 10, "mc_midTexCoord": 11, "at_tangent": 12}


class Program:
    def __init__(self, dim, name, overrides=None):
        self.name = name
        self.dim = dim
        base = os.path.join(SHADERS, dim, name)
        self.vsrc = read_source(base + ".vsh", overrides)
        self.fsrc = read_source(base + ".fsh", overrides)
        self.targets = parse_rendertargets(self.fsrc)
        self.consts = parse_consts(self.fsrc)
        vs, vlog = compile_shader(self.vsrc, GL_VERTEX_SHADER, f"{dim}/{name}.vsh")
        try:
            fs, flog = compile_shader(self.fsrc, GL_FRAGMENT_SHADER, f"{dim}/{name}.fsh")
        except Exception:
            glDeleteShader(vs)
            raise
        p = glCreateProgram()
        glAttachShader(p, vs)
        glAttachShader(p, fs)
        for a, loc in ATTRIBS.items():
            glBindAttribLocation(p, loc, a)
        for i in range(len(self.targets)):
            glBindFragDataLocation(p, i, f"outColor{i}")  # harmless when layout() is used
        glLinkProgram(p)
        glDetachShader(p, vs); glDetachShader(p, fs)
        glDeleteShader(vs); glDeleteShader(fs)
        if not glGetProgramiv(p, GL_LINK_STATUS):
            raise RuntimeError(f"[{dim}/{name}] link error:\n" + _s(glGetProgramInfoLog(p)))
        self.id = p
        self.warnings = (vlog + flog).strip()
        self.uniforms = {}
        n = glGetProgramiv(p, GL_ACTIVE_UNIFORMS)
        for i in range(n):
            uname, size, utype = glGetActiveUniform(p, i)
            uname = uname.decode() if isinstance(uname, bytes) else uname
            self.uniforms[uname] = (glGetUniformLocation(p, uname), utype)


#===================================================================================================
# Math
#===================================================================================================
def perspective(fov, aspect, n, f):
    t = 1.0 / math.tan(math.radians(fov) / 2)
    m = np.zeros((4, 4), np.float32)
    m[0, 0] = t / aspect
    m[1, 1] = t
    m[2, 2] = (f + n) / (n - f)
    m[2, 3] = 2 * f * n / (n - f)
    m[3, 2] = -1
    return m


def ortho(l, r, b, t, n, f):
    m = np.eye(4, dtype=np.float32)
    m[0, 0] = 2 / (r - l); m[1, 1] = 2 / (t - b); m[2, 2] = -2 / (f - n)
    m[0, 3] = -(r + l) / (r - l); m[1, 3] = -(t + b) / (t - b); m[2, 3] = -(f + n) / (f - n)
    return m


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]], np.float32)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]], np.float32)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], np.float32)


def translate(x, y, z):
    m = np.eye(4, dtype=np.float32)
    m[:3, 3] = [x, y, z]
    return m


def look_dir(d, up=(0, 1, 0)):
    """view matrix looking along d from the origin"""
    f = np.array(d, np.float64); f /= np.linalg.norm(f)
    u = np.array(up, np.float64)
    if abs(np.dot(f, u)) > 0.99:
        u = np.array([0, 0, 1.0])
    s = np.cross(f, u); s /= np.linalg.norm(s)
    u = np.cross(s, f)
    m = np.eye(4, dtype=np.float32)
    m[0, :3] = s; m[1, :3] = u; m[2, :3] = -f
    return m


#===================================================================================================
# Test scene
#===================================================================================================
TILE = 16
ATLAS_TILES = 8


def make_atlas():
    rng = np.random.default_rng(3)
    size = TILE * ATLAS_TILES
    atlas = np.zeros((size, size, 4), np.float32)

    def tile(i, fn):
        x0, y0 = (i % ATLAS_TILES) * TILE, (i // ATLAS_TILES) * TILE
        atlas[y0:y0 + TILE, x0:x0 + TILE] = fn()

    def noisy(c, amt):
        n = rng.uniform(-amt, amt, (TILE, TILE, 1))
        rgb = np.clip(np.array(c)[None, None, :] + n, 0, 1)
        return np.concatenate([rgb, np.ones((TILE, TILE, 1))], -1)

    tile(0, lambda: noisy([0.33, 0.47, 0.20], 0.06))           # grass top
    tile(1, lambda: noisy([0.46, 0.33, 0.23], 0.06))           # dirt
    tile(2, lambda: noisy([0.47, 0.47, 0.47], 0.06))           # stone

    def grass_side():
        t = noisy([0.46, 0.33, 0.23], 0.06)
        t[:4] = noisy([0.33, 0.47, 0.20], 0.06)[:4]
        return t
    tile(3, grass_side)
    tile(4, lambda: noisy([0.40, 0.30, 0.18], 0.06))           # log

    def leaves():
        t = noisy([0.20, 0.38, 0.12], 0.08)
        t[..., 3] = (rng.uniform(0, 1, (TILE, TILE)) > 0.25).astype(np.float32)
        return t
    tile(5, leaves)

    def water():
        t = noisy([0.75, 0.75, 0.75], 0.05)
        t[..., 3] = 0.72
        return t
    tile(6, water)

    def glass(c=(0.9, 0.95, 1.0), a=0.15):
        t = np.zeros((TILE, TILE, 4))
        t[..., :3] = c
        t[..., 3] = a
        t[0, :, 3] = t[-1, :, 3] = t[:, 0, 3] = t[:, -1, 3] = 0.9
        return t
    tile(7, glass)
    tile(8, lambda: noisy([0.86, 0.80, 0.58], 0.05))           # sand
    tile(9, lambda: noisy([0.95, 0.82, 0.45], 0.12))           # glowstone
    tile(10, lambda: glass((0.8, 0.15, 0.15), 0.55))           # red stained glass
    tile(11, lambda: noisy([0.82, 0.82, 0.84], 0.03))          # iron block

    def plant():
        t = np.zeros((TILE, TILE, 4))
        for x in range(1, TILE, 3):
            hgt = rng.integers(6, 15)
            t[TILE - hgt:, x, :3] = [0.32, 0.50, 0.20]
            t[TILE - hgt:, x, 3] = 1
        return t
    tile(12, plant)

    def ore():
        t = noisy([0.47, 0.47, 0.47], 0.06)
        for _ in range(6):
            x, y = rng.integers(1, 14, 2)
            t[y:y + 2, x:x + 2, :3] = [0.35, 0.9, 0.85]
        return t
    tile(13, ore)
    img = np.clip(atlas * 255 + 0.5, 0, 255).astype(np.uint8)
    return img


# block types: name -> (tiles [top, side, bottom], layer, id)
BLOCKS = {
    "grass": ((0, 3, 1), "solid", 10041),
    "dirt": ((1, 1, 1), "solid", 10041),
    "stone": ((2, 2, 2), "solid", 0),
    "log": ((4, 4, 4), "solid", 0),
    "leaves": ((5, 5, 5), "cutout", 10003),
    "water": ((6, 6, 6), "translucent", 10010),
    "glass": ((7, 7, 7), "translucent", 10012),
    "redglass": ((10, 10, 10), "translucent", 10012),
    "sand": ((8, 8, 8), "solid", 10041),
    "glowstone": ((9, 9, 9), "solid", 10022),
    "iron": ((11, 11, 11), "solid", 10030),
    "ore": ((13, 13, 13), "solid", 10024),
}

FACES = [  # normal, 4 corners (unit cube), tile index (0 top, 1 side, 2 bottom)
    ((0, 1, 0), [(0, 1, 1), (1, 1, 1), (1, 1, 0), (0, 1, 0)], 0),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], 2),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], 1),
    ((0, 0, -1), [(1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)], 1),
    ((1, 0, 0), [(1, 0, 1), (1, 0, 0), (1, 1, 0), (1, 1, 1)], 1),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)], 1),
]
FACE_UV = [(0, 1), (1, 1), (1, 0), (0, 0)]  # uv per corner (v=0 top of texture)


def build_world():
    world = {}
    R = 40
    heights = {}
    for x in range(-R, R):
        for z in range(-R - 30, R):
            h = 64 + 2.5 * math.sin(x * 0.13) * math.cos(z * 0.11) + 1.5 * math.sin((x + z) * 0.07)
            h = int(round(h))
            if (x - 2) ** 2 + (z + 8) ** 2 < 70:      # pond
                h = min(h, 60)
            heights[(x, z)] = h
            for y in range(56, h + 1):
                if y == h:
                    world[(x, y, z)] = "sand" if h <= 63 and (x - 2) ** 2 + (z + 8) ** 2 < 110 else "grass"
                elif y > h - 3:
                    world[(x, y, z)] = "dirt"
                else:
                    world[(x, y, z)] = "stone"
            for y in range(h + 1, 64):
                world[(x, y, z)] = "water"
    # trees
    for tx, tz in [(-10, -6), (12, -14), (-4, -24)]:
        h = heights[(tx, tz)]
        for y in range(h + 1, h + 6):
            world[(tx, y, tz)] = "log"
        for dx in range(-2, 3):
            for dz in range(-2, 3):
                for dy in range(3, 7):
                    if abs(dx) + abs(dz) + max(dy - 5, 0) * 2 <= 3 and (dx, dz) != (0, 0) or dy >= 6 and abs(dx) + abs(dz) <= 1:
                        world.setdefault((tx + dx, h + dy, tz + dz), "leaves")
    # glass wall, iron, glowstone, ore
    for y in range(1, 4):
        for x in range(6, 9):
            world[(x, heights[(x, 2)] + y, 2)] = "redglass" if x == 7 else "glass"
    world[(-3, heights[(-3, 6)] + 1, 6)] = "iron"
    world[(-3, heights[(-3, 6)] + 2, 6)] = "iron"
    world[(-6, heights[(-6, 4)] + 1, 4)] = "glowstone"
    world[(3, heights[(3, 8)] + 1, 8)] = "ore"
    return world, heights


def build_meshes(world, heights, cam):
    layers = {"solid": [], "cutout": [], "translucent": []}
    uvs = 1.0 / ATLAS_TILES
    glow = [p for p, b in world.items() if b == "glowstone"]

    def sky_at(p):
        x, y, z = p
        h = heights.get((x, z), 0)
        # leaves/logs above reduce skylight
        for yy in range(y, y + 8):
            b = world.get((x, yy, z))
            if b in ("leaves", "log"):
                return 12
        return 15 if y > h else 15

    def block_light_at(p):
        best = 0
        for g in glow:
            d = abs(g[0] - p[0]) + abs(g[1] - p[1]) + abs(g[2] - p[2])
            best = max(best, 15 - d)
        return max(best, 0)

    for pos, b in world.items():
        tiles, layer, bid = BLOCKS[b]
        for normal, corners, ti in FACES:
            npos = (pos[0] + normal[0], pos[1] + normal[1], pos[2] + normal[2])
            nb = world.get(npos)
            if nb is not None:
                nlayer = BLOCKS[nb][1]
                if b == "water" and nb == "water":
                    continue
                if layer != "translucent" and nlayer == "solid":
                    continue
                if layer == "translucent" and nb == b:
                    continue
                if b == "water" and nlayer != "translucent":
                    continue
            if b == "water" and normal != (0, 1, 0) and nb is None:
                pass
            tile = tiles[ti]
            tu, tv = (tile % ATLAS_TILES) * uvs, (tile // ATLAS_TILES) * uvs
            sky = sky_at(npos)
            blk = block_light_at(npos)
            lm = ((blk * 16 + 8) / 256.0, (sky * 16 + 8) / 256.0)
            color = (0.25, 0.46, 0.9, 1.0) if b == "water" else (1, 1, 1, 1)
            yofs = -0.1 if b == "water" and normal == (0, 1, 0) and world.get((pos[0], pos[1] + 1, pos[2])) is None else 0.0
            tangent = (1, 0, 0, 1) if normal[0] == 0 else (0, 0, 1, 1)
            quad = []
            for (cx, cy, cz), (u, v) in zip(corners, FACE_UV):
                px = pos[0] + cx - cam[0]
                py = pos[1] + cy + (yofs if cy == 1 else 0.0) - cam[1]
                pz = pos[2] + cz - cam[2]
                quad.append([px, py, pz, *color, tu + u * uvs, tv + v * uvs, *lm, *normal,
                             bid, 0, 0, 0, tu + 0.5 * uvs, tv + 0.5 * uvs, 0, 0, *tangent])
            layers[layer] += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
    # a few grass plants (cross quads)
    rng = np.random.default_rng(5)
    for (x, z), h in heights.items():
        if world.get((x, h, z)) == "grass" and world.get((x, h + 1, z)) is None and rng.uniform() < 0.12:
            tile = 12
            tu, tv = (tile % ATLAS_TILES) * uvs, (tile // ATLAS_TILES) * uvs
            lm = (8 / 256.0, (15 * 16 + 8) / 256.0)
            for (a, b2) in [((0, 0), (1, 1)), ((0, 1), (1, 0))]:
                p0 = (x + a[0], h + 1, z + a[1]); p1 = (x + b2[0], h + 1, z + b2[1])
                corners = [(p0[0], p0[1], p0[2]), (p1[0], p1[1], p1[2]), (p1[0], p1[1] + 1, p1[2]), (p0[0], p0[1] + 1, p0[2])]
                uv = [(0, 1), (1, 1), (1, 0), (0, 0)]
                quad = []
                for (cx, cy, cz), (u, v) in zip(corners, uv):
                    quad.append([cx - cam[0], cy - cam[1], cz - cam[2], 0.45, 0.8, 0.35, 1, tu + u * uvs, tv + v * uvs, *lm,
                                 0, 1, 0, 10001, 0, 0, 0, tu + 0.5 * uvs, tv + 0.5 * uvs, 0, 0, 1, 0, 0, 1])
                layers["cutout"] += [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
    out = {}
    for k, v in layers.items():
        out[k] = np.array(v, np.float32) if v else np.zeros((0, 26), np.float32)
    return out


class Mesh:
    STRIDE = 26 * 4

    def __init__(self, data):
        self.count = len(data)
        self.vbo = glGenBuffers(1)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        if self.count:
            glBufferData(GL_ARRAY_BUFFER, data.nbytes, data, GL_STATIC_DRAW)

    def draw(self):
        if not self.count:
            return
        s = self.STRIDE
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableClientState(GL_VERTEX_ARRAY)
        glVertexPointer(3, GL_FLOAT, s, ctypes.c_void_p(0))
        glEnableClientState(GL_COLOR_ARRAY)
        glColorPointer(4, GL_FLOAT, s, ctypes.c_void_p(12))
        glClientActiveTexture(GL_TEXTURE0)
        glEnableClientState(GL_TEXTURE_COORD_ARRAY)
        glTexCoordPointer(2, GL_FLOAT, s, ctypes.c_void_p(28))
        glClientActiveTexture(GL_TEXTURE1)
        glEnableClientState(GL_TEXTURE_COORD_ARRAY)
        glTexCoordPointer(2, GL_FLOAT, s, ctypes.c_void_p(36))
        glEnableClientState(GL_NORMAL_ARRAY)
        glNormalPointer(GL_FLOAT, s, ctypes.c_void_p(44))
        glEnableVertexAttribArray(10)
        glVertexAttribPointer(10, 4, GL_FLOAT, GL_FALSE, s, ctypes.c_void_p(56))
        glEnableVertexAttribArray(11)
        glVertexAttribPointer(11, 4, GL_FLOAT, GL_FALSE, s, ctypes.c_void_p(72))
        glEnableVertexAttribArray(12)
        glVertexAttribPointer(12, 4, GL_FLOAT, GL_FALSE, s, ctypes.c_void_p(88))
        glDrawArrays(GL_TRIANGLES, 0, self.count)
        for a in (10, 11, 12):
            glDisableVertexAttribArray(a)
        glClientActiveTexture(GL_TEXTURE1)
        glDisableClientState(GL_TEXTURE_COORD_ARRAY)
        glClientActiveTexture(GL_TEXTURE0)
        for c in (GL_VERTEX_ARRAY, GL_COLOR_ARRAY, GL_TEXTURE_COORD_ARRAY, GL_NORMAL_ARRAY):
            glDisableClientState(c)


#===================================================================================================
# Pipeline
#===================================================================================================
FORMATS = {"RGBA16F": (GL_RGBA16F, GL_FLOAT), "RGBA16": (GL_RGBA16, GL_UNSIGNED_SHORT),
           "RGBA8": (GL_RGBA8, GL_UNSIGNED_BYTE), "RGBA32F": (GL_RGBA32F, GL_FLOAT)}

GBUFFERS_OPAQUE = ["gbuffers_terrain"]
PROGRAM_ORDER_COMPOSITE = ["composite", "composite1", "composite2", "composite3", "composite4", "composite5"]


def make_tex(w, h, ifmt, fmt=GL_RGBA, typ=GL_FLOAT, filt=GL_LINEAR, data=None, mip=False):
    t = glGenTextures(1)
    glBindTexture(GL_TEXTURE_2D, t)
    glTexImage2D(GL_TEXTURE_2D, 0, ifmt, w, h, 0, fmt, typ, data)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR if mip else filt)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filt)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    return t


class Pipeline:
    def __init__(self, dim="world0", overrides=None):
        self.dim = dim
        self.overrides = overrides or {}
        self.programs = {}
        names = sorted(f[:-4] for f in os.listdir(os.path.join(SHADERS, dim)) if f.endswith(".fsh"))
        for n in names:
            self.programs[n] = Program(dim, n, self.overrides)
        allsrc = "".join(p.fsrc + p.vsrc for p in self.programs.values())
        self.consts = parse_consts(allsrc)
        self.shadow_res = int(self.consts.get("shadowMapResolution", "2048"))
        self.shadow_dist = float(self.consts.get("shadowDistance", "128.0"))
        self.sun_rot = float(self.consts.get("sunPathRotation", "0.0"))

    # ------------------------------------------------------------------ resources
    def setup(self):
        c = self.consts
        self.ctex = {}
        self.cur = {}
        self.fmt = {}
        for i in range(8):
            fmt = c.get(f"colortex{i}Format", "RGBA16F")
            ifmt, typ = FORMATS[fmt]
            self.fmt[i] = (ifmt, typ)
            self.ctex[i] = [make_tex(W, H, ifmt, typ=typ), make_tex(W, H, ifmt, typ=typ)]
            self.cur[i] = 0
        self.depth0 = make_tex(W, H, GL_DEPTH_COMPONENT32F, GL_DEPTH_COMPONENT, GL_FLOAT, GL_NEAREST)
        self.depth1 = make_tex(W, H, GL_DEPTH_COMPONENT32F, GL_DEPTH_COMPONENT, GL_FLOAT, GL_NEAREST)
        S = self.shadow_res
        self.shadow0 = make_tex(S, S, GL_DEPTH_COMPONENT32F, GL_DEPTH_COMPONENT, GL_FLOAT, GL_LINEAR)
        self.shadow1 = make_tex(S, S, GL_DEPTH_COMPONENT32F, GL_DEPTH_COMPONENT, GL_FLOAT, GL_LINEAR)
        for t in (self.shadow0, self.shadow1):
            glBindTexture(GL_TEXTURE_2D, t)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL)
        self.shadowcol = make_tex(S, S, GL_RGBA8, typ=GL_UNSIGNED_BYTE)
        self.final_tex = make_tex(W, H, GL_RGBA8, typ=GL_UNSIGNED_BYTE)
        self.fbo = glGenFramebuffers(1)

        atlas = make_atlas()
        self.atlas = make_tex(atlas.shape[1], atlas.shape[0], GL_RGBA8, typ=GL_UNSIGNED_BYTE,
                              filt=GL_NEAREST, data=atlas.tobytes())
        noise = Image.open(os.path.join(SHADERS, "textures", "noise.png")).convert("RGBA")
        self.noise = make_tex(noise.width, noise.height, GL_RGBA8, typ=GL_UNSIGNED_BYTE,
                              data=np.array(noise).tobytes())
        glBindTexture(GL_TEXTURE_2D, self.noise)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
        flat_n = np.array([[[128, 128, 255, 255]]], np.uint8)
        self.normals_tex = make_tex(1, 1, GL_RGBA8, typ=GL_UNSIGNED_BYTE, data=flat_n.tobytes())
        self.spec_tex = make_tex(1, 1, GL_RGBA8, typ=GL_UNSIGNED_BYTE, data=np.zeros((1, 1, 4), np.uint8).tobytes())

    def set_scene(self, cam=(0.5, 69.6, 20.0), yaw=0.0, pitch=-12.0, world=None):
        self.cam = np.array(cam, np.float32)
        world, heights = build_world() if world is None else world
        meshes = build_meshes(world, heights, cam)
        self.meshes = {k: Mesh(v) for k, v in meshes.items()}
        self.view = (rot_x(math.radians(-pitch)) @ rot_y(math.radians(yaw))).astype(np.float32)
        self.proj = perspective(70.0, W / H, 0.05, 192.0)

    # ------------------------------------------------------------------ uniforms
    def frame_uniforms(self, sun_angle, frame, rain=0.0, eye_in_water=0, time=10.0):
        view, proj = self.view, self.proj
        theta = sun_angle * 2 * math.pi
        rot = math.radians(self.sun_rot)
        sun_w = np.array([math.cos(theta), math.sin(theta) * math.cos(rot), math.sin(theta) * math.sin(rot)])
        sun_w /= np.linalg.norm(sun_w)
        moon_w = -sun_w
        light_w = sun_w if sun_angle < 0.5 else moon_w
        sm = look_dir(-light_w)
        shadow_mv = (translate(0, 0, -100.0) @ sm).astype(np.float32)
        shadow_proj = ortho(-self.shadow_dist, self.shadow_dist, -self.shadow_dist, self.shadow_dist, 0.05, 256.0)

        def vdir(d):
            return (view[:3, :3] @ d) * 100.0
        u = {
            "frameTimeCounter": time, "frameTime": 1.0, "frameCounter": frame,
            "viewWidth": float(W), "viewHeight": float(H), "aspectRatio": W / H, "near": 0.05, "far": 192.0,
            "cameraPosition": self.cam, "previousCameraPosition": self.cam,
            "gbufferModelView": view, "gbufferModelViewInverse": np.linalg.inv(view),
            "gbufferProjection": proj, "gbufferProjectionInverse": np.linalg.inv(proj),
            "gbufferPreviousModelView": view, "gbufferPreviousProjection": proj,
            "shadowModelView": shadow_mv, "shadowModelViewInverse": np.linalg.inv(shadow_mv),
            "shadowProjection": shadow_proj, "shadowProjectionInverse": np.linalg.inv(shadow_proj),
            "sunPosition": vdir(sun_w), "moonPosition": vdir(moon_w), "shadowLightPosition": vdir(light_w),
            "upPosition": vdir(np.array([0, 1.0, 0])), "sunAngle": sun_angle,
            "worldTime": int(sun_angle * 24000 - 6000) % 24000, "moonPhase": 0,
            "rainStrength": rain, "wetness": rain, "thunderStrength": 0.0, "isEyeInWater": eye_in_water,
            "eyeBrightnessSmooth": (0, 240), "nightVision": 0.0, "blindness": 0.0, "darknessFactor": 0.0,
            "screenBrightness": 0.5, "fogColor": (0.22, 0.04, 0.03) if self.dim == "world-1" else (0.6, 0.7, 1.0), "skyColor": (0.5, 0.7, 1.0),
            "heldBlockLightValue": 0, "heldBlockLightValue2": 0, "centerDepthSmooth": 0.99,
            "snowiness": 0.0, "entityColor": (0, 0, 0, 0), "entityId": 0, "blockEntityId": 0,
            "atlasSize": (TILE * ATLAS_TILES, TILE * ATLAS_TILES),
        }
        self.u = u

    def bind_program(self, prog, mv, pj):
        glUseProgram(prog.id)
        glMatrixMode(GL_PROJECTION)
        glLoadMatrixf(pj.T.flatten())
        glMatrixMode(GL_MODELVIEW)
        glLoadMatrixf(mv.T.flatten())
        glMatrixMode(GL_TEXTURE)
        for unit in (0, 1):
            glActiveTexture(GL_TEXTURE0 + unit)
            glLoadIdentity()
        glActiveTexture(GL_TEXTURE0)
        glMatrixMode(GL_MODELVIEW)

        samplers = {
            "gtexture": self.atlas, "noisetex": self.noise, "normals": self.normals_tex, "specular": self.spec_tex,
            "depthtex0": self.depth0, "depthtex1": self.depth1,
            "shadowtex0": self.shadow0, "shadowtex1": self.shadow1, "shadowcolor0": self.shadowcol,
        }
        for i in range(8):
            samplers[f"colortex{i}"] = self.ctex[i][self.cur[i]]
        unit = 0
        for name, (loc, typ) in prog.uniforms.items():
            if name in samplers:
                glActiveTexture(GL_TEXTURE0 + unit)
                glBindTexture(GL_TEXTURE_2D, samplers[name])
                glUniform1i(loc, unit)
                unit += 1
                continue
            if name.startswith("gl_"):
                continue
            if name not in self.u:
                raise KeyError(f"{prog.name}: unknown uniform {name}")
            v = self.u[name]
            if typ == GL_FLOAT:
                glUniform1f(loc, float(v))
            elif typ == GL_INT or typ == GL_BOOL:
                glUniform1i(loc, int(v))
            elif typ == GL_FLOAT_VEC3:
                glUniform3f(loc, *[float(x) for x in v])
            elif typ == GL_FLOAT_VEC4:
                glUniform4f(loc, *[float(x) for x in v])
            elif typ == GL_INT_VEC2:
                glUniform2i(loc, *[int(x) for x in v])
            elif typ == GL_FLOAT_MAT4:
                glUniformMatrix4fv(loc, 1, GL_TRUE, np.ascontiguousarray(v, np.float32))
            else:
                raise TypeError(f"uniform type {typ} for {name}")
        glActiveTexture(GL_TEXTURE0)

    def attach_targets(self, targets, depth=True, flip=False):
        glBindFramebuffer(GL_FRAMEBUFFER, self.fbo)
        bufs = []
        for i, t in enumerate(targets):
            idx = (1 - self.cur[t]) if flip else self.cur[t]
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, self.ctex[t][idx], 0)
            bufs.append(GL_COLOR_ATTACHMENT0 + i)
        for i in range(len(targets), 8):
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, 0, 0)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, self.depth0 if depth else 0, 0)
        glDrawBuffers(len(bufs), bufs)
        st = glCheckFramebufferStatus(GL_FRAMEBUFFER)
        assert st == GL_FRAMEBUFFER_COMPLETE, st

    def copy_depth(self, src, dst, w, h):
        rfbo, dfbo = glGenFramebuffers(2)
        glBindFramebuffer(GL_READ_FRAMEBUFFER, rfbo)
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, src, 0)
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, dfbo)
        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, dst, 0)
        glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_DEPTH_BUFFER_BIT, GL_NEAREST)
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glDeleteFramebuffers(2, [rfbo, dfbo])

    def fullscreen(self, name):
        prog = self.programs[name]
        targets = prog.targets
        # mipmaps
        for i in range(8):
            if prog.consts.get(f"colortex{i}MipmapEnabled") == "true":
                glBindTexture(GL_TEXTURE_2D, self.ctex[i][self.cur[i]])
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
                glGenerateMipmap(GL_TEXTURE_2D)
        is_final = name == "final"
        if is_final:
            glBindFramebuffer(GL_FRAMEBUFFER, self.fbo)
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.final_tex, 0)
            for i in range(1, 8):
                glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, 0, 0)
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, 0, 0)
            glDrawBuffers(1, [GL_COLOR_ATTACHMENT0])
        else:
            self.attach_targets(targets, depth=False, flip=True)
        glDisable(GL_DEPTH_TEST)
        glDisable(GL_BLEND)
        glDisable(GL_CULL_FACE)
        self.bind_program(prog, np.eye(4, dtype=np.float32), ortho(0, 1, 0, 1, -1, 1))
        glBegin(GL_QUADS)
        for x, y in ((0, 0), (1, 0), (1, 1), (0, 1)):
            glMultiTexCoord2f(GL_TEXTURE0, x, y)
            glVertex3f(x, y, 0)
        glEnd()
        if not is_final:
            for t in targets:
                self.cur[t] = 1 - self.cur[t]
        for i in range(8):
            glBindTexture(GL_TEXTURE_2D, self.ctex[i][self.cur[i]])
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)

    def gbuffer(self, name, meshes, blend=False, cull=True):
        prog = self.programs.get(name)
        if prog is None:
            return
        self.attach_targets(prog.targets)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glDepthMask(GL_TRUE)
        if cull:
            glEnable(GL_CULL_FACE)
            glCullFace(GL_BACK)
        else:
            glDisable(GL_CULL_FACE)
        if blend:
            glEnablei(GL_BLEND, 0)
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
            for i in range(1, 8):
                glDisablei(GL_BLEND, i)
        else:
            glDisable(GL_BLEND)
        self.bind_program(prog, self.view, self.proj)
        for m in meshes:
            self.meshes[m].draw()
        glDisable(GL_BLEND)

    def shadow_pass(self):
        prog = self.programs.get("shadow")
        if prog is None:
            return
        S = self.shadow_res
        glBindFramebuffer(GL_FRAMEBUFFER, self.fbo)
        for i in range(8):
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, 0, 0)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.shadowcol, 0)
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, self.shadow0, 0)
        glDrawBuffers(1, [GL_COLOR_ATTACHMENT0])
        glViewport(0, 0, S, S)
        glClearColor(1, 1, 1, 1)
        glClearDepth(1.0)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glEnable(GL_DEPTH_TEST)
        glDisable(GL_CULL_FACE)
        glDisable(GL_BLEND)
        u = self.u
        self.bind_program(prog, u["shadowModelView"], u["shadowProjection"])
        self.meshes["solid"].draw()
        self.meshes["cutout"].draw()
        self.copy_depth(self.shadow0, self.shadow1, S, S)
        glBindFramebuffer(GL_FRAMEBUFFER, self.fbo)
        self.bind_program(prog, u["shadowModelView"], u["shadowProjection"])
        self.meshes["translucent"].draw()
        glViewport(0, 0, W, H)

    def render_frame(self, sun_angle, frame, **kw):
        self.frame_uniforms(sun_angle, frame, **kw)
        glViewport(0, 0, W, H)
        # clear
        for i in range(8):
            if self.consts.get(f"colortex{i}Clear", "true") == "false":
                continue
            cc = self.consts.get(f"colortex{i}ClearColor", "vec4(0.0)")
            vals = [float(x) for x in re.findall(r"[-\d.]+", cc.replace("vec4", ""))]
            if len(vals) == 1:
                vals *= 4
            self.attach_targets([i], depth=False)
            glClearColor(*vals)
            glClear(GL_COLOR_BUFFER_BIT)
        self.attach_targets([0], depth=True)
        glClearDepth(1.0)
        glClear(GL_DEPTH_BUFFER_BIT)

        self.shadow_pass()
        self.gbuffer("gbuffers_skybasic", [], blend=True)
        self.gbuffer("gbuffers_terrain", ["solid"], blend=False, cull=True)
        self.gbuffer("gbuffers_terrain", ["cutout"], blend=False, cull=False)
        self.copy_depth(self.depth0, self.depth1, W, H)
        if "deferred" in self.programs:
            self.fullscreen("deferred")
        self.gbuffer("gbuffers_water", ["translucent"], blend=True, cull=False)
        for n in PROGRAM_ORDER_COMPOSITE:
            if n in self.programs:
                self.fullscreen(n)
        self.fullscreen("final")

    def read_final(self):
        glBindFramebuffer(GL_READ_FRAMEBUFFER, self.fbo)
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.final_tex, 0)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        data = glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE)
        img = np.frombuffer(data, np.uint8).reshape(H, W, 4)[::-1]
        return img

    def read_colortex(self, i):
        glBindFramebuffer(GL_READ_FRAMEBUFFER, self.fbo)
        glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.ctex[i][self.cur[i]], 0)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        data = glReadPixels(0, 0, W, H, GL_RGBA, GL_FLOAT)
        return np.frombuffer(data, np.float32).reshape(H, W, 4)[::-1]


#===================================================================================================
# CLI
#===================================================================================================
def compile_all(overrides=None, dims=("world0", "world-1", "world1")):
    errors = []
    count = 0
    for d in dims:
        for f in sorted(os.listdir(os.path.join(SHADERS, d))):
            if not f.endswith(".fsh"):
                continue
            try:
                p = Program(d, f[:-4], overrides)
                glDeleteProgram(p.id)
                count += 1
            except Exception as e:  # noqa: BLE001
                errors.append(str(e))
    return count, errors


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["compile", "render"])
    ap.add_argument("--out", default="/tmp/claude-0/renders")
    ap.add_argument("--dim", default="world0")
    ap.add_argument("--times", default="0.03,0.2,0.46,0.7")
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--rain", type=float, default=0.0)
    ap.add_argument("--water", type=int, default=0)
    ap.add_argument("--set", action="append", default=[], help="NAME=value option override")
    ap.add_argument("--tag", default="")
    ap.add_argument("--yaw", type=float, default=0.0)
    ap.add_argument("--pitch", type=float, default=-12.0)
    ap.add_argument("--camy", type=float, default=69.6)
    ap.add_argument("--camx", type=float, default=0.5)
    ap.add_argument("--camz", type=float, default=20.0)
    args = ap.parse_args()

    overrides = {}
    for s in args.set:
        k, v = s.split("=", 1)
        overrides[k] = True if v == "on" else False if v == "off" else v

    if args.mode == "compile":
        n, errs = compile_all(overrides)
        for e in errs:
            print(e)
            print("-" * 80)
        print(f"compiled {n} programs, {len(errs)} errors")
        sys.exit(1 if errs else 0)

    os.makedirs(args.out, exist_ok=True)
    pipe = Pipeline(args.dim, overrides)
    pipe.setup()
    pipe.set_scene(cam=(args.camx, args.camy, args.camz), yaw=args.yaw, pitch=args.pitch)
    for t in [float(x) for x in args.times.split(",")]:
        for f in range(args.frames):
            pipe.render_frame(t, f, rain=args.rain, eye_in_water=args.water, time=10.0 + f / 60.0)
        img = pipe.read_final()
        c0 = pipe.read_colortex(0)
        bad = int(np.count_nonzero(~np.isfinite(c0)))
        path = os.path.join(args.out, f"{args.dim}_{args.tag}t{t:.2f}.png")
        Image.fromarray(img[..., :3]).save(path)
        c6 = pipe.read_colortex(6)
        print(f"{path}: mean={img[..., :3].mean():.1f} nonfinite(colortex0)={bad} exposure={c6[0,0,3]:.3f} hdrMean={c0[..., :3].mean():.3f}")


if __name__ == "__main__":
    main()
