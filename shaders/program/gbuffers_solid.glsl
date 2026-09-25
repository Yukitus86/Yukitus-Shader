/*
    Yukitus Shader - opaque geometry (terrain, block entities, entities, hand)
    Variants: GB_TERRAIN, GB_BLOCK, GB_ENTITIES, GB_HAND
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
in vec4 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_tangent;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 viewPos;
out vec3 normal;
out vec4 tangent;
out vec3 worldPos;
flat out int matId;

#include "/lib/waving.glsl"

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
    glcolor = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
    tangent = vec4(normalize(gl_NormalMatrix * at_tangent.xyz), at_tangent.w < 0.0 ? -1.0 : 1.0);

    #ifdef GB_TERRAIN
        matId = int(mc_Entity.x + 0.5);
    #else
        matId = 0;
    #endif

    vec4 vpos = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPos = viewToPlayer(vpos.xyz);
    worldPos = playerPos + cameraPosition;

    #if defined GB_TERRAIN && (defined WAVING_PLANTS || defined WAVING_LEAVES)
        if (matId >= 10001 && matId <= 10006) {
            bool isTop = gl_MultiTexCoord0.t < mc_midTexCoord.t;
            playerPos += getWaving(worldPos, matId, isTop, lmcoord.y);
            vpos.xyz = playerToView(playerPos);
        }
    #endif

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
in vec4 tangent;
in vec3 worldPos;
flat in int matId;

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform ivec2 atlasSize;
uniform vec4 entityColor;
uniform int entityId;
uniform int blockEntityId;

#include "/lib/colors.glsl"
#include "/lib/shadows.glsl"
#include "/lib/clouds.glsl"
#include "/lib/materials.glsl"
#include "/lib/lighting.glsl"

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outMat;

void main() {
    vec4 albedo = texture(gtexture, texcoord);
    #ifdef GB_TERRAIN
        // separateAo: vertex alpha holds vanilla AO
        float vanillaAO = glcolor.a;
        albedo.rgb *= glcolor.rgb;
    #else
        float vanillaAO = 1.0;
        albedo *= glcolor;
    #endif
    if (albedo.a < 0.1) discard;

    #ifdef GB_ENTITIES
        albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
    #endif

    int id = matId;
    #ifdef GB_BLOCK
        id = blockEntityId;
    #endif

    vec3 albedoL = toLinear(albedo.rgb);
    Material mat = getMaterial(id, albedo.rgb);

    #ifdef GB_ENTITIES
        if (entityId == 20001) { // lightning
            outColor = vec4(vec3(0.8, 0.85, 1.0) * 40.0, 1.0);
            outData = vec4(0.5, 0.5, 0.0, 1.0);
            outMat = vec4(MAT_NOFOG / 255.0, 0.0, 0.0, 1.0);
            return;
        }
    #endif

    #ifdef GB_BLOCK
        if (id == 10060) { // end portal / gateway: parallax star field
            vec3 dir = normalize(viewToPlayer(viewPos) - gbufferModelViewInverse[3].xyz);
            vec3 c = vec3(0.0);
            for (int i = 0; i < 6; i++) {
                float layer = 1.0 + float(i) * 0.6;
                vec2 uv = worldPos.xz * 0.12 / layer + dir.xz / max(abs(dir.y), 0.15) * float(i) * 0.08 + frameTimeCounter * 0.002 * layer;
                float n = texture(noisetex, uv).r;
                float star = pow(saturate((n - 0.72) * 4.0), 3.0);
                c += mix(vec3(0.15, 0.55, 0.5), vec3(0.45, 0.2, 0.8), fract(float(i) * 0.37)) * star / layer;
            }
            c += vec3(0.02, 0.03, 0.05);
            outColor = vec4(c * 4.0, 1.0);
            outData = vec4(encodeNormal(normalize(normal)), pack2x8(lmcoord), 1.0);
            outMat = vec4(MAT_EMISSIVE / 255.0, 0.0, pack2x8(vec2(0.04, 0.0)), 1.0);
            return;
        }
    #endif

    vec3 geoNormal = normalize(normal);
    if (!gl_FrontFacing && mat.sss > 0.0) geoNormal = -geoNormal;
    vec3 n = geoNormal;

    #if PBR_MODE == 1
        vec4 nTex = texture(normals, texcoord);
        vec4 sTex = texture(specular, texcoord);
        applyLabPBR(mat, sTex);
        if (nTex.a > 0.0 || nTex.x + nTex.y > 0.0) {
            vec3 tn;
            tn.xy = nTex.xy * 2.0 - 1.0;
            tn.z = sqrt(saturate(1.0 - dot(tn.xy, tn.xy)));
            tn.xy *= NORMAL_STRENGTH;
            vec3 t = normalize(tangent.xyz);
            vec3 b = cross(t, geoNormal) * tangent.w;
            n = normalize(mat3(t, b, geoNormal) * tn);
            vanillaAO *= mix(1.0, nTex.b, 0.8);
        }
    #elif defined GENERATED_NORMALS
        {
            vec2 texel = 1.0 / vec2(max(atlasSize, ivec2(1)));
            float h0 = luma(texture(gtexture, texcoord).rgb);
            float hx = luma(texture(gtexture, texcoord + vec2(texel.x, 0.0)).rgb);
            float hy = luma(texture(gtexture, texcoord + vec2(0.0, texel.y)).rgb);
            vec3 tn = normalize(vec3((h0 - hx) * 2.0 * NORMAL_STRENGTH, (h0 - hy) * 2.0 * NORMAL_STRENGTH, 1.0));
            vec3 t = normalize(tangent.xyz);
            vec3 b = cross(t, geoNormal) * tangent.w;
            n = normalize(mat3(t, b, geoNormal) * tn);
        }
    #endif

    vec2 lm = lmcoord;

    // Rain: wet surfaces and puddles
    #if defined OVERWORLD && defined RAIN_PUDDLES
        if (wetness > 0.01 && mat.emission < 0.1) {
            float up = dot(geoNormal, getUpDir());
            float exposed = smoothstep(0.88, 0.97, lm.y);
            float wet = wetness * exposed;
            if (wet > 0.0) {
                bool porous = id == 10041 || mat.matClass == MAT_FOLIAGE;
                float puddle = 0.0;
                if (up > 0.9) {
                    float p = texture(noisetex, worldPos.xz / 96.0).r * 0.7 + texture(noisetex, worldPos.xz / 24.0).g * 0.3;
                    puddle = smoothstep(0.55 - 0.1 * PUDDLE_AMOUNT, 0.62 - 0.1 * PUDDLE_AMOUNT, p) * wet;
                    if (porous) puddle *= mat.matClass == MAT_FOLIAGE ? 0.0 : 0.55;
                }
                albedoL *= 1.0 - 0.35 * wet * (porous ? 1.0 : 0.5) * (1.0 - puddle);
                mat.smoothness = mix(mat.smoothness, porous ? 0.5 : 0.72, wet * 0.6);
                mat.smoothness = mix(mat.smoothness, 0.97, puddle);
                mat.f0 = mat.f0 >= 0.9 ? mat.f0 : mix(mat.f0, 0.02, puddle);
                n = normalize(mix(n, geoNormal, puddle));
            }
        }
    #endif

    #ifdef GB_HAND
        mat.matClass = MAT_HAND;
    #endif

    float noise = dither(gl_FragCoord.xy);
    LightingResult light = getLighting(albedoL, viewPos, n, geoNormal, lm, vanillaAO, mat, noise);

    outColor = vec4(light.color, 1.0);
    outData = vec4(encodeNormal(n), pack2x8(lm), 1.0);
    outMat = vec4(mat.matClass / 255.0, mat.smoothness, pack2x8(vec2(mat.f0, light.aoWeight)), 1.0);
}
#endif
