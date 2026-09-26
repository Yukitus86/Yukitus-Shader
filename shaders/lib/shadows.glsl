/*
    Yukitus Shader - shadow map distortion and filtering
*/
#ifndef SHADOWS_GLSL
#define SHADOWS_GLSL

float getDistortFactor(vec2 clipXY) {
    return length(clipXY) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
}

vec3 distortShadowClip(vec3 p) {
    p.xy /= getDistortFactor(p.xy);
    p.z *= 0.25;
    return p;
}

#ifndef SHADOW_PASS

uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;

vec3 shadowClipFromPlayer(vec3 playerPos) {
    vec3 sView = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
    return vec3(shadowProjection[0].x, shadowProjection[1].y, shadowProjection[2].z) * sView + shadowProjection[3].xyz;
}

// Single tap, used by volumetric light and particles
float sampleShadowSimple(vec3 playerPos) {
    vec3 c = distortShadowClip(shadowClipFromPlayer(playerPos));
    vec3 s = c * 0.5 + 0.5;
    if (any(greaterThan(abs(c.xy), vec2(0.999)))) return 1.0;
    return texture(shadowtex1, vec3(s.xy, s.z - 0.0002));
}

vec3 sampleShadowColored(vec3 s) {
    #ifdef COLORED_SHADOWS
        float s0 = texture(shadowtex0, s);
        if (s0 >= 0.999) return vec3(1.0);
        float s1 = texture(shadowtex1, s);
        if (s1 > s0 + 0.001) return vec3(s0) + (s1 - s0) * texture(shadowcolor0, s.xy).rgb * 2.0;
        return vec3(s1);
    #else
        return vec3(texture(shadowtex1, s));
    #endif
}

/*
    Returns colored shadow visibility.
    worldNormal : geometric normal in player space
    NdotL       : geometric N.L
    foliage     : use light-direction offset instead of normal offset
    fade        : 0 inside the shadow map, 1 outside (caller uses a lightmap fallback)
*/
vec3 getShadow(vec3 playerPos, vec3 worldNormal, float NdotL, float noise, bool foliage, out float fade) {
    fade = 0.0;
    vec3 clip = shadowClipFromPlayer(playerPos);
    float df = getDistortFactor(clip.xy);

    // normal offset bias in world units
    float texelWorld = 2.0 * shadowDistance / float(shadowMapResolution);
    vec3 offsetDir = foliage ? getLightDirWorld() : worldNormal;
    float offsetAmount = texelWorld * df * (foliage ? 0.8 : (1.2 + 1.2 * (1.0 - saturate(NdotL))));
    offsetAmount += length(playerPos) * 0.0008;
    clip = shadowClipFromPlayer(playerPos + offsetDir * offsetAmount);

    vec3 dc = distortShadowClip(clip);
    vec3 s = dc * 0.5 + 0.5;
    s.z -= 0.00008;

    float edge = maxOf(vec3(abs(clip.xy), 0.0));
    fade = smoothstep(0.85, 0.98, edge);
    if (fade >= 1.0 || s.z >= 1.0) { fade = 1.0; return vec3(1.0); }

    #if SHADOW_FILTER == 0
        return sampleShadowColored(s);
    #else
        #if SHADOW_FILTER == 1
            const int samples = 6;
        #elif SHADOW_FILTER == 2
            const int samples = 12;
        #else
            const int samples = 24;
        #endif
        float worldRadius = 0.055 * SHADOW_SOFTNESS;
        float radius = worldRadius / (2.0 * shadowDistance) / df;
        radius = max(radius, 1.2 / float(shadowMapResolution));
        radius = min(radius, 12.0 / float(shadowMapResolution));

        float phi = noise * TAU;
        #ifdef COLORED_SHADOWS
            // shadowtex0 includes translucents: fully lit there means fully lit everywhere,
            // so shadowtex1 is only sampled where something blocks the light
            float s0 = 0.0, s1 = 0.0;
            for (int i = 0; i < samples; i++) {
                vec3 p = vec3(s.xy + vogelDisk(i, samples, phi) * radius, s.z);
                float a = texture(shadowtex0, p);
                s0 += a;
                s1 += a >= 0.999 ? 1.0 : texture(shadowtex1, p);
            }
            s0 /= float(samples);
            s1 /= float(samples);
            if (s1 > s0 + 0.001) return vec3(s0) + (s1 - s0) * texture(shadowcolor0, s.xy).rgb * 2.0;
            return vec3(s1);
        #else
            float r = 0.0;
            for (int i = 0; i < samples; i++) {
                r += texture(shadowtex1, vec3(s.xy + vogelDisk(i, samples, phi) * radius, s.z));
            }
            return vec3(r / float(samples));
        #endif
    #endif
}

#endif
#endif
