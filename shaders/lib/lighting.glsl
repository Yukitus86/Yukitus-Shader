/*
    Yukitus Shader - main forward lighting model
    requires: common.glsl, colors.glsl, shadows.glsl, clouds.glsl, materials.glsl
*/
#ifndef LIGHTING_GLSL
#define LIGHTING_GLSL

// Schlick (1994) Fresnel approximation
float fresnelSchlick(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - saturate(cosTheta), 5.0);
}

// GGX distribution (Walter et al. 2007) with Smith-Schlick visibility
float ggxSpecular(vec3 n, vec3 v, vec3 l, float smoothness) {
    float rough = max(pow2(1.0 - smoothness), 0.02);
    vec3 h = normalize(l + v);
    float NdotH = saturate(dot(n, h));
    float NdotL = saturate(dot(n, l));
    float NdotV = max(dot(n, v), 0.001);
    float a2 = rough * rough;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);
    float k = rough * 0.5;
    float G = NdotL / (NdotL * (1.0 - k) + k) * NdotV / (NdotV * (1.0 - k) + k);
    return min(D * G / (4.0 * NdotV + 0.001), 40.0);
}

float getHandLight(vec3 viewPos) {
    #ifdef HANDHELD_LIGHT
        float held = float(max(heldBlockLightValue, heldBlockLightValue2));
        if (held <= 0.0) return 0.0;
        float dist = length(viewPos);
        return saturate((held - dist * 1.1) / 15.0);
    #else
        return 0.0;
    #endif
}

struct LightingResult {
    vec3 color;
    float aoWeight;  // share of the result that SSAO may darken
    float sunVis;    // shadow visibility (for water specular)
};

/*
    albedo     : linear albedo
    viewPos    : view space position
    normal     : shading normal (view space)
    geoNormal  : geometric normal (view space)
    lm         : (block, sky) lightmap 0..1
    vanillaAO  : vertex AO
*/
LightingResult getLighting(vec3 albedo, vec3 viewPos, vec3 normal, vec3 geoNormal, vec2 lm,
                           float vanillaAO, Material mat, float noise) {
    LightingResult res;
    vec3 playerPos = viewToPlayer(viewPos);
    vec3 viewDir = -normalize(viewPos);
    vec3 upV = getUpDir();

    float metal = mat.f0 >= 0.9 ? 1.0 : 0.0;
    float ao = mix(1.0, vanillaAO, VANILLA_AO);

    // ---------------------------------------------------------------- direct light
    vec3 direct = vec3(0.0);
    vec3 specular = vec3(0.0);
    float sunVis = 0.0;
    #if defined OVERWORLD || defined END
        vec3 lightDir = getLightDir();
        vec3 lightC = getLightColor();
        float NdotL = dot(normal, lightDir);
        float geoNdotL = dot(geoNormal, lightDir);
        bool foliage = mat.sss > 0.0;

        #ifdef SUBSURFACE_SCATTERING
            float diffuse = foliage ? mix(saturate(NdotL), 0.5 + 0.5 * abs(NdotL), mat.sss * 0.6) : saturate(NdotL);
        #else
            float diffuse = saturate(NdotL);
        #endif
        if (!foliage && geoNdotL <= 0.0) diffuse = 0.0;

        vec3 shadow = vec3(0.0);
        float skyMask = saturate(lm.y * 4.0);
        if ((diffuse > 0.0 || foliage) && maxOf(lightC) > 0.0 && skyMask > 0.0) {
            #ifdef SHADOWS
                float fade;
                vec3 worldNormal = mat3(gbufferModelViewInverse) * geoNormal;
                shadow = getShadow(playerPos, worldNormal, geoNdotL, noise, foliage, fade);
                if (fade > 0.0) shadow = mix(shadow, vec3(smoothstep(0.82, 0.96, lm.y)), fade);
            #else
                shadow = vec3(smoothstep(0.82, 0.96, lm.y));
            #endif
            shadow *= skyMask;
            #if defined OVERWORLD && defined CLOUD_SHADOWS && defined VOLUMETRIC_CLOUDS
                shadow *= getCloudShadow(playerPos);
            #endif
        }
        sunVis = luma(shadow);

        direct = lightC * shadow * diffuse;

        #ifdef SUBSURFACE_SCATTERING
            if (foliage) {
                float VdotL = dot(-viewDir, lightDir);
                float transmit = pow(saturate(VdotL), 6.0) * 1.2 + 0.25;
                direct += lightC * shadow * transmit * mat.sss * 0.6 * saturate(-NdotL + 0.4);
            }
        #endif

        #ifdef SPECULAR_HIGHLIGHTS
            if (mat.smoothness > 0.05 && geoNdotL > 0.0) {
                float spec = ggxSpecular(normal, viewDir, lightDir, mat.smoothness);
                float F = fresnelSchlick(dot(normalize(lightDir + viewDir), viewDir), metal > 0.5 ? 0.9 : mat.f0);
                vec3 specC = metal > 0.5 ? albedo : vec3(1.0);
                specular = lightC * shadow * spec * F * specC * saturate(NdotL);
            }
        #endif
    #endif

    // ---------------------------------------------------------------- ambient
    #if defined OVERWORLD
        float skyL = lm.y * lm.y;
        float upness = dot(normal, upV) * 0.5 + 0.5;
        vec3 ambient = getAmbientColor() * skyL * (0.55 + 0.45 * upness);
        // light bounced from the ground in sunlight
        ambient += getLightColor() * 0.05 * skyL * (1.0 - upness);
    #elif defined NETHER
        vec3 ambient = getAmbientColor();
    #else
        vec3 ambient = getAmbientColor() * (0.7 + 0.3 * (dot(normal, upV) * 0.5 + 0.5));
    #endif

    float bl = max(lm.x, getHandLight(viewPos));
    vec3 block = getBlockLight(bl);
    vec3 minL = getMinLight();

    vec3 indirect = (ambient + block + minL) * ao;
    vec3 diffuseLight = direct + indirect;

    vec3 color = albedo * diffuseLight * (1.0 - metal * 0.6);
    color += specular;
    color += albedo * mat.emission * 5.0 * EMISSION_STRENGTH;

    float total = luma(diffuseLight) + 1e-4;
    res.aoWeight = saturate(luma(ambient + minL) / total) * (1.0 - saturate(mat.emission * 4.0));
    res.color = color;
    res.sunVis = sunVis;
    return res;
}

// Simple lighting for particles / weather / basic geometry
vec3 getSimpleLighting(vec3 albedo, vec3 viewPos, vec2 lm) {
    vec3 light = vec3(0.0);
    #if defined OVERWORLD || defined END
        vec3 lightC = getLightColor();
        float vis = 1.0;
        #ifdef SHADOWS
            vis = sampleShadowSimple(viewToPlayer(viewPos));
        #endif
        light += lightC * vis * 0.55 * saturate(lm.y * 4.0);
    #endif
    #if defined OVERWORLD
        light += getAmbientColor() * lm.y * lm.y;
    #else
        light += getAmbientColor();
    #endif
    light += getBlockLight(max(lm.x, getHandLight(viewPos))) + getMinLight();
    return albedo * light;
}

#endif
