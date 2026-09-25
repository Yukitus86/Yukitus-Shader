/*
    Yukitus Shader - time of day, light and ambient colors per dimension
*/
#ifndef COLORS_GLSL
#define COLORS_GLSL

vec3 getSunDir()   { return normalize(sunPosition); }
vec3 getUpDir()    { return normalize(upPosition); }
vec3 getLightDir() { return normalize(shadowLightPosition); }
vec3 getLightDirWorld() { return mat3(gbufferModelViewInverse) * normalize(shadowLightPosition); }

// Sun elevation, -1 (nadir) .. 1 (zenith)
float getSunElevation() {
    return clamp(dot(getSunDir(), getUpDir()), -1.0, 1.0);
}

float getDayFactor(float e)    { return smoothstep(-0.10, 0.12, e); }
float getSunsetFactor(float e) { return smoothstep(-0.18, 0.0, e) * (1.0 - smoothstep(0.0, 0.3, e)); }

float getMoonBrightness() {
    // 0 = full moon, 4 = new moon
    float p = abs(float(moonPhase) - 4.0) / 4.0;
    return mix(0.35, 1.0, p);
}

vec3 getBlockLightColor() {
    #if BLOCKLIGHT_TEMP == 0
        vec3 c = vec3(1.0, 0.82, 0.62);
    #elif BLOCKLIGHT_TEMP == 1
        vec3 c = vec3(1.0, 0.62, 0.32);
    #else
        vec3 c = vec3(1.0, 0.48, 0.18);
    #endif
    return c * 1.6 * BLOCKLIGHT_INTENSITY;
}

vec3 getBlockLight(float bl) {
    float b = bl * bl;
    float intensity = b * b * 1.6 + b * 0.35 + bl * 0.03;
    return getBlockLightColor() * intensity;
}

vec3 getSunColor(float e) {
    vec3 horizon = vec3(1.00, 0.28, 0.06);
    vec3 low     = vec3(1.00, 0.56, 0.24);
    vec3 noon    = vec3(1.00, 0.95, 0.88);
    vec3 c = mix(horizon, low, smoothstep(0.0, 0.12, e));
    c = mix(c, noon, smoothstep(0.10, 0.50, e));
    return c * smoothstep(-0.04, 0.06, e) * 3.4 * SUN_INTENSITY;
}

vec3 getMoonColor(float e) {
    return vec3(0.52, 0.66, 1.0) * 0.16 * getMoonBrightness() * smoothstep(-0.04, 0.06, -e) * NIGHT_BRIGHTNESS;
}

// Directional (shadow casting) light
vec3 getLightColor() {
    #if defined OVERWORLD
        float e = getSunElevation();
        vec3 c = getSunColor(e) + getMoonColor(e);
        return c * (1.0 - rainStrength * 0.85);
    #elif defined END
        return vec3(0.62, 0.48, 0.95) * 0.9;
    #else
        return vec3(0.0);
    #endif
}

// Skylight illuminance on an upward facing surface
vec3 getAmbientColor() {
    #if defined OVERWORLD
        float e = getSunElevation();
        float dayF = getDayFactor(e);
        float setF = getSunsetFactor(e);
        vec3 day    = vec3(0.40, 0.56, 0.95) * 0.95;
        vec3 sunset = vec3(0.62, 0.46, 0.44) * 0.55;
        vec3 night  = vec3(0.10, 0.15, 0.32) * 0.30 * NIGHT_BRIGHTNESS;
        vec3 c = mix(night, day, dayF);
        c = mix(c, sunset, setF * 0.7);
        vec3 rainC = vec3(luma(c)) * vec3(0.85, 0.9, 1.0) * 0.75;
        c = mix(c, rainC, rainStrength);
        return c * AMBIENT_INTENSITY;
    #elif defined NETHER
        vec3 f = toLinear(fogColor);
        return (f / max(maxOf(f), 0.01) * 0.28 + vec3(0.10, 0.06, 0.04)) * AMBIENT_INTENSITY;
    #else
        return vec3(0.16, 0.12, 0.26) * AMBIENT_INTENSITY;
    #endif
}

vec3 getMinLight() {
    return vec3(0.75, 0.85, 1.0) * 0.006 * MIN_LIGHT + vec3(0.25, 0.3, 0.35) * nightVision;
}

// Water medium coefficients (per block)
const vec3 waterAbsorption = vec3(0.34, 0.085, 0.06);
vec3 getWaterScatterColor() {
    #ifdef OVERWORLD
        vec3 light = getAmbientColor() * 0.8 + getLightColor() * 0.12;
    #else
        vec3 light = getAmbientColor() * 1.2;
    #endif
    return vec3(0.03, 0.16, 0.20) * light;
}

#endif
