/*
    Yukitus Shader - rain and snow
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
    glcolor = gl_Color;
    gl_Position = ftransform();
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

uniform sampler2D gtexture;

#include "/lib/colors.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.02) discard;

    vec3 light = getAmbientColor() * max(lmcoord.y, 0.3) * 1.2 + getLightColor() * 0.15 + getBlockLight(lmcoord.x);
    float isSnow = step(0.75, minOf(albedo.rgb));
    outColor = vec4(toLinear(albedo.rgb) * light, albedo.a * mix(0.35, 0.9, isSnow));
}
#endif
