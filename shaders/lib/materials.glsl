/*
    Yukitus Shader - integrated PBR (material properties from block ids + albedo heuristics)
*/
#ifndef MATERIALS_GLSL
#define MATERIALS_GLSL

struct Material {
    float smoothness;  // 0..1
    float f0;          // reflectance at normal incidence, >= 0.9 means metal
    float emission;    // 0..1 (scaled later)
    float sss;         // subsurface scattering amount
    float matClass;    // MAT_* (for later passes)
};

bool isFoliageId(int id) { return id >= 10001 && id <= 10007; }

Material getMaterial(int id, vec3 albedo) {
    Material m = Material(0.0, 0.04, 0.0, 0.0, MAT_GENERIC);
    float lum = luma(albedo);
    float mx = maxOf(albedo), mn = minOf(albedo);
    float sat = (mx - mn) / max(mx, 0.001);

    if (id < 10000) return m;

    if (isFoliageId(id)) {
        m.matClass = MAT_FOLIAGE;
        m.sss = (id == 10003) ? 0.75 : 0.9;
        m.smoothness = (id == 10003) ? 0.32 : 0.18;
        if (id == 10006) m.sss = 0.4;
    }
    else if (id == 10020) {              // lava
        m.emission = 0.6 + 0.8 * pow(lum, 2.0);
        m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10021) {              // fire
        m.emission = 1.0;
        m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10022) {              // full light blocks
        m.emission = 0.25 + pow(lum, 2.2) * 1.4;
        m.smoothness = 0.35;
        m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10023) {              // torches, lanterns, lit furnaces
        m.emission = smoothstep(0.55, 0.85, mx) * smoothstep(0.15, 0.4, sat + 0.2 * step(0.85, lum)) * 1.4;
        if (m.emission > 0.05) m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10051) {              // soul torch, soul lantern, soul fire
        m.emission = smoothstep(0.45, 0.75, albedo.b) * smoothstep(0.35, 0.7, albedo.g) * 1.2;
        if (m.emission > 0.05) m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10070) {              // copper torch / lantern
        m.emission = smoothstep(0.5, 0.8, albedo.g) * smoothstep(0.2, 0.5, sat) * 1.3;
        if (m.emission > 0.05) m.matClass = MAT_EMISSIVE;
    }
    else if (id == 10050) {              // redstone stuff
        m.emission = smoothstep(0.45, 0.75, albedo.r) * (1.0 - smoothstep(0.25, 0.5, albedo.g)) * 0.9;
        m.smoothness = 0.3;
    }
    else if (id == 10024) {              // ores
        #ifdef EMISSIVE_ORES
            m.emission = smoothstep(0.28, 0.55, sat) * smoothstep(0.2, 0.5, lum) * 0.35;
        #endif
        m.smoothness = smoothstep(0.25, 0.5, sat) * 0.7;
        m.f0 = mix(0.04, 0.2, smoothstep(0.25, 0.5, sat));
    }
    else if (id == 10025) {              // magma
        m.emission = smoothstep(0.4, 0.8, albedo.r) * smoothstep(0.2, 0.5, sat) * 0.9;
    }
    else if (id == 10026) {              // amethyst
        m.smoothness = 0.7;
        m.f0 = 0.08;
        m.emission = smoothstep(0.55, 0.85, lum) * 0.25;
    }
    else if (id == 10030) {              // metals
        m.smoothness = 0.38 + lum * 0.3;
        m.f0 = 0.92;
        m.matClass = MAT_METAL;
    }
    else if (id == 10031) {              // polished / smooth stone-like
        m.smoothness = 0.45;
    }
    else if (id == 10032) {              // gem blocks
        m.smoothness = 0.8;
        m.f0 = 0.12;
    }
    else if (id == 10033) {              // obsidian / crying obsidian
        m.smoothness = 0.78;
        m.f0 = 0.05;
        m.emission = smoothstep(0.35, 0.6, albedo.b) * smoothstep(0.2, 0.5, sat) * 0.6;
    }
    else if (id == 10040) {              // snow
        m.smoothness = 0.25;
        m.sss = 0.25;
    }
    else if (id == 10061) {              // glow lichen, glow berries
        m.emission = smoothstep(0.55, 0.8, lum) * 0.9;
        m.matClass = MAT_FOLIAGE;
        m.sss = 0.5;
    }
    else if (id == 10062) {              // sculk
        m.emission = smoothstep(0.35, 0.6, albedo.b - albedo.r) * 0.6;
        m.smoothness = 0.3;
    }
    else if (id == 10011) {              // ice (opaque variants)
        m.smoothness = 0.85;
        m.f0 = 0.02;
    }
    return m;
}

// labPBR 1.3 decoding
void applyLabPBR(inout Material m, vec4 spec) {
    m.smoothness = spec.r;
    float f0raw = spec.g * 255.0;
    m.f0 = f0raw >= 229.5 ? 0.92 : spec.g;
    if (m.f0 >= 0.9) m.matClass = MAT_METAL;
    if (spec.b * 255.0 >= 64.5) m.sss = max(m.sss, (spec.b * 255.0 - 64.0) / 191.0);
    float em = spec.a * 255.0 < 254.5 ? spec.a : 0.0;
    m.emission = max(m.emission, em);
}

#endif
