/*
    Yukitus Shader - wind animation for plants and leaves (shared by gbuffers and shadow pass)
*/
#ifndef WAVING_GLSL
#define WAVING_GLSL

vec3 getWind(vec3 worldPos) {
    float t = frameTimeCounter * WAVING_SPEED;
    float gust = 0.55 + 0.45 * sin(t * 0.37 + worldPos.x * 0.021 + worldPos.z * 0.013);
    vec3 w;
    w.x = sin(t * 1.9 + worldPos.x * 0.55 + worldPos.z * 0.27 + worldPos.y * 0.3);
    w.z = sin(t * 1.5 + worldPos.z * 0.48 + worldPos.x * 0.21 + 1.7);
    w.y = sin(t * 2.3 + worldPos.x * 0.8 + worldPos.z * 0.9) * 0.3;
    w.xz += vec2(sin(t * 4.1 + worldPos.x * 1.7), cos(t * 3.7 + worldPos.z * 1.9)) * 0.25;
    return w * gust * (0.65 + rainStrength * 0.9) * WAVING_STRENGTH;
}

/*
    id       : block id from block.properties
    isTop    : vertex is on the upper edge of its texture
    skyLight : vertex skylight (no wind in caves)
*/
vec3 getWaving(vec3 worldPos, int id, bool isTop, float skyLight) {
    vec3 offset = vec3(0.0);
    float amount = smoothstep(0.1, 0.6, skyLight);
    if (amount <= 0.0) return offset;

    #ifdef WAVING_PLANTS
        if (id == 10001 || id == 10005) {            // short plants, crops (bottom anchored)
            if (isTop) offset = getWind(worldPos) * vec3(0.10, 0.02, 0.10);
        } else if (id == 10002) {                    // upper half of tall plants
            offset = getWind(worldPos) * vec3(isTop ? 0.16 : 0.10, 0.02, isTop ? 0.16 : 0.10);
        } else if (id == 10004) {                    // vines
            offset = getWind(worldPos) * vec3(0.05, 0.0, 0.05);
        } else if (id == 10006) {                    // lily pad
            offset.y = sin(frameTimeCounter * 1.3 * WAVING_SPEED + worldPos.x * 0.7 + worldPos.z * 0.5) * 0.015;
        }
    #endif
    #ifdef WAVING_LEAVES
        if (id == 10003) {
            offset = getWind(worldPos) * vec3(0.045, 0.025, 0.045);
        }
    #endif
    return offset * amount;
}

#endif
