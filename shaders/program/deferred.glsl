/*
    Yukitus Shader - deferred: sky, clouds, SSAO and fog for opaque geometry
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
uniform sampler2D depthtex0;

#include "/lib/colors.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"
#include "/lib/clouds.glsl"

float getSSAO(vec3 viewPos, vec3 normal, float noise) {
    const int samples = 8;
    const float radius = 0.7;
    vec3 up = abs(normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 t = normalize(cross(up, normal));
    vec3 b = cross(normal, t);
    float occlusion = 0.0;
    float rot = noise * TAU;
    for (int i = 0; i < samples; i++) {
        float fi = (float(i) + fract(noise * 7.31 + float(i) * 0.618)) / float(samples);
        vec2 disk = vogelDisk(i, samples, rot);
        float z = sqrt(max(1.0 - dot(disk, disk), 0.0));
        vec3 dir = t * disk.x + b * disk.y + normal * (z + 0.15);
        vec3 samplePos = viewPos + dir * radius * mix(0.2, 1.0, fi * fi);
        vec3 ss = viewToScreen(samplePos);
        if (any(lessThan(ss.xy, vec2(0.0))) || any(greaterThan(ss.xy, vec2(1.0)))) continue;
        float sd = texture(depthtex0, ss.xy).r;
        if (sd < 0.56) continue;
        vec3 sv = screenToView(vec3(ss.xy, sd));
        float diff = sv.z - samplePos.z;
        float rangeCheck = smoothstep(0.0, 1.0, radius / abs(viewPos.z - sv.z));
        occlusion += step(0.03, diff) * rangeCheck;
    }
    return 1.0 - occlusion / float(samples);
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    vec3 viewPos = screenToView(vec3(texcoord, depth));
    vec3 viewDir = normalize(viewPos);
    vec3 worldDir = mat3(gbufferModelViewInverse) * viewDir;
    float noise = dither(gl_FragCoord.xy);

    if (depth >= 1.0) {
        color = getSkyFull(viewDir, worldDir, noise);
        #if defined OVERWORLD && defined VOLUMETRIC_CLOUDS
            vec4 clouds = getVolumetricClouds(worldDir, 1e7, noise);
            color = color * clouds.a + clouds.rgb;
        #endif
        #ifdef OVERWORLD
            // looking at the sky from a cave: keep it, but block light leaks are handled by fog
        #endif
        color *= 1.0 - max(blindness, darknessFactor);
    } else {
        vec3 playerPos = viewToPlayer(viewPos);
        vec4 matData = texture(colortex2, texcoord);
        float matClass = floor(matData.r * 255.0 + 0.5);
        bool hand = depth < 0.56;

        #ifdef SSAO
            if (!hand && matClass != MAT_NOFOG && matClass != MAT_EMISSIVE) {
                vec3 normal = decodeNormal(texture(colortex1, texcoord).xy);
                float aoWeight = unpack2x8(matData.b).y;
                if (aoWeight > 0.01) {
                    float ao = getSSAO(viewPos, normal, noise);
                    ao = pow(ao, 1.5 * SSAO_STRENGTH);
                    color *= mix(1.0, ao, aoWeight);
                }
            }
        #endif

        if (!hand && matClass != MAT_NOFOG) {
            #if defined OVERWORLD && defined VOLUMETRIC_CLOUDS
                if (cameraPosition.y > cloudBottom - 16.0 || playerPos.y + cameraPosition.y > cloudBottom) {
                    vec4 clouds = getVolumetricClouds(worldDir, length(playerPos), noise);
                    color = color * clouds.a + clouds.rgb;
                }
            #endif
            color = applyFog(color, viewPos, playerPos);
        }
    }

    outColor = vec4(max(color, vec3(0.0)), 1.0);
}
#endif
