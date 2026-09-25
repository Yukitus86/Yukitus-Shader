#!/usr/bin/env python3
"""
Yukitus Shader - generator for per-dimension program wrappers, block.properties and the noise texture.
Run from the repository root:  python3 tools/generate.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders")

# program name -> (source file, extra defines)
PROGRAMS = {
    "shadow":                   ("shadow.glsl", []),
    "gbuffers_basic":           ("gbuffers_unlit.glsl", ["GB_BASIC"]),
    "gbuffers_textured":        ("gbuffers_particles.glsl", ["GB_TEXTURED"]),
    "gbuffers_textured_lit":    ("gbuffers_particles.glsl", ["GB_TEXTURED"]),
    "gbuffers_skybasic":        ("gbuffers_unlit.glsl", ["GB_SKYBASIC"]),
    "gbuffers_skytextured":     ("gbuffers_unlit.glsl", ["GB_SKYTEXTURED"]),
    "gbuffers_clouds":          ("gbuffers_unlit.glsl", ["GB_CLOUDS"]),
    "gbuffers_terrain":         ("gbuffers_solid.glsl", ["GB_TERRAIN"]),
    "gbuffers_block":           ("gbuffers_solid.glsl", ["GB_BLOCK"]),
    "gbuffers_entities":        ("gbuffers_solid.glsl", ["GB_ENTITIES"]),
    "gbuffers_entities_glowing":("gbuffers_solid.glsl", ["GB_ENTITIES"]),
    "gbuffers_hand":            ("gbuffers_solid.glsl", ["GB_HAND"]),
    "gbuffers_water":           ("gbuffers_translucent.glsl", ["GB_WATER"]),
    "gbuffers_hand_water":      ("gbuffers_translucent.glsl", ["GB_HAND_WATER"]),
    "gbuffers_weather":         ("gbuffers_weather.glsl", []),
    "gbuffers_beaconbeam":      ("gbuffers_unlit.glsl", ["GB_BEACON"]),
    "gbuffers_spidereyes":      ("gbuffers_unlit.glsl", ["GB_SPIDEREYES"]),
    "gbuffers_armor_glint":     ("gbuffers_unlit.glsl", ["GB_GLINT"]),
    "gbuffers_damagedblock":    ("gbuffers_unlit.glsl", ["GB_DAMAGED"]),
    "deferred":                 ("deferred.glsl", []),
    "composite":                ("composite.glsl", []),
    "composite1":               ("composite1.glsl", []),
    "composite2":               ("composite2.glsl", []),
    "composite3":               ("composite3.glsl", []),
    "composite4":               ("composite_blur.glsl", ["BLUR_H"]),
    "composite5":               ("composite_blur.glsl", ["BLUR_V"]),
    "final":                    ("final.glsl", []),
}

DIMENSIONS = {
    "world0": ("OVERWORLD", True),
    "world-1": ("NETHER", False),
    "world1": ("END", True),
}


def write_wrappers():
    for folder, (dim_define, has_shadows) in DIMENSIONS.items():
        d = os.path.join(ROOT, folder)
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            if f.endswith((".vsh", ".fsh")):
                os.remove(os.path.join(d, f))
        for name, (src, defines) in PROGRAMS.items():
            if name == "shadow" and not has_shadows:
                continue
            for stage, ext in (("VSH", "vsh"), ("FSH", "fsh")):
                lines = ["#version 330 compatibility", f"#define {dim_define}", f"#define {stage}"]
                lines += [f"#define {x}" for x in defines]
                lines.append(f'#include "/program/{src}"')
                with open(os.path.join(d, f"{name}.{ext}"), "w", newline="\n") as fh:
                    fh.write("\n".join(lines) + "\n")


#---------------------------------------------------------------------------------------------------
# block.properties
#---------------------------------------------------------------------------------------------------
WOODS = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak"]
COLORS = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray",
          "cyan", "purple", "blue", "brown", "green", "red", "black"]
COPPER_STAGES = ["", "exposed_", "weathered_", "oxidized_"]


def copper(names):
    out = []
    for n in names:
        for st in COPPER_STAGES:
            out.append(st + n)
            out.append("waxed_" + st + n)
    return out


def tall(name):
    return [f"{name}:half=lower"], [f"{name}:half=upper"]


BLOCKS = {}

short_plants = ["short_grass", "grass", "fern", "dead_bush", "dandelion", "poppy", "blue_orchid", "allium",
                "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy",
                "cornflower", "lily_of_the_valley", "wither_rose", "torchflower", "sweet_berry_bush",
                "crimson_roots", "warped_roots", "nether_sprouts", "open_eyeblossom", "closed_eyeblossom",
                "bush", "short_dry_grass", "tall_dry_grass", "firefly_bush", "cactus_flower", "seagrass",
                "pink_petals", "wildflowers", "mangrove_propagule", "small_dripleaf", "hanging_roots",
                ] + [f"{w}_sapling" for w in WOODS if w not in ("mangrove",)] + ["azalea_sapling"]
lower_half, upper_half = [], []
for t in ["tall_grass", "large_fern", "sunflower", "lilac", "rose_bush", "peony", "pitcher_plant", "tall_seagrass"]:
    lo, up = tall(t)
    lower_half += lo
    upper_half += up

BLOCKS[10001] = short_plants + lower_half
BLOCKS[10002] = upper_half
BLOCKS[10003] = [f"{w}_leaves" for w in WOODS] + ["azalea_leaves", "flowering_azalea_leaves"]
BLOCKS[10004] = ["vine", "weeping_vines", "weeping_vines_plant", "twisting_vines", "twisting_vines_plant",
                 "cave_vines:berries=false", "cave_vines_plant:berries=false", "pale_hanging_moss"]
BLOCKS[10005] = ["wheat", "carrots", "potatoes", "beetroots", "torchflower_crop", "pitcher_crop", "nether_wart"]
BLOCKS[10006] = ["lily_pad"]
BLOCKS[10007] = ["sugar_cane", "kelp", "kelp_plant", "bamboo", "big_dripleaf", "big_dripleaf_stem",
                 "spore_blossom", "moss_carpet", "pale_moss_carpet", "leaf_litter", "azalea", "flowering_azalea",
                 "cactus", "melon_stem", "pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem",
                 "sea_pickle", "brown_mushroom", "red_mushroom", "crimson_fungus", "warped_fungus"]

BLOCKS[10010] = ["water", "flowing_water", "bubble_column"]
BLOCKS[10011] = ["ice", "frosted_ice", "packed_ice", "blue_ice"]
BLOCKS[10012] = ["glass", "glass_pane", "tinted_glass"] + [f"{c}_stained_glass" for c in COLORS] + \
                [f"{c}_stained_glass_pane" for c in COLORS]
BLOCKS[10013] = ["slime_block", "honey_block"]
BLOCKS[10014] = ["nether_portal"]

BLOCKS[10020] = ["lava", "flowing_lava"]
BLOCKS[10021] = ["fire", "campfire:lit=true"]
BLOCKS[10022] = ["glowstone", "sea_lantern", "shroomlight", "redstone_lamp:lit=true", "ochre_froglight",
                 "verdant_froglight", "pearlescent_froglight", "beacon", "end_rod", "conduit",
                 "respawn_anchor:charges=1", "respawn_anchor:charges=2", "respawn_anchor:charges=3",
                 "respawn_anchor:charges=4", "copper_bulb:lit=true", "exposed_copper_bulb:lit=true",
                 "weathered_copper_bulb:lit=true", "oxidized_copper_bulb:lit=true", "waxed_copper_bulb:lit=true",
                 "waxed_exposed_copper_bulb:lit=true", "waxed_weathered_copper_bulb:lit=true",
                 "waxed_oxidized_copper_bulb:lit=true", "light", "creaking_heart:creaking_heart_state=awake"]
BLOCKS[10023] = ["torch", "wall_torch", "lantern", "jack_o_lantern", "furnace:lit=true", "blast_furnace:lit=true",
                 "smoker:lit=true", "candle:lit=true", "cake_with_candles:lit=true"] + \
                [f"{c}_candle:lit=true" for c in COLORS] + \
                [f"{c}_candle_cake:lit=true" for c in COLORS] + ["candle_cake:lit=true"]
BLOCKS[10024] = ["coal_ore", "iron_ore", "gold_ore", "diamond_ore", "emerald_ore", "lapis_ore", "redstone_ore",
                 "copper_ore", "deepslate_coal_ore", "deepslate_iron_ore", "deepslate_gold_ore",
                 "deepslate_diamond_ore", "deepslate_emerald_ore", "deepslate_lapis_ore", "deepslate_redstone_ore",
                 "deepslate_copper_ore", "nether_gold_ore", "nether_quartz_ore", "ancient_debris",
                 "gilded_blackstone"]
BLOCKS[10025] = ["magma_block"]
BLOCKS[10026] = ["amethyst_cluster", "large_amethyst_bud", "medium_amethyst_bud", "small_amethyst_bud",
                 "amethyst_block", "budding_amethyst", "calibrated_sculk_sensor"]
BLOCKS[10030] = ["iron_block", "gold_block", "netherite_block", "anvil", "chipped_anvil", "damaged_anvil",
                 "iron_bars", "chain", "iron_chain", "iron_door", "iron_trapdoor", "cauldron", "water_cauldron",
                 "lava_cauldron", "powder_snow_cauldron", "hopper", "heavy_core", "bell", "raw_gold_block",
                 "heavy_weighted_pressure_plate", "light_weighted_pressure_plate"] + \
                copper(["copper_block", "cut_copper", "cut_copper_stairs", "cut_copper_slab", "chiseled_copper",
                        "copper_grate", "copper_door", "copper_trapdoor", "copper_bulb", "lightning_rod",
                        "copper_bars", "copper_chain", "copper_chest", "copper_golem_statue"])
BLOCKS[10031] = ["polished_andesite", "polished_diorite", "polished_granite", "polished_deepslate",
                 "polished_blackstone", "polished_tuff", "polished_basalt", "smooth_stone", "smooth_stone_slab",
                 "smooth_quartz", "smooth_quartz_stairs", "smooth_quartz_slab", "quartz_block", "quartz_bricks",
                 "quartz_pillar", "chiseled_quartz_block", "quartz_stairs", "quartz_slab", "calcite",
                 "polished_andesite_stairs", "polished_andesite_slab", "polished_diorite_stairs",
                 "polished_diorite_slab", "polished_granite_stairs", "polished_granite_slab",
                 "prismarine_bricks", "dark_prismarine", "purpur_block", "purpur_pillar",
                 "resin_bricks", "chiseled_resin_bricks"] + \
                [f"{c}_concrete" for c in COLORS] + [f"{c}_glazed_terracotta" for c in COLORS]
BLOCKS[10032] = ["diamond_block", "emerald_block", "lapis_block"]
BLOCKS[10033] = ["obsidian", "crying_obsidian"]
BLOCKS[10040] = ["snow", "snow_block", "powder_snow"]
BLOCKS[10041] = ["grass_block", "dirt", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "sand", "red_sand",
                 "gravel", "farmland", "dirt_path", "moss_block", "pale_moss_block", "mud", "muddy_mangrove_roots",
                 "clay", "suspicious_sand", "suspicious_gravel", "soul_sand", "soul_soil"]
BLOCKS[10050] = ["redstone_torch:lit=true", "redstone_wall_torch:lit=true", "redstone_block",
                 "repeater:powered=true", "comparator:powered=true", "redstone_ore:lit=true",
                 "deepslate_redstone_ore:lit=true"] + [f"redstone_wire:power={p}" for p in range(1, 16)]
BLOCKS[10051] = ["soul_torch", "soul_wall_torch", "soul_lantern", "soul_fire", "soul_campfire:lit=true"]
BLOCKS[10060] = ["end_portal", "end_gateway"]
BLOCKS[10061] = ["glow_lichen", "cave_vines:berries=true", "cave_vines_plant:berries=true"]
BLOCKS[10062] = ["sculk", "sculk_vein", "sculk_catalyst", "sculk_shrieker", "sculk_sensor"]
BLOCKS[10070] = ["copper_torch", "copper_wall_torch", "copper_lantern", "exposed_copper_lantern",
                 "weathered_copper_lantern", "oxidized_copper_lantern", "waxed_copper_lantern",
                 "waxed_exposed_copper_lantern", "waxed_weathered_copper_lantern", "waxed_oxidized_copper_lantern"]


def write_properties():
    seen = {}
    lines = ["# Yukitus Shader - block ids (generated by tools/generate.py)",
             "# 10001 plants (bottom anchored)  10002 tall plant upper half  10003 leaves  10004 vines",
             "# 10005 crops  10006 lily pad  10007 other foliage  10010 water  10011 ice  10012 glass",
             "# 10013 slime/honey  10014 nether portal  10020 lava  10021 fire  10022 light blocks",
             "# 10023 torches/lanterns  10024 ores  10025 magma  10026 amethyst  10030 metal",
             "# 10031 polished  10032 gems  10033 obsidian  10040 snow  10041 porous  10050 redstone  10051 soul light",
             "# 10060 end portal  10061 glow lichen/berries  10062 sculk  10070 copper light", ""]
    for bid, names in BLOCKS.items():
        uniq = []
        for n in names:
            if n in seen:
                raise SystemExit(f"duplicate block {n} in {bid} and {seen[n]}")
            seen[n] = bid
            uniq.append(n if ":" in n and n.startswith("minecraft:") else "minecraft:" + n)
        lines.append(f"block.{bid}=" + " ".join(uniq))
        lines.append("")
    with open(os.path.join(ROOT, "block.properties"), "w", newline="\n") as fh:
        fh.write("\n".join(lines))


#---------------------------------------------------------------------------------------------------
# noise texture (tileable)
#---------------------------------------------------------------------------------------------------
def perlin(size, freq, seed):
    rng = np.random.default_rng(seed)
    ang = rng.uniform(0, 2 * np.pi, (freq, freq))
    gx, gy = np.cos(ang), np.sin(ang)
    lin = np.arange(size) * freq / size
    x, y = np.meshgrid(lin, lin, indexing="xy")
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int)
    fx = x - x0; fy = y - y0
    x1 = (x0 + 1) % freq; y1 = (y0 + 1) % freq
    x0 %= freq; y0 %= freq

    def dot(ix, iy, dx, dy):
        return gx[iy, ix] * dx + gy[iy, ix] * dy
    n00 = dot(x0, y0, fx, fy)
    n10 = dot(x1, y0, fx - 1, fy)
    n01 = dot(x0, y1, fx, fy - 1)
    n11 = dot(x1, y1, fx - 1, fy - 1)
    u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    nx0 = n00 + u * (n10 - n00)
    nx1 = n01 + u * (n11 - n01)
    return nx0 + v * (nx1 - nx0)


def fbm(size, freq, octaves, seed):
    total = np.zeros((size, size))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += perlin(size, freq * 2 ** o, seed + o) * amp
        norm += amp
        amp *= 0.5
    total /= norm
    total = (total - total.min()) / (total.max() - total.min())
    return total


def worley(size, freq, seed):
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, 1, (freq, freq, 2))
    lin = (np.arange(size) + 0.5) * freq / size
    x, y = np.meshgrid(lin, lin, indexing="xy")
    cx = np.floor(x).astype(int); cy = np.floor(y).astype(int)
    best = np.full((size, size), 10.0)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx = cx + ox; ny = cy + oy
            p = pts[ny % freq, nx % freq]
            dx = nx + p[..., 0] - x
            dy = ny + p[..., 1] - y
            best = np.minimum(best, np.sqrt(dx * dx + dy * dy))
    best = best / best.max()
    return 1.0 - best


def write_noise():
    size = 256
    r = fbm(size, 4, 5, 11)
    g = fbm(size, 8, 4, 23)
    b = worley(size, 8, 37) * 0.6 + worley(size, 16, 41) * 0.4
    b = (b - b.min()) / (b.max() - b.min())
    a = fbm(size, 8, 3, 59)
    img = np.stack([r, g, b, a], axis=-1)
    img = np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(os.path.join(ROOT, "textures"), exist_ok=True)
    Image.fromarray(img, "RGBA").save(os.path.join(ROOT, "textures", "noise.png"))
    with open(os.path.join(ROOT, "textures", "noise.png.mcmeta"), "w") as fh:
        fh.write('{\n    "texture": {\n        "blur": true,\n        "clamp": false\n    }\n}\n')


if __name__ == "__main__":
    write_wrappers()
    write_properties()
    write_noise()
    print("generated wrappers, block.properties and noise texture")
