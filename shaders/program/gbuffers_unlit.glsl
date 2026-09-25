/*
    Yukitus Shader - simple / unlit geometry
    Variants: GB_BASIC, GB_SKYBASIC, GB_SKYTEXTURED, GB_CLOUDS, GB_BEACON, GB_SPIDEREYES, GB_GLINT, GB_DAMAGED
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

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    #if defined GB_SKYBASIC || defined GB_SKYTEXTURED
        // the sky is fully procedural (deferred pass)
        discard;
    #elif defined GB_CLOUDS
        #ifdef VOLUMETRIC_CLOUDS
            discard;
        #else
            vec4 albedo = texture(gtexture, texcoord) * glcolor;
            if (albedo.a < 0.05) discard;
            vec3 c = toLinear(albedo.rgb) * (getAmbientColor() * 1.3 + getLightColor() * 0.45);
            c = applyFog(c, viewPos, viewToPlayer(viewPos));
            outColor = vec4(c, albedo.a);
        #endif
    #elif defined GB_BEACON
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
        if (albedo.a < 0.02) discard;
        outColor = vec4(toLinear(albedo.rgb) * 6.0 * EMISSION_STRENGTH, albedo.a);
    #elif defined GB_SPIDEREYES
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
        if (albedo.a < 0.02) discard;
        outColor = vec4(toLinear(albedo.rgb) * 4.0 * EMISSION_STRENGTH, albedo.a);
    #elif defined GB_GLINT
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
        outColor = vec4(toLinear(albedo.rgb) * 1.6, albedo.a);
    #elif defined GB_DAMAGED
        vec4 albedo = texture(gtexture, texcoord) * glcolor;
        if (albedo.a < 0.02) discard;
        outColor = albedo;
    #else
        // basic: lines, leashes, debug geometry
        vec4 albedo = glcolor;
        #ifdef GB_TEXTURED_BASIC
            albedo *= texture(gtexture, texcoord);
        #endif
        if (albedo.a < 0.02) discard;
        vec3 c = toLinear(albedo.rgb);
        if (lmcoord.x + lmcoord.y > 0.02) {
            #ifdef OVERWORLD
                c *= getAmbientColor() * lmcoord.y * lmcoord.y + getBlockLight(lmcoord.x) + getLightColor() * 0.3 * lmcoord.y + getMinLight() * 4.0;
            #else
                c *= getAmbientColor() + getBlockLight(lmcoord.x) + getMinLight() * 4.0;
            #endif
        }
        outColor = vec4(c, albedo.a);
    #endif
}
#endif
