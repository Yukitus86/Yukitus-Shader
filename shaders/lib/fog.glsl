/*
    Yukitus Shader - atmospheric / border / dimension fog
    requires: common.glsl, colors.glsl, sky.glsl
*/
#ifndef FOG_GLSL
#define FOG_GLSL

float getEyeSkyLight() {
    return saturate(float(eyeBrightnessSmooth.y) / 240.0);
}

vec3 applyFog(vec3 color, vec3 viewPos, vec3 playerPos) {
    float dist = length(playerPos);
    vec3 viewDir = viewPos / max(length(viewPos), 1e-5);

    // Lava / powder snow
    if (isEyeInWater == 2) {
        return mix(color, vec3(1.2, 0.35, 0.05), 1.0 - exp(-dist * 1.2));
    }
    if (isEyeInWater == 3) {
        return mix(color, vec3(0.75, 0.82, 0.95), 1.0 - exp(-dist * 1.0));
    }

    #if defined OVERWORLD
        vec3 fogC = getSkyColor(viewDir);
        float eyeSky = getEyeSkyLight();
        // caves: fog turns into dark haze
        vec3 caveFog = vec3(0.012, 0.014, 0.018) * MIN_LIGHT + vec3(0.02) * nightVision;
        fogC = mix(caveFog, fogC, eyeSky);

        float worldY = playerPos.y + cameraPosition.y;
        float e = getSunElevation();
        float density = 0.0011;
        #ifdef MORNING_FOG
            float morning = smoothstep(-0.1, 0.05, e) * (1.0 - smoothstep(0.05, 0.3, e));
            density += 0.0045 * morning * ((sunAngle < 0.25 || sunAngle > 0.75) ? 1.0 : 0.3) + 0.0006 * (1.0 - getDayFactor(e));
        #endif
        density += 0.0075 * rainStrength;
        density *= exp(-max(worldY - 62.0, 0.0) / 72.0);
        density *= FOG_DENSITY;

        float f = 1.0 - exp(-dist * density);
        #ifdef BORDER_FOG
            float border = smoothstep(far * 0.55, far * 0.98, dist);
            f = max(f, border * border);
        #endif
        color = mix(color, fogC, f);
    #elif defined NETHER
        vec3 fogC = getSkyColor(viewDir);
        float f = 1.0 - exp(-dist * 0.018 * NETHER_FOG);
        f = max(f, smoothstep(far * 0.5, far * 0.98, dist));
        color = mix(color, fogC, f);
    #else
        vec3 fogC = getSkyColor(viewDir);
        float f = 1.0 - exp(-dist * 0.006 * END_FOG);
        f = max(f, smoothstep(far * 0.6, far * 0.98, dist));
        color = mix(color, fogC, f);
    #endif

    // Blindness / darkness effect
    float blind = max(blindness, darknessFactor);
    if (blind > 0.0) {
        color *= exp(-dist * blind * 0.45);
    }
    return color;
}

// Underwater fog when the camera is inside water
vec3 applyUnderwaterFog(vec3 color, float dist) {
    float eyeSky = max(getEyeSkyLight(), 0.08);
    vec3 scatter = getWaterScatterColor() * eyeSky * 1.4 + vec3(0.002, 0.006, 0.008);
    vec3 absorb = waterAbsorption * WATER_FOG_DENSITY;
    vec3 T = exp(-absorb * dist * 1.1);
    color = color * T + scatter * (1.0 - exp(-dist * 0.12 * WATER_FOG_DENSITY));
    return color;
}

#endif
