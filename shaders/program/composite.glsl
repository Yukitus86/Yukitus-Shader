/*
    Yukitus Shader - composite: water (refraction, absorption), reflections, underwater fog
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
out vec2 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0.xy;
}
#endif

#ifdef FSH
//==================================================================================================
in vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#include "/lib/colors.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"
#include "/lib/clouds.glsl"
#include "/lib/reflections.glsl"

float fresnel(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - saturate(cosTheta), 5.0);
}

float specGGX(vec3 n, vec3 v, vec3 l, float smoothness) {
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
    return min(D * G / (4.0 * NdotV + 0.001), 60.0) * NdotL;
}

vec3 getReflection(vec3 viewPos, vec3 n, float skyLM, float noise, bool allowSSR) {
    vec3 R = reflect(normalize(viewPos), n);
    vec3 worldR = mat3(gbufferModelViewInverse) * R;
    vec3 sky = getSkyColor(R);
    #if defined OVERWORLD && defined VOLUMETRIC_CLOUDS
        sky = getCheapClouds(worldR, sky);
    #endif
    #ifdef OVERWORLD
        float skyF = pow(saturate(skyLM * 1.15 - 0.1), 3.0);
        sky *= skyF;
        sky += getMinLight() * (1.0 - skyF);
    #endif
    vec3 refl = sky;
    #if REFLECTIONS > 0
        if (allowSSR) {
            vec4 ssr = screenSpaceReflection(viewPos, R, noise);
            refl = mix(sky, ssr.rgb, ssr.a);
        }
    #endif
    return refl;
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    float depth0 = texture(depthtex0, texcoord).r;
    float depth1 = texture(depthtex1, texcoord).r;
    vec3 viewPos0 = screenToView(vec3(texcoord, depth0));
    vec3 viewDir = normalize(viewPos0);
    float noise = dither(gl_FragCoord.xy);

    vec4 trans = texture(colortex5, texcoord);
    vec2 transInfo = unpack2x8(trans.b);
    int type = int(transInfo.x * 4.0 + 0.5);
    float skyLM = transInfo.y;
    bool hand = depth0 < 0.56;

    if (type == 2 && !hand) {
        //------------------------------------------------------------------------------------ water
        vec3 n = decodeNormal(trans.xy);
        vec3 V = -viewDir;

        vec2 refrUV = texcoord;
        float depth1R = depth1;
        #ifdef WATER_REFRACTION
        {
            vec3 viewPos1 = screenToView(vec3(texcoord, depth1));
            float thick = clamp(distance(viewPos0, viewPos1), 0.0, 2.5) * REFRACTION_STRENGTH;
            vec3 R = refract(viewDir, n, isEyeInWater == 1 ? 1.33 : 0.75);
            if (dot(R, R) > 0.0) {
                vec2 a = viewToScreen(viewPos0 + R * thick).xy;
                vec2 b = viewToScreen(viewPos0 + viewDir * thick).xy;
                vec2 uv = texcoord + (a - b);
                float d0R = texture(depthtex0, uv).r;
                float d1R = texture(depthtex1, uv).r;
                if (d1R > d0R && d0R > 0.56 && all(greaterThan(uv, vec2(0.001))) && all(lessThan(uv, vec2(0.999)))) {
                    refrUV = uv;
                    depth1R = d1R;
                }
            }
        }
        #endif
        color = texture(colortex0, refrUV).rgb;

        if (isEyeInWater == 0) {
            vec3 viewPos1 = screenToView(vec3(refrUV, depth1R));
            float thickness = depth1R >= 1.0 ? 64.0 : min(distance(viewPos0, viewPos1), 64.0);
            float density = WATER_FOG_DENSITY;
            vec3 T = exp(-waterAbsorption * density * thickness);
            float sky = max(skyLM * skyLM, 0.05);
            vec3 scatter = getWaterScatterColor() * sky * 1.4;
            color = color * T + scatter * (1.0 - exp(-thickness * 0.14 * density));

            // soft foam where the water is very shallow (shores)
            vec3 wp = viewToPlayer(viewPos0) + cameraPosition;
            float foamNoise = texture(noisetex, wp.xz / 7.0 + frameTimeCounter * 0.01 * WAVE_SPEED).b;
            float foam = (1.0 - smoothstep(0.05, 0.55, thickness)) * smoothstep(0.35, 0.75, foamNoise);
            #if defined OVERWORLD || defined END
                vec3 foamLight = getAmbientColor() * sky + getLightColor() * texture(colortex3, texcoord).r * 0.6;
            #else
                vec3 foamLight = getAmbientColor();
            #endif
            color = mix(color, foamLight * 0.8, foam * 0.55);
        }

        float NdotV = saturate(dot(n, V));
        float F = fresnel(NdotV, 0.02);
        if (isEyeInWater == 1) F = NdotV < 0.66 ? 1.0 : F * 0.5; // total internal reflection
        vec3 refl = getReflection(viewPos0, n, isEyeInWater == 1 ? 0.0 : skyLM, noise, true);
        if (isEyeInWater == 1) refl = getWaterScatterColor() * 0.8;
        color = mix(color, refl, F);

        #if defined OVERWORLD || defined END
            float sunVis = texture(colortex3, texcoord).r;
            vec3 L = getLightDir();
            float Fl = fresnel(saturate(dot(normalize(L + V), V)), 0.02);
            color += getLightColor() * specGGX(n, V, L, 0.985) * Fl * sunVis * (isEyeInWater == 1 ? 0.0 : 1.0);
        #endif

        if (isEyeInWater == 0) {
            // re-apply fog for the surface itself (background was fogged at its own distance)
            vec3 foggedSurface = applyFog(color, viewPos0, viewToPlayer(viewPos0));
            color = mix(color, foggedSurface, 0.85);
        }
    }
    else if (type == 1 && !hand) {
        //------------------------------------------------------------------------------------ glass & co.
        vec3 n = decodeNormal(trans.xy);
        vec4 extra = texture(colortex3, texcoord);
        float smoothness = extra.g;
        float NdotV = saturate(dot(n, -viewDir));
        float F = fresnel(NdotV, extra.b) * smoothness;
        #if REFLECTIONS == 2
            bool ssr = true;
        #else
            bool ssr = false;
        #endif
        vec3 refl = getReflection(viewPos0, n, skyLM, noise, ssr);
        color = mix(color, refl, F);
    }
    #if REFLECTIONS == 2
    else if (!hand && depth0 < 1.0 && depth0 == depth1) {
        //------------------------------------------------------------------------------------ opaque reflections
        vec4 matData = texture(colortex2, texcoord);
        float smoothness = matData.g;
        if (smoothness > 0.35) {
            vec4 data = texture(colortex1, texcoord);
            vec3 n = decodeNormal(data.xy);
            float sky = unpack2x8(data.b).y;
            vec2 fa = unpack2x8(matData.b);
            float f0 = fa.x;
            bool metal = f0 >= 0.9;
            float rough = 1.0 - smoothness;
            // rough reflections: jitter normal, resolved by TAA
            vec2 h = vec2(noise, fract(noise * 13.37 + 0.37)) - 0.5;
            vec3 up = abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
            vec3 t = normalize(cross(up, n));
            vec3 b = cross(n, t);
            vec3 nj = normalize(n + (t * h.x + b * h.y) * rough * rough * 1.2);

            float NdotV = saturate(dot(nj, -viewDir));
            float F = metal ? 1.0 : fresnel(NdotV, f0);
            F *= smoothstep(0.35, 0.9, smoothness);
            vec3 refl = getReflection(viewPos0, nj, sky, noise, true);
            if (metal) {
                vec3 tint = color / max(luma(color), 1e-4);
                refl *= mix(vec3(1.0), clamp(tint, 0.0, 3.0), 0.8);
                F *= 0.55;
            }
            color = mix(color, refl, F);
        }
    }
    #endif

    if (isEyeInWater == 1) {
        float dist = depth0 >= 1.0 ? far : length(viewPos0);
        color = applyUnderwaterFog(color, dist);
    }

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}
#endif
