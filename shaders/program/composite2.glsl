/*
    Yukitus Shader - composite2: temporal anti-aliasing + auto exposure
    colortex6 = history (rgb) + exposure (a)
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
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;

#include "/lib/bloom_tiles.glsl"

vec3 rgbToYCoCg(vec3 c) {
    return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b, 0.5 * c.r - 0.5 * c.b, -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 yCoCgToRgb(vec3 c) {
    return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

// perceptual weighting to reduce flicker of very bright pixels (Brian Karis, "High Quality Temporal Supersampling" 2014)
vec3 compress(vec3 c) { return c / (1.0 + luma(c)); }
vec3 decompress(vec3 c) { return c / max(1.0 - luma(c), 1e-3); }

vec3 sampleHistory(vec2 uv) {
    // 5-tap Catmull-Rom for a sharp history (Jorge Jimenez, Filmic SMAA 2016; Matt Pettineo's optimized version)
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 pos = uv * res;
    vec2 center = floor(pos - 0.5) + 0.5;
    vec2 f = pos - center;
    vec2 f2 = f * f, f3 = f2 * f;
    vec2 w0 = -0.5 * f3 + f2 - 0.5 * f;
    vec2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
    vec2 w2 = -1.5 * f3 + 2.0 * f2 + 0.5 * f;
    vec2 w3 = 0.5 * f3 - 0.5 * f2;
    vec2 w12 = w1 + w2;
    vec2 tc12 = (center + w2 / w12) / res;
    vec2 tc0 = (center - 1.0) / res;
    vec2 tc3 = (center + 2.0) / res;
    vec3 c = texture(colortex6, vec2(tc12.x, tc0.y)).rgb * (w12.x * w0.y)
           + texture(colortex6, vec2(tc0.x, tc12.y)).rgb * (w0.x * w12.y)
           + texture(colortex6, vec2(tc12.x, tc12.y)).rgb * (w12.x * w12.y)
           + texture(colortex6, vec2(tc3.x, tc12.y)).rgb * (w3.x * w12.y)
           + texture(colortex6, vec2(tc12.x, tc3.y)).rgb * (w12.x * w3.y);
    float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(c / wsum, vec3(0.0));
}

/* RENDERTARGETS: 0,6 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outHistory;

void main() {
    vec3 current = textureLod(colortex0, texcoord, 0.0).rgb;
    if (any(isnan(current)) || any(isinf(current))) current = vec3(0.0);

    //---------------------------------------------------------------------------------- exposure
    float prevExposure = texelFetch(colortex6, ivec2(0), 0).a;
    #ifdef AUTO_EXPOSURE
        // average of the previous frame's smallest bloom tile (1/128 res) - no extra mipmap chain needed
        const int tile = BLOOM_TILE_COUNT - 1;
        vec2 tOff = bloomTileOffset(tile);
        float tScale = bloomTileScale(tile);
        float avgLum = 0.0;
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                avgLum += luma(textureLod(colortex7, tOff + (vec2(x, y) + 0.5) / 4.0 * tScale, 0.0).rgb);
            }
        }
        avgLum = avgLum / 16.0;
        if (!(avgLum > 1e-4 && avgLum < 1e4)) avgLum = 0.2;
        float targetExposure = clamp(0.24 / avgLum, 0.35, 2.4);
        float adapt = 1.0 - exp(-frameTime * 1.2);
        float exposure = prevExposure > 0.0 && prevExposure < 100.0 ? mix(prevExposure, targetExposure, adapt) : targetExposure;
    #else
        float exposure = 1.0;
    #endif

    //---------------------------------------------------------------------------------- TAA
    #ifdef TAA
        float depth = texture(depthtex0, texcoord).r;
        vec2 prevUV = texcoord;
        if (depth >= 0.56) {
            vec3 viewPos = screenToView(vec3(texcoord, depth));
            vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
            vec3 camOffset = depth >= 1.0 ? vec3(0.0) : cameraPosition - previousCameraPosition;
            vec3 prevPlayer = playerPos + camOffset;
            vec3 prevView = mat3(gbufferPreviousModelView) * prevPlayer + gbufferPreviousModelView[3].xyz;
            vec4 prevClip = gbufferPreviousProjection * vec4(prevView, 1.0);
            prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
        }

        // neighborhood statistics: variance clipping (Marco Salvi, GDC 2016) in YCoCg
        vec2 px = texelSize();
        vec3 m1 = vec3(0.0), m2 = vec3(0.0);
        vec3 cMin = vec3(1e9), cMax = vec3(-1e9);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 c = rgbToYCoCg(compress(texture(colortex0, texcoord + vec2(x, y) * px).rgb));
                m1 += c; m2 += c * c;
                cMin = min(cMin, c); cMax = max(cMax, c);
            }
        }
        m1 /= 9.0; m2 /= 9.0;
        vec3 sigma = sqrt(max(m2 - m1 * m1, 0.0));
        vec3 boxMin = max(cMin, m1 - sigma * 1.25);
        vec3 boxMax = min(cMax, m1 + sigma * 1.25);

        bool offscreen = any(lessThan(prevUV, vec2(0.0))) || any(greaterThan(prevUV, vec2(1.0)));
        vec3 history = rgbToYCoCg(compress(sampleHistory(prevUV)));

        // clip towards the box center
        vec3 center = (boxMin + boxMax) * 0.5;
        vec3 extent = max((boxMax - boxMin) * 0.5, vec3(1e-5));
        vec3 dir = history - center;
        vec3 unit = abs(dir / extent);
        float maxUnit = maxOf(unit);
        if (maxUnit > 1.0) history = center + dir / maxUnit;

        vec2 velocity = (texcoord - prevUV) * vec2(viewWidth, viewHeight);
        float blend = 0.08 + saturate(length(velocity) * 0.04) * 0.25;
        if (offscreen) blend = 1.0;

        vec3 cur = rgbToYCoCg(compress(current));
        vec3 result = decompress(yCoCgToRgb(mix(history, cur, blend)));
        result = max(result, vec3(0.0));
        if (any(isnan(result)) || any(isinf(result))) result = current;
    #else
        vec3 result = current;
    #endif

    outColor = vec4(result, 1.0);
    outHistory = vec4(result, exposure);
}
#endif
