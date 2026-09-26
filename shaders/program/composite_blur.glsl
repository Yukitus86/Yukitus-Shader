/*
    Yukitus Shader - composite4/5: separable gaussian blur of the bloom tiles
    Variants: BLUR_H, BLUR_V
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

uniform sampler2D colortex7;

#include "/lib/bloom_tiles.glsl"

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outBloom;

const float weights[5] = float[5](0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162);

void main() {
    vec3 result = vec3(0.0);
    {
        for (int k = 0; k < BLOOM_TILE_COUNT; k++) {
            float s = bloomTileScale(k);
            vec2 off = bloomTileOffset(k);
            vec2 lo = off - s * 0.02;
            vec2 hi = off + s * 1.02;
            if (all(greaterThan(texcoord, lo)) && all(lessThan(texcoord, hi))) {
                #ifdef BLUR_H
                    vec2 dir = vec2(1.0 / viewWidth, 0.0);
                #else
                    vec2 dir = vec2(0.0, 1.0 / viewHeight);
                #endif
                vec2 halfTexel = 0.5 / vec2(viewWidth, viewHeight);
                result = texture(colortex7, texcoord).rgb * weights[0];
                for (int i = 1; i < 5; i++) {
                    vec2 o = dir * float(i) * 1.5;
                    result += texture(colortex7, clamp(texcoord + o, lo + halfTexel, hi - halfTexel)).rgb * weights[i];
                    result += texture(colortex7, clamp(texcoord - o, lo + halfTexel, hi - halfTexel)).rgb * weights[i];
                }
                break;
            }
        }
    }
    outBloom = vec4(result, 1.0);
}
#endif
