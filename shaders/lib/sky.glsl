/*
    Yukitus Shader - procedural sky, sun, moon, stars, aurora and rainbow
    requires: common.glsl, colors.glsl
*/
#ifndef SKY_GLSL
#define SKY_GLSL

//--------------------------------------------------------------------------------------------------
// Base sky gradient (no celestial bodies) - also used for fog and reflections
//--------------------------------------------------------------------------------------------------
vec3 getSkyColor(vec3 viewDir) {
    #if defined OVERWORLD
        vec3 upV  = getUpDir();
        vec3 sunV = getSunDir();
        float e = dot(sunV, upV);
        float VdotU = dot(viewDir, upV);
        float VdotS = dot(viewDir, sunV);
        float y = max(VdotU, 0.0);

        float dayF = getDayFactor(e);
        float setF = getSunsetFactor(e);

        // Day
        vec3 zenith  = vec3(0.075, 0.22, 0.78);
        vec3 horizon = vec3(0.42, 0.60, 0.95);
        float hGrad = pow(1.0 - y, 3.0);
        vec3 day = mix(zenith, horizon, hGrad) * 1.4;

        // Sunset / sunrise
        float sunSide = pow(VdotS * 0.5 + 0.5, 1.5);
        vec3 setTop     = vec3(0.26, 0.30, 0.58) * 0.75;
        vec3 setHorizon = mix(vec3(0.85, 0.36, 0.36), vec3(1.25, 0.52, 0.16), sunSide);
        vec3 sunset = mix(setTop, setHorizon, pow(1.0 - y, 2.6));

        // Night
        vec3 night = mix(vec3(0.010, 0.016, 0.038), vec3(0.028, 0.042, 0.085), pow(1.0 - y, 2.0)) * NIGHT_BRIGHTNESS;

        vec3 sky = mix(night, day, dayF);
        sky = mix(sky, sunset, setF * 0.9);

        // Mie glow around the sun
        float sd = max(VdotS, 0.0);
        vec3 sunC = getSunColor(e) / (3.4 * SUN_INTENSITY);
        sky += sunC * (pow(sd, 8.0) * 0.22 + pow(sd, 64.0) * 0.8) * (0.4 + setF * 1.4) * (1.0 - rainStrength * 0.7);

        // Moon glow
        float md = max(dot(viewDir, normalize(moonPosition)), 0.0);
        sky += vec3(0.10, 0.14, 0.24) * pow(md, 12.0) * (1.0 - dayF) * getMoonBrightness() * 0.6;

        // Below horizon: a bit darker so the horizon line reads
        sky *= mix(1.0, 0.55, saturate(-VdotU * 2.5));

        // Rain: overcast
        float l = luma(sky);
        sky = mix(sky, vec3(l) * vec3(0.9, 0.95, 1.0) * 0.6, rainStrength * 0.85);
        return sky;
    #elif defined NETHER
        return toLinear(fogColor) * 0.5;
    #else
        vec3 upV = getUpDir();
        float y = dot(viewDir, upV);
        return mix(vec3(0.030, 0.018, 0.048), vec3(0.055, 0.035, 0.085), saturate(y * 0.5 + 0.5)) * END_FOG;
    #endif
}

//--------------------------------------------------------------------------------------------------
// Stars rotate with the celestial sphere
//--------------------------------------------------------------------------------------------------
vec3 celestialDir(vec3 worldDir) {
    float a = sunAngle * TAU;
    float c = cos(a), s = sin(a);
    // rotation around the east-west (z) axis the sun path follows
    vec3 p = vec3(c * worldDir.x - s * worldDir.y, s * worldDir.x + c * worldDir.y, worldDir.z);
    return p;
}

vec3 getStars(vec3 worldDir) {
    vec3 p = celestialDir(worldDir) * 150.0;
    vec3 cell = floor(p);
    vec3 f = fract(p) - 0.5;
    float h = hash13(cell);
    float threshold = 1.0 - 0.0045 * STAR_AMOUNT;
    if (h < threshold) return vec3(0.0);
    vec2 o = hash23(cell) - 0.5;
    float d = length(f.xy - o * 0.5) + abs(f.z) * 0.2;
    float star = smoothstep(0.22, 0.0, d);
    float twinkle = 0.7 + 0.3 * sin(frameTimeCounter * (2.0 + h * 5.0) + h * 100.0);
    vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.7), fract(h * 37.0));
    float bright = (h - threshold) / (1.0 - threshold);
    return tint * star * twinkle * (0.4 + bright * 2.4);
}

//--------------------------------------------------------------------------------------------------
// Sun & moon
//--------------------------------------------------------------------------------------------------
vec3 getSunDisc(vec3 viewDir, vec3 sunC) {
    float cosR = cos(0.022 * SUN_SIZE);
    float d = dot(viewDir, getSunDir());
    if (d < cosR - 0.00002) return vec3(0.0);
    float r = saturate((1.0 - d) / (1.0 - cosR));
    float limb = 1.0 - 0.55 * (1.0 - sqrt(max(1.0 - r, 0.0)));
    float edge = smoothstep(1.0, 0.85, r);
    return sunC * 24.0 * limb * edge;
}

