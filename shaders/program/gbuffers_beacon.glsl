/*
    Yukitus Shader - beacon beam (emissive, also marks colortex2 so later passes skip SSAO/reflections)
*/
#include "/lib/common.glsl"

#ifdef VSH
//==================================================================================================
out vec2 texcoord;
out vec4 glcolor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
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
in vec4 glcolor;

uniform sampler2D gtexture;

/* RENDERTARGETS: 0,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outMat;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
    if (albedo.a < 0.02) discard;
    outColor = vec4(toLinear(albedo.rgb) * 6.0 * EMISSION_STRENGTH, albedo.a);
    outMat = vec4(MAT_EMISSIVE / 255.0, 0.0, 0.0, 1.0);
}
#endif
