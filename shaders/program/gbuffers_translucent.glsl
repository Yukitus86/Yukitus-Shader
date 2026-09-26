/*
    Yukitus Shader - translucent geometry (water, stained glass, ice, slime, portals, held translucents)
    Variants: GB_WATER, GB_HAND_WATER
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
in vec4 mc_Entity;
in vec4 at_tangent;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 viewPos;
out vec3 normal;
out vec3 worldPos;
flat out int matId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
    glcolor = gl_Color;
    normal = safeNormalize(gl_NormalMatrix * gl_Normal, vec3(0.0, 0.0, 1.0));
    #ifdef GB_WATER
        matId = int(mc_Entity.x + 0.5);
    #else
        matId = 0;
    #endif

    vec4 vpos = gl_ModelViewMatrix * gl_Vertex;
    worldPos = viewToPlayer(vpos.xyz) + cameraPosition;
    viewPos = vpos.xyz;
    gl_Position = gl_ProjectionMatrix * vpos;
    #ifdef TAA
        gl_Position.xy += taaJitter() * gl_Position.w;
    #endif
}
#endif

#ifdef FSH
//==================================================================================================
in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 normal;
in vec3 worldPos;
flat in int matId;

uniform sampler2D gtexture;

#include "/lib/colors.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"
#include "/lib/shadows.glsl"
#include "/lib/clouds.glsl"
#include "/lib/materials.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"

/* RENDERTARGETS: 0,3,5 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outExtra;   // sunVis, smoothness, f0
layout(location = 2) out vec4 outTrans;   // normal.xy, pack(type, skylight)

void main() {
    #ifdef GB_WATER
        // separateAo: vertex alpha holds vanilla AO, not opacity
        vec4 albedo = texture(gtexture, texcoord) * vec4(glcolor.rgb, 1.0);
    #else
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
    #endif
    vec3 geoNormal = safeNormalize(normal, vec3(0.0, 0.0, 1.0));
    if (!gl_FrontFacing) geoNormal = -geoNormal;
    float noise = dither(gl_FragCoord.xy);
    vec3 playerPos = viewToPlayer(viewPos);

    if (matId == 10010) {
        //------------------------------------------------------------------------------------ water
        vec3 n = geoNormal;
        #ifdef WATER_WAVES
            vec3 worldN = mat3(gbufferModelViewInverse) * geoNormal;
            if (abs(worldN.y) > 0.5) {
                vec3 wn = getWaveNormal(worldPos, 1.0);
                wn.y *= sign(worldN.y);
                // fade waves at distance to reduce aliasing
                float fadeW = exp(-length(viewPos) / 96.0);
                wn = normalize(mix(vec3(0.0, sign(worldN.y), 0.0), wn, fadeW));
                n = normalize(mat3(gbufferModelView) * wn);
            }
        #endif

        Material mat = Material(0.98, 0.02, 0.0, 0.0, MAT_GENERIC);
        LightingResult light = getLighting(toLinear(albedo.rgb), viewPos, n, geoNormal, lmcoord, 1.0, mat, noise);

        #if WATER_STYLE == 0
            outColor = vec4(0.0);
        #elif WATER_STYLE == 1
            vec3 c = applyFog(light.color * 0.5, viewPos, playerPos);
            outColor = vec4(c, albedo.a * 0.35);
        #else
            vec3 c = applyFog(light.color, viewPos, playerPos);
            outColor = vec4(c, albedo.a);
        #endif

        outExtra = vec4(light.sunVis, 0.98, 0.02, 1.0);
        outTrans = vec4(encodeNormal(n), pack2x8(vec2(2.0 / 4.0, lmcoord.y)), 1.0);
        return;
    }

    if (albedo.a < 0.02) discard;

    //------------------------------------------------------------------------------------ other translucents
    Material mat = Material(0.9, 0.04, 0.0, 0.0, MAT_GENERIC);
    float type = 1.0 / 4.0;
    if (matId == 10011) { mat.smoothness = 0.92; mat.f0 = 0.02; }     // ice
    if (matId == 10013) { mat.smoothness = 0.75; mat.sss = 0.5; }     // slime / honey
    if (matId == 10014) {                                              // nether portal
        mat.emission = 0.6 + luma(albedo.rgb);
        type = 0.0;
    }
    #ifdef GB_HAND_WATER
        type = 0.0;
    #endif

    vec3 albedoL = toLinear(albedo.rgb);
    LightingResult light = getLighting(albedoL, viewPos, geoNormal, geoNormal, lmcoord, 1.0, mat, noise);
    vec3 c = light.color;
    #ifndef GB_HAND_WATER
        c = applyFog(c, viewPos, playerPos);
    #endif

    outColor = vec4(c, albedo.a);
    outExtra = vec4(light.sunVis, mat.smoothness, mat.f0, 1.0);
    outTrans = vec4(encodeNormal(geoNormal), pack2x8(vec2(type, lmcoord.y)), 1.0);
}
#endif