vec3 getMoonDisc(vec3 viewDir) {
    vec3 moonV = normalize(moonPosition);
    float radius = 0.03 * MOON_SIZE;
    float d = dot(viewDir, moonV);
    if (d < cos(radius * 1.3)) return vec3(0.0);

    vec3 upRef = abs(moonV.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(upRef, moonV));
    vec3 up = cross(moonV, right);
    vec3 rel = viewDir - moonV * d;
    vec2 uv = vec2(dot(rel, right), dot(rel, up)) / radius;
    float r2 = dot(uv, uv);
    if (r2 > 1.0) return vec3(0.0);

    vec3 n = vec3(uv, sqrt(1.0 - r2));
    float phase = float(moonPhase) / 8.0 * TAU;
    vec3 L = vec3(sin(phase), 0.0, cos(phase));
    float lit = smoothstep(-0.04, 0.12, dot(n, L));

    // craters
    float crater = texture(noisetex, uv * 0.18 + 0.37).r * 0.6 + texture(noisetex, uv * 0.45 + 0.11).g * 0.4;
    float surface = 0.62 + 0.38 * smoothstep(0.35, 0.65, crater);
    float edge = smoothstep(1.0, 0.92, r2);

    vec3 moonC = vec3(0.86, 0.9, 1.0) * surface;
    return moonC * (lit * 2.2 + 0.03) * edge;
}

//--------------------------------------------------------------------------------------------------
// Aurora borealis
//--------------------------------------------------------------------------------------------------
vec3 getAurora(vec3 worldDir, float dither) {
    if (worldDir.y < 0.02) return vec3(0.0);
    vec3 result = vec3(0.0);
    const int steps = 10;
    float t = frameTimeCounter * 0.012;
    for (int i = 0; i < steps; i++) {
        float fi = (float(i) + dither) / float(steps);
        float h = 1.0 + fi * 0.45;
        vec2 p = worldDir.xz / worldDir.y * h * 0.35;
        vec2 warp = vec2(texture(noisetex, p * 0.08 + t * 0.3).r, texture(noisetex, p * 0.08 + 0.5 - t * 0.2).g) - 0.5;
        float n = texture(noisetex, (p + warp * 0.8) * vec2(0.05, 0.22) + vec2(t, 0.0)).r;
        float band = pow(1.0 - abs(n - 0.5) * 2.0, 10.0);
        vec3 col = mix(vec3(0.05, 1.0, 0.45), vec3(0.55, 0.15, 1.0), pow(fi, 1.4));
        result += band * col * (1.0 - fi);
    }
    result /= float(steps);
    return result * smoothstep(0.02, 0.25, worldDir.y) * 1.3;
}

//--------------------------------------------------------------------------------------------------
// Rainbow after rain, opposite of the sun
//--------------------------------------------------------------------------------------------------
vec3 getRainbow(vec3 viewDir) {
    float amount = saturate(wetness - rainStrength) * (1.0 - rainStrength);
    if (amount < 0.01) return vec3(0.0);
    float e = getSunElevation();
    amount *= smoothstep(0.0, 0.1, e) * (1.0 - smoothstep(0.35, 0.6, e));
    float ang = acos(clamp(dot(viewDir, -getSunDir()), -1.0, 1.0));
    float x = (ang - 0.705) / 0.035; // ~40.4 .. 42.4 deg
    if (x < -0.3 || x > 1.3) return vec3(0.0);
    vec3 c = saturate(vec3(1.0 - abs(x - 1.0) * 2.2, 1.0 - abs(x - 0.55) * 2.2, 1.0 - abs(x - 0.1) * 2.2));
    return c * amount * 0.12 * smoothstep(-0.05, 0.2, dot(viewDir, getUpDir()));
}

//--------------------------------------------------------------------------------------------------
// End sky
//--------------------------------------------------------------------------------------------------
vec3 getEndSky(vec3 viewDir, vec3 worldDir) {
    vec3 sky = getSkyColor(viewDir);
    float n = texture(noisetex, worldDir.xz / (abs(worldDir.y) + 0.35) * 0.08 + frameTimeCounter * 0.001).r;
    float n2 = texture(noisetex, worldDir.xz / (abs(worldDir.y) + 0.35) * 0.21 - frameTimeCounter * 0.0007).g;
    float nebula = pow(saturate(n * 0.7 + n2 * 0.5 - 0.35), 2.0);
    sky += vec3(0.16, 0.08, 0.34) * nebula * 0.45;
    sky += getStars(worldDir) * 0.8;
    // bright light source in the End
    float d = max(dot(viewDir, getLightDir()), 0.0);
    sky += vec3(0.5, 0.35, 0.8) * (pow(d, 40.0) * 0.4 + pow(d, 1200.0) * 6.0);
    return sky;
}

//--------------------------------------------------------------------------------------------------
// Full sky for sky pixels
//--------------------------------------------------------------------------------------------------
vec3 getSkyFull(vec3 viewDir, vec3 worldDir, float dither) {
    #if defined OVERWORLD
        vec3 sky = getSkyColor(viewDir);
        float e = getSunElevation();
        float nightF = 1.0 - getDayFactor(e);
        float clearF = 1.0 - rainStrength;

        #ifdef STARS
            sky += getStars(worldDir) * nightF * clearF * smoothstep(0.0, 0.15, worldDir.y) * 0.35;
        #endif

        #if AURORA > 0
            #if AURORA == 1
                float auroraAmount = snowiness;
            #else
                float auroraAmount = 1.0;
            #endif
            if (auroraAmount * nightF * clearF > 0.01) {
                sky += getAurora(worldDir, dither) * auroraAmount * nightF * clearF * NIGHT_BRIGHTNESS;
            }
        #endif

        #ifdef RAINBOWS
            sky += getRainbow(viewDir);
        #endif

        float horizonMask = smoothstep(-0.02, 0.01, dot(viewDir, getUpDir()));
        sky += getSunDisc(viewDir, getSunColor(e)) * clearF * horizonMask;
        sky += getMoonDisc(viewDir) * clearF * horizonMask * NIGHT_BRIGHTNESS;
        return sky;
    #elif defined END
        return getEndSky(viewDir, worldDir);
    #else
        return getSkyColor(viewDir);
    #endif
}

#endif
