/*
    Yukitus Shader - final: DOF / motion blur, bloom, exposure, tonemapping, color grading
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

// bicubic b-spline upsampling (4 bilinear taps)
vec3 textureBicubic(sampler2D tex, vec2 uv) {
    vec2 res = vec2(viewWidth, viewHeight);
    vec2 pos = uv * res - 0.5;
    vec2 f = fract(pos);
    pos -= f;
    vec2 f2 = f * f, f3 = f2 * f;
    vec2 w0 = (1.0 / 6.0) * (-f3 + 3.0 * f2 - 3.0 * f + 1.0);
    vec2 w1 = (1.0 / 6.0) * (3.0 * f3 - 6.0 * f2 + 4.0);
    vec2 w2 = (1.0 / 6.0) * (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0);
    vec2 w3 = (1.0 / 6.0) * f3;
    vec2 s0 = w0 + w1, s1 = w2 + w3;
    vec2 t0 = (pos - 0.5 + w1 / s0) / res;
    vec2 t1 = (pos + 1.5 + w3 / s1) / res;
    return (texture(tex, vec2(t0.x, t0.y)).rgb * s0.x + texture(tex, vec2(t1.x, t0.y)).rgb * s1.x) * s0.y
         + (texture(tex, vec2(t0.x, t1.y)).rgb * s0.x + texture(tex, vec2(t1.x, t1.y)).rgb * s1.x) * s1.y;
}

vec3 tonemapACES(vec3 x) {
    // Stephen Hill's fitted ACES
    const mat3 inputM = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
    const mat3 outputM = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
    x = inputM * x;
    vec3 a = x * (x + 0.0245786) - 0.000090537;
    vec3 b = x * (0.983729 * x + 0.4329510) + 0.238081;
    return saturate(outputM * (a / b));
}

vec3 tonemapLottes(vec3 x) {
    const float a = 1.6, d = 0.977, hdrMax = 12.0, midIn = 0.18, midOut = 0.267;
    float b = (-pow(midIn, a) + pow(hdrMax, a) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);
    float c = (pow(hdrMax, a * d) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, a * d) * midOut) / ((pow(hdrMax, a * d) - pow(midIn, a * d)) * midOut);
    return saturate(pow(x, vec3(a)) / (pow(x, vec3(a * d)) * b + c));
}

vec3 tonemapReinhardJodie(vec3 c) {
    float l = luma(c);
    vec3 tc = c / (1.0 + c);
    return saturate(mix(c / (1.0 + l), tc, tc));
}

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    vec2 uv = texcoord;

    #ifdef UNDERWATER_DISTORTION
        if (isEyeInWater == 1) {
            uv += vec2(sin(uv.y * 24.0 + frameTimeCounter * 2.2), cos(uv.x * 20.0 + frameTimeCounter * 1.8)) * 0.0012;
        }
    #endif

    vec3 color = texture(colortex0, uv).rgb;

    //---------------------------------------------------------------------------------- sharpening
    #ifdef TAA
    if (SHARPENING > 0.0) {
        vec2 px = texelSize();
        vec3 n = texture(colortex0, uv + vec2(0.0, px.y)).rgb;
        vec3 s = texture(colortex0, uv - vec2(0.0, px.y)).rgb;
        vec3 e = texture(colortex0, uv + vec2(px.x, 0.0)).rgb;
        vec3 w = texture(colortex0, uv - vec2(px.x, 0.0)).rgb;
        vec3 mn = min(color, min(min(n, s), min(e, w)));
        vec3 mx = max(color, max(max(n, s), max(e, w)));
        vec3 blur = (n + s + e + w) * 0.25;
        vec3 sharp = color + (color - blur) * SHARPENING * 0.6;
        color = clamp(sharp, mn, mx);
    }
    #endif

    //---------------------------------------------------------------------------------- depth of field
    #ifdef DEPTH_OF_FIELD
    {
        float depth = texture(depthtex0, uv).r;
        if (depth >= 0.56) {
            float focus = linearizeDepth(centerDepthSmooth);
            float lin = linearizeDepth(depth);
            float coc = saturate(abs(lin - focus) / max(focus, 1.0) * 0.6) * 0.012 * DOF_STRENGTH;
            if (coc > 0.0005) {
                vec3 acc = vec3(0.0);
                const int taps = 24;
                float rot = dither(gl_FragCoord.xy) * TAU;
                for (int i = 0; i < taps; i++) {
                    vec2 o = vogelDisk(i, taps, rot) * coc * vec2(1.0 / aspectRatio, 1.0);
                    acc += texture(colortex0, uv + o).rgb;
                }
                color = acc / float(taps);
            }
        }
    }
    #endif

    //---------------------------------------------------------------------------------- motion blur
    #ifdef MOTION_BLUR
    {
        float depth = texture(depthtex0, uv).r;
        if (depth >= 0.56) {
            vec3 viewPos = screenToView(vec3(uv, depth));
            vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
            vec3 prevPlayer = playerPos + (depth >= 1.0 ? vec3(0.0) : cameraPosition - previousCameraPosition);
            vec4 prevClip = gbufferPreviousProjection * vec4(mat3(gbufferPreviousModelView) * prevPlayer + gbufferPreviousModelView[3].xyz, 1.0);
            vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
            vec2 vel = (uv - prevUV) * 0.5 * MOTION_BLUR_STRENGTH;
            vel = clamp(vel, vec2(-0.05), vec2(0.05));
            vec3 acc = color;
            float noise = dither(gl_FragCoord.xy);
            for (int i = 1; i < 6; i++) {
                acc += texture(colortex0, uv - vel * (float(i) + noise - 0.5) / 5.0).rgb;
            }
            color = acc / 6.0;
        }
    }
    #endif

    //---------------------------------------------------------------------------------- bloom
    #ifdef BLOOM
    {
        vec3 bloom = vec3(0.0);
        float wsum = 0.0;
        for (int k = 0; k < BLOOM_TILE_COUNT; k++) {
            float s = bloomTileScale(k);
            vec2 off = bloomTileOffset(k);
            float w = 1.0 + float(k) * 0.25;
            bloom += textureBicubic(colortex7, uv * s + off) * w;
            wsum += w;
        }
        bloom /= wsum;
        float amount = 0.06 * BLOOM_STRENGTH;
        if (isEyeInWater == 1) amount *= 2.5;
        amount *= 1.0 + rainStrength * 0.6;
        color = mix(color, bloom, amount);
    }
    #endif

    //---------------------------------------------------------------------------------- exposure & tonemap
    #ifdef AUTO_EXPOSURE
        float exposure = texelFetch(colortex6, ivec2(0), 0).a;
        if (!(exposure > 0.0 && exposure < 100.0)) exposure = 1.0;
    #else
        float exposure = 1.0;
    #endif
    color *= exposure * EXPOSURE * 1.1;

    #if TONEMAP == 0
        color = tonemapACES(color * 1.25);
    #elif TONEMAP == 1
        color = tonemapLottes(color);
    #else
        color = tonemapReinhardJodie(color * 1.2);
    #endif

    //---------------------------------------------------------------------------------- grading
    float l = luma(color);
    color = mix(vec3(l), color, SATURATION);
    float sat = maxOf(color) - minOf(color);
    color = mix(vec3(luma(color)), color, 1.0 + (VIBRANCE - 1.0) * (1.0 - sat));
    color = saturate(color);

    color = toSRGB(color);
    color = saturate((color - 0.5) * CONTRAST + 0.5);

    vec2 vc = texcoord - 0.5;
    color *= saturate(1.0 - dot(vc, vc) * VIGNETTE * 1.1);

    // dither to avoid banding
    color += (dither(gl_FragCoord.xy) - 0.5) / 255.0;

    outColor = vec4(color, 1.0);
}
#endif
