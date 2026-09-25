/*
    Yukitus Shader - shadow pass
*/
#define SHADOW_PASS
#include "/lib/common.glsl"
#include "/lib/shadows.glsl"

#ifdef VSH
//==================================================================================================
in vec4 mc_Entity;
in vec4 mc_midTexCoord;

out vec2 texcoord;
out vec4 glcolor;
out vec3 worldPos;
flat out int matId;

#include "/lib/waving.glsl"

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;
    matId = int(mc_Entity.x + 0.5);

    vec4 shadowViewPos = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPos = (shadowModelViewInverse * shadowViewPos).xyz;
    worldPos = playerPos + cameraPosition;

    #if defined WAVING_PLANTS || defined WAVING_LEAVES
        if (matId >= 10001 && matId <= 10006) {
            vec2 lm = saturate(((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy - 0.03125) * 1.06667);
            bool isTop = gl_MultiTexCoord0.t < mc_midTexCoord.t;
            playerPos += getWaving(worldPos, matId, isTop, lm.y);
        }
    #endif

    gl_Position = gl_ProjectionMatrix * (shadowModelView * vec4(playerPos, 1.0));
    gl_Position.xyz = distortShadowClip(gl_Position.xyz);
}
#endif

#ifdef FSH
//==================================================================================================
in vec2 texcoord;
in vec4 glcolor;
in vec3 worldPos;
flat in int matId;

uniform sampler2D gtexture;

#include "/lib/water.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 shadowColorOut;

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;

    if (matId == 10010) {
        // water: tinted caustic light instead of a hard shadow
        vec3 tint = vec3(0.55, 0.85, 0.95);
        #ifdef WATER_CAUSTICS
            tint *= getCaustics(worldPos);
        #endif
        shadowColorOut = vec4(saturate(tint * 0.5), 1.0);
        return;
    }

    if (albedo.a < 0.1) discard;

    vec3 transmit = mix(vec3(1.0), toLinear(albedo.rgb), saturate(albedo.a * 1.4));
    transmit *= 1.0 - albedo.a * 0.35;
    shadowColorOut = vec4(transmit * 0.5, 1.0);
}
#endif
