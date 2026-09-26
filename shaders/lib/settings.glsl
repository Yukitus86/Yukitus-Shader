/*
    Yukitus Shader - Settings
    All user facing options live here. Values in [brackets] show up in the in-game menu.
*/
#ifndef SETTINGS_GLSL
#define SETTINGS_GLSL

//==================================================================================================
// Shadows
//==================================================================================================
#define SHADOWS
const int shadowMapResolution = 2048; // [512 1024 1536 2048 3072 4096 6144 8192]
const float shadowDistance = 128.0; // [48.0 64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0]
const float shadowDistanceRenderMul = 1.0; // [-1.0 1.0]
const float sunPathRotation = -25.0; // [-60.0 -50.0 -45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0 50.0 60.0]
const bool shadowHardwareFiltering = true;
const float shadowIntervalSize = 2.0;
#define SHADOW_FILTER 2 // [0 1 2 3]
#define SHADOW_SOFTNESS 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0]
#define COLORED_SHADOWS
#define ENTITY_SHADOWS
#define SHADOW_DISTORT 0.85

//==================================================================================================
// Lighting
//==================================================================================================
#define SUN_INTENSITY 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.75 2.0]
#define AMBIENT_INTENSITY 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.75 2.0]
#define BLOCKLIGHT_INTENSITY 1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.75 2.0 2.5 3.0]
#define BLOCKLIGHT_TEMP 1 // [0 1 2]
#define NIGHT_BRIGHTNESS 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define MIN_LIGHT 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]
#define SSAO
#define SSAO_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define VANILLA_AO 0.8 // [0.0 0.2 0.4 0.6 0.8 1.0]
#define HANDHELD_LIGHT
#define SUBSURFACE_SCATTERING
#define CLOUD_SHADOWS
#define SPECULAR_HIGHLIGHTS

//==================================================================================================
// Materials
//==================================================================================================
#define PBR_MODE 0 // [0 1]
#define EMISSIVE_ORES
#define EMISSION_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define RAIN_PUDDLES
#define PUDDLE_AMOUNT 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
//#define GENERATED_NORMALS
#define NORMAL_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

//==================================================================================================
// Water
//==================================================================================================
#define WATER_STYLE 0 // [0 1 2]
#define WATER_WAVES
#define WAVE_HEIGHT 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WAVE_SPEED 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_REFRACTION
#define REFRACTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define WATER_FOG_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WATER_CAUSTICS
#define REFLECTIONS 2 // [0 1 2]
#define SSR_QUALITY 1 // [0 1 2]

//==================================================================================================
// Sky
//==================================================================================================
#define VOLUMETRIC_CLOUDS
#define CLOUD_QUALITY 1 // [0 1 2]
#define CLOUD_HEIGHT 192.0 // [128.0 144.0 160.0 176.0 192.0 208.0 224.0 256.0 288.0 320.0]
#define CLOUD_THICKNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define CLOUD_COVERAGE 1.0 // [0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]
#define CLOUD_SPEED 1.0 // [0.0 0.25 0.5 1.0 1.5 2.0 3.0 5.0]
#define STARS
#define STAR_AMOUNT 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define AURORA 1 // [0 1 2]
#define RAINBOWS
#define SUN_SIZE 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define MOON_SIZE 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0 3.0]

//==================================================================================================
// Atmosphere
//==================================================================================================
#define VOLUMETRIC_LIGHT
#define VL_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define VL_QUALITY 1 // [0 1 2]
#define FOG_DENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define MORNING_FOG
#define BORDER_FOG
#define NETHER_FOG 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define END_FOG 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define WAVING_PLANTS
#define WAVING_LEAVES
#define WAVING_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WAVING_SPEED 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]

//==================================================================================================
// Post processing
//==================================================================================================
#define TAA
#define SHARPENING 0.5 // [0.0 0.25 0.5 0.75 1.0]
#define BLOOM
#define BLOOM_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define AUTO_EXPOSURE
#define EXPOSURE 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define TONEMAP 0 // [0 1 2]
#define SATURATION 1.0 // [0.0 0.25 0.5 0.75 0.9 1.0 1.1 1.2 1.3 1.5 1.75 2.0]
#define VIBRANCE 1.1 // [0.0 0.5 0.75 0.9 1.0 1.1 1.2 1.3 1.5 1.75 2.0]
#define CONTRAST 1.0 // [0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.3]
#define VIGNETTE 0.35 // [0.0 0.1 0.2 0.3 0.35 0.4 0.5 0.6 0.8 1.0]
//#define DEPTH_OF_FIELD
#define DOF_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
//#define MOTION_BLUR
#define MOTION_BLUR_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define UNDERWATER_DISTORTION

//==================================================================================================
// Engine constants (not options)
//==================================================================================================
const int noiseTextureResolution = 256;
const float ambientOcclusionLevel = 1.0;
const float eyeBrightnessHalflife = 4.0;
const float wetnessHalflife = 300.0;
const float drynessHalflife = 70.0;
const float centerDepthHalflife = 2.0;

#endif
