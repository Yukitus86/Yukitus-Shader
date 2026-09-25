/*
    Yukitus Shader - composite1: volumetric light (god rays) through the shadow map
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
uniform sampler2D depthtex0;

#include "/lib/colors.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"
#include "/lib/shadows.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

float phaseHG(float c, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;

    #if defined VOLUMETRIC_LIGHT && defined SHADOWS && (defined OVERWORLD || defined END)
        float depth = texture(depthtex0, texcoord).r;
        vec3 viewPos = screenToView(vec3(texcoord, depth));
        vec3 playerPos = viewToPlayer(viewPos);
        float dist = length(playerPos);
        vec3 worldDir = playerPos / max(dist, 1e-4);

        float eyeSky = getEyeSkyLight();
        bool underwater = isEyeInWater == 1;
        #ifdef OVERWORLD
            float strength = eyeSky;
        #else
            float strength = 1.0;
        #endif
        if (underwater) strength = max(eyeSky, 0.3);

        vec3 lightC = getLightColor();
        if (strength > 0.01 && maxOf(lightC) > 0.001 && isEyeInWater < 2) {
            #if VL_QUALITY == 0
                const int steps = 6;
            #elif VL_QUALITY == 1
                const int steps = 10;
            #else
                const int steps = 18;
            #endif
            float maxDist = min(depth >= 1.0 ? shadowDistance : dist, shadowDistance);
            if (underwater) maxDist = min(maxDist, 48.0);
            float noise = dither(gl_FragCoord.xy);

            float vis = 0.0;
            float stepLen = maxDist / float(steps);
            for (int i = 0; i < steps; i++) {
                // quadratic distribution: more samples close to the camera
                float fi = (float(i) + noise) / float(steps);
                vec3 p = worldDir * maxDist * fi * fi;
                vis += sampleShadowSimple(p) * 2.0 * fi;
            }
            vis /= float(steps);

            float VdotL = dot(worldDir, getLightDirWorld());
            float e = getSunElevation();
            #ifdef OVERWORLD
                float dayF = getDayFactor(e);
                float setF = getSunsetFactor(e);
                float density = 0.0012 + 0.0035 * setF + 0.0025 * (1.0 - dayF) + 0.009 * rainStrength;
                #ifdef MORNING_FOG
                    if (sunAngle < 0.25 || sunAngle > 0.75) density *= 1.6;
                #endif
                float phase = mix(phaseHG(VdotL, 0.65), 1.0 / (4.0 * PI), 0.35) * 4.0 * PI;
                vec3 vlColor = lightC;
            #else
                float density = 0.004 * END_FOG;
                float phase = mix(phaseHG(VdotL, 0.55), 1.0 / (4.0 * PI), 0.5) * 4.0 * PI;
                vec3 vlColor = lightC * vec3(0.8, 0.6, 1.0);
            #endif

            if (underwater) {
                density = 0.03 * WATER_FOG_DENSITY;
                vlColor = lightC * vec3(0.25, 0.7, 0.8);
            }

            float scatterAmount = 1.0 - exp(-maxDist * density);
            color += vlColor * vis * phase * scatterAmount * strength * 0.3 * VL_STRENGTH;
        }
    #endif

    outColor = vec4(color, 1.0);
}
#endif
