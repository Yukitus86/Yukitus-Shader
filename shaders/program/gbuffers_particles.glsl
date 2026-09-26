/*
    Yukitus Shader - particles
    Variants: GB_TEXTURED
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 viewPos;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
    glcolor = gl_Color;
    vec4 vpos = gl_ModelViewMatrix * gl_Vertex;
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

uniform sampler2D gtexture;

#include "/lib/colors.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"
#include "/lib/shadows.glsl"
#include "/lib/clouds.glsl"
#include "/lib/materials.glsl"
#include "/lib/lighting.glsl"

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outData;
layout(location = 2) out vec4 outMat;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.1) discard;

    vec3 albedoL = toLinear(albedo.rgb);
    vec3 c = getSimpleLighting(albedoL, viewPos, lmcoord);
    // fullbright particles (flames, sparks, portal, ...) glow
    if (lmcoord.x > 0.99 && luma(albedo.rgb) > 0.45) c += albedoL * 2.5 * EMISSION_STRENGTH;
    c = applyFog(c, viewPos, viewToPlayer(viewPos));

    outColor = vec4(c, albedo.a);
    outData = vec4(encodeNormal(vec3(0.0, 0.0, 1.0)), pack2x8(lmcoord), 1.0);
    outMat = vec4(MAT_NOFOG / 255.0, 0.0, 0.0, 1.0);
}
#endif
