/*
    Yukitus Shader - bloom tile layout inside colortex7
    Tile k (k = 0..5) holds the image at 1/2^(k+2) resolution.
*/
#ifndef BLOOM_TILES_GLSL
#define BLOOM_TILES_GLSL

#define BLOOM_TILE_COUNT 6
const float bloomPad = 0.012;

float bloomTileScale(int k) { return exp2(-float(k + 2)); }

vec2 bloomTileOffset(int k) {
    // tiles 0..5 placed left to right, with padding
    float x = 0.0;
    for (int i = 0; i < k; i++) x += bloomTileScale(i) + bloomPad;
    return vec2(x + bloomPad * 0.5, bloomPad * 0.5);
}

#endif
