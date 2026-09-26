/*
    Yukitus Shader - water waves and caustics
*/
#ifndef WATER_GLSL
#define WATER_GLSL

float waterHeight(vec2 p) {
    float t = frameTimeCounter * WAVE_SPEED;
    vec2 w1 = vec2(t * 0.40, t * 0.25);
    vec2 w2 = vec2(-t * 0.30, t * 0.45);
    vec2 w3 = vec2(t * 0.65, -t * 0.55);
    float h = texture(noisetex, (p + w1) / 48.0).a * 0.55
            + texture(noisetex, (p * 1.3 + w2) / 20.0).a * 0.30
            + texture(noisetex, (p * 1.1 + w3) / 9.0).g * 0.15;
    return h;
}

// Returns a normal in tangent space of a horizontal surface (x, z) with y up
vec3 getWaveNormal(vec3 worldPos, float strength) {
    vec2 p = worldPos.xz;
    const float e = 0.08;
    float h0 = waterHeight(p);
    float hx = waterHeight(p + vec2(e, 0.0));
    float hz = waterHeight(p + vec2(0.0, e));
    float s = 0.55 * WAVE_HEIGHT * strength;
    vec3 n = normalize(vec3((h0 - hx) / e * s, 1.0, (h0 - hz) / e * s));
    return n;
}

float getCaustics(vec3 worldPos) {
    float t = frameTimeCounter * 0.9 * WAVE_SPEED;
    vec2 p = worldPos.xz + worldPos.y * 0.25;
    float a = texture(noisetex, (p + vec2(t, t * 0.6)) / 14.0).a;
    float b = texture(noisetex, (p * 0.9 - vec2(t * 0.7, -t * 0.4)) / 11.0).a;
    float c = 1.0 - abs(a - b) * 3.0;
    c = pow(saturate(c), 6.0);
    return 0.35 + c * 1.6;
}

#endif
