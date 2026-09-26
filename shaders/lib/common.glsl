/*
    Yukitus Shader - common uniforms and helper functions
*/
#ifndef COMMON_GLSL
#define COMMON_GLSL

#include "/lib/settings.glsl"

#if !defined OVERWORLD && !defined NETHER && !defined END
    #define OVERWORLD
#endif

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16;
const int colortex2Format = RGBA16;
const int colortex3Format = RGBA8;
const int colortex5Format = RGBA16;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;

const bool colortex0Clear = true;
const bool colortex1Clear = true;
const bool colortex2Clear = true;
const bool colortex3Clear = true;
const bool colortex5Clear = true;
const bool colortex6Clear = false;
const bool colortex7Clear = false;

const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 1.0);
*/

//--------------------------------------------------------------------------------------------------
// Uniforms
//--------------------------------------------------------------------------------------------------
uniform float frameTimeCounter;
uniform float frameTime;
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;
uniform float sunAngle;
uniform int worldTime;
uniform int moonPhase;

uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform float screenBrightness;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform float centerDepthSmooth;

// custom uniform (shaders.properties)
uniform float snowiness;

uniform sampler2D noisetex;

//--------------------------------------------------------------------------------------------------
// Constants & small helpers
//--------------------------------------------------------------------------------------------------
const float PI = 3.14159265359;
const float TAU = 6.28318530718;
const float GOLDEN_ANGLE = 2.39996322973;

#define saturate(x) clamp(x, 0.0, 1.0)

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float pow2(float x) { return x * x; }
float pow4(float x) { x *= x; return x * x; }
float pow8(float x) { x *= x; x *= x; return x * x; }
vec3 safeNormalize(vec3 v, vec3 fallback) {
    float l = dot(v, v);
    return l > 1e-12 ? v * inversesqrt(l) : fallback;
}
float maxOf(vec3 v) { return max(v.x, max(v.y, v.z)); }
float minOf(vec3 v) { return min(v.x, min(v.y, v.z)); }

vec3 toLinear(vec3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
vec3 toSRGB(vec3 c)   { return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

vec2 viewSize()  { return vec2(viewWidth, viewHeight); }
vec2 texelSize() { return 1.0 / vec2(viewWidth, viewHeight); }

vec3 projectAndDivide(mat4 m, vec3 p) {
    vec4 h = m * vec4(p, 1.0);
    return h.xyz / h.w;
}

vec3 screenToView(vec3 screenPos) {
    return projectAndDivide(gbufferProjectionInverse, screenPos * 2.0 - 1.0);
}

vec3 viewToScreen(vec3 viewPos) {
    return projectAndDivide(gbufferProjection, viewPos) * 0.5 + 0.5;
}

vec3 viewToPlayer(vec3 viewPos) {
    return mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
}

vec3 playerToView(vec3 playerPos) {
    return mat3(gbufferModelView) * playerPos + gbufferModelView[3].xyz;
}

float linearizeDepth(float depth) {
    return (near * far) / (depth * (near - far) + far);
}

//--------------------------------------------------------------------------------------------------
// Noise
//--------------------------------------------------------------------------------------------------
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash23(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Interleaved gradient noise, animated when TAA is on so it gets resolved over time
float dither(vec2 fragCoord) {
    #ifdef TAA
        fragCoord += 5.588238 * float(frameCounter & 63);
    #endif
    return fract(52.9829189 * fract(0.06711056 * fragCoord.x + 0.00583715 * fragCoord.y));
}

vec2 vogelDisk(int i, int n, float phi) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float theta = float(i) * GOLDEN_ANGLE + phi;
    return r * vec2(cos(theta), sin(theta));
}

//--------------------------------------------------------------------------------------------------
// Packing
//--------------------------------------------------------------------------------------------------
vec2 encodeNormal(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    if (n.z < 0.0) {
        vec2 s = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * s;
    }
    return n.xy * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 f) {
    f = f * 2.0 - 1.0;
    vec3 n = vec3(f, 1.0 - abs(f.x) - abs(f.y));
    float t = saturate(-n.z);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;
    return normalize(n);
}

float pack2x8(vec2 v) {
    v = floor(saturate(v) * 255.0 + 0.5);
    return (v.x + v.y * 256.0) / 65535.0;
}

vec2 unpack2x8(float f) {
    float v = floor(f * 65535.0 + 0.5);
    return vec2(mod(v, 256.0), floor(v / 256.0)) / 255.0;
}

//--------------------------------------------------------------------------------------------------
// Temporal jitter
//--------------------------------------------------------------------------------------------------
const vec2 taaOffsets[8] = vec2[8](
    vec2( 0.125, -0.375), vec2(-0.125,  0.375),
    vec2( 0.625,  0.125), vec2( 0.375, -0.625),
    vec2(-0.625,  0.625), vec2(-0.875, -0.125),
    vec2( 0.375,  0.875), vec2( 0.875, -0.875)
);

vec2 taaJitter() {
    return taaOffsets[frameCounter & 7] / vec2(viewWidth, viewHeight);
}

//--------------------------------------------------------------------------------------------------
// Material classes (stored in colortex2.r)
//--------------------------------------------------------------------------------------------------
#define MAT_NONE     0.0
#define MAT_GENERIC  1.0
#define MAT_FOLIAGE  2.0
#define MAT_NOFOG    3.0
#define MAT_HAND     4.0
#define MAT_METAL    5.0
#define MAT_EMISSIVE 6.0

#endif
