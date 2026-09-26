/*
    Yukitus Shader - composite3: bloom downsample into tiles (colortex7)
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

const bool colortex0MipmapEnabled = true;

#include "/lib/bloom_tiles.glsl"

/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outBloom;

void main() {
    vec3 result = vec3(0.0);
    {
        for (int k = 0; k < BLOOM_TILE_COUNT; k++) {
            float s = bloomTileScale(k);
            vec2 off = bloomTileOffset(k);
            vec2 local = (texcoord - off) / s;
            // include a small border so the blur has data to work with
            if (all(greaterThan(local, vec2(-0.02))) && all(lessThan(local, vec2(1.02)))) {
                local = clamp(local, 0.0, 1.0);
                float lod = float(k + 1);
                vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
                vec3 c = textureLod(colortex0, local, lod).rgb * 0.5
                       + textureLod(colortex0, local + vec2( texel.x,  texel.y), lod).rgb * 0.125
                       + textureLod(colortex0, local + vec2(-texel.x,  texel.y), lod).rgb * 0.125
                       + textureLod(colortex0, local + vec2( texel.x, -texel.y), lod).rgb * 0.125
                       + textureLod(colortex0, local + vec2(-texel.x, -texel.y), lod).rgb * 0.125;
                result = clamp(c, vec3(0.0), vec3(256.0));
                if (any(isnan(result))) result = vec3(0.0);
                break;
            }
        }
    }
    outBloom = vec4(result, 1.0);
}
#endif
