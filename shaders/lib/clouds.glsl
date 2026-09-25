/*
    Yukitus Shader - volumetric clouds (cheap 2.5D noise raymarch)
    requires: common.glsl, colors.glsl
*/
#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

const float cloudBottom = CLOUD_HEIGHT;
const float cloudThick = 72.0 * CLOUD_THICKNESS;
const float cloudTop = CLOUD_HEIGHT + 72.0 * CLOUD_THICKNESS;

vec2 cloudWind() {
    return vec2(frameTimeCounter * 1.2 * CLOUD_SPEED, frameTimeCounter * 0.3 * CLOUD_SPEED);
}

float cloudCoverage() {
    return saturate(0.42 * CLOUD_COVERAGE + rainStrength * 0.32);
}

// Large scale cloud shape, 0..1
float cloudShape(vec2 xz) {
    vec2 p = (xz + cloudWind()) / 3072.0;
    float n = texture(noisetex, p).r * 0.62
            + texture(noisetex, p * 2.7 + 0.31).g * 0.26
            + texture(noisetex, p * 7.3 + 0.73).a * 0.12;
    float c = cloudCoverage();
    return saturate((n - (1.0 - c)) / max(c, 0.05) * 1.6);
}

float cloudDensity(vec3 pos, bool detail) {
    float h = saturate((pos.y - cloudBottom) / cloudThick);
    float shape = cloudShape(pos.xz);
    if (shape <= 0.0) return 0.0;
    // flat-ish bottom, rounded top
    float profile = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.35, 1.0, h));
    float d = shape * 1.25 - (1.0 - profile) - h * 0.35;
    if (detail && d > -0.2) {
        vec2 dp = (pos.xz + cloudWind() * 1.5) / 420.0 + pos.y / 900.0;
        d -= texture(noisetex, dp).b * 0.35;
    }
    return saturate(d * 3.0);
}

float cloudPhase(float cosTheta) {
    float g1 = 0.75, g2 = -0.25;
    float a = (1.0 - g1 * g1) / pow(1.0 + g1 * g1 - 2.0 * g1 * cosTheta, 1.5);
    float b = (1.0 - g2 * g2) / pow(1.0 + g2 * g2 - 2.0 * g2 * cosTheta, 1.5);
    return mix(b, a, 0.7) / (4.0 * PI);
}

/*
    Returns vec4(scattered light, transmittance)
    worldDir : normalized ray direction (player space)
    maxDist  : distance to scene geometry (large value for sky)
*/
vec4 getVolumetricClouds(vec3 worldDir, float maxDist, float noise) {
    #if CLOUD_QUALITY == 0
        const int steps = 10;
    #elif CLOUD_QUALITY == 1
        const int steps = 16;
    #else
        const int steps = 28;
    #endif

    float camY = cameraPosition.y;
    if (abs(worldDir.y) < 0.0001) worldDir.y = 0.0001;
    float tBottom = (cloudBottom - camY) / worldDir.y;
    float tTop = (cloudTop - camY) / worldDir.y;
    float tEnter = max(min(tBottom, tTop), 0.0);
    float tExit = max(tBottom, tTop);
    if (tExit <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
    tExit = min(tExit, tEnter + 1200.0);
    tExit = min(tExit, maxDist);
    const float maxRange = 6000.0;
    if (tEnter > maxRange || tEnter >= tExit) return vec4(0.0, 0.0, 0.0, 1.0);

    float stepLen = (tExit - tEnter) / float(steps);
    vec3 lightDirW = getLightDirWorld();
    vec3 lightC = getLightColor();
    vec3 ambC = getAmbientColor();
    float VdotL = dot(worldDir, lightDirW);
    float phase = cloudPhase(VdotL) * 4.0 * PI;

    float transmittance = 1.0;
    vec3 scatter = vec3(0.0);
    const float sigma = 0.035;

    for (int i = 0; i < steps; i++) {
        float t = tEnter + stepLen * (float(i) + noise);
        vec3 p = vec3(cameraPosition.x, camY, cameraPosition.z) + worldDir * t;
        float d = cloudDensity(p, true);
        if (d < 0.005) continue;

        // light marching (cheap, shape only)
        float ld = cloudDensity(p + lightDirW * 10.0, false) * 10.0
                 + cloudDensity(p + lightDirW * 28.0, false) * 18.0;
        #if CLOUD_QUALITY == 2
            ld += cloudDensity(p + lightDirW * 60.0, false) * 32.0;
        #endif
        float lightT = exp(-ld * sigma * 1.6);
        float powder = 1.0 - exp(-d * 4.0);
        float h = saturate((p.y - cloudBottom) / cloudThick);

        vec3 S = lightC * lightT * phase * mix(0.6, 1.0, powder)
               + ambC * (0.45 + 0.55 * h) * 0.85;

        float dT = exp(-d * sigma * stepLen);
        scatter += transmittance * S * (1.0 - dT);
        transmittance *= dT;
        if (transmittance < 0.02) break;
    }

    // fade out towards the horizon
    float fade = exp(-tEnter / 2600.0) * smoothstep(maxRange, maxRange * 0.5, tEnter);
    scatter *= fade;
    transmittance = mix(1.0, transmittance, fade);
    return vec4(scatter, transmittance);
}

// Very cheap flat clouds for reflections
vec3 getCheapClouds(vec3 worldDir, vec3 sky) {
    if (worldDir.y < 0.02) return sky;
    float t = (cloudBottom + cloudThick * 0.5 - cameraPosition.y) / worldDir.y;
    if (t < 0.0) return sky;
    vec3 p = cameraPosition + worldDir * t;
    float s = cloudShape(p.xz);
    vec3 c = getAmbientColor() * 0.9 + getLightColor() * 0.25;
    float fade = exp(-t / 2600.0);
    return mix(sky, c, saturate(s * 1.4) * fade * 0.85);
}

// Cloud shadow factor on a world position
float getCloudShadow(vec3 playerPos) {
    vec3 lightDirW = getLightDirWorld();
    if (lightDirW.y < 0.05) return 1.0;
    vec3 wp = playerPos + cameraPosition;
    float t = (cloudBottom + cloudThick * 0.3 - wp.y) / lightDirW.y;
    if (t < 0.0) return 1.0;
    vec3 p = wp + lightDirW * t;
    float s = cloudShape(p.xz);
    return 1.0 - smoothstep(0.0, 0.6, s) * 0.78;
}

#endif
