/*
    Yukitus Shader - screen space reflections
    requires: common.glsl
    needs:    depthtex0 and colortex0 declared by the including program
*/
#ifndef REFLECTIONS_GLSL
#define REFLECTIONS_GLSL

#if SSR_QUALITY == 0
    #define SSR_STEPS 12
    #define SSR_REFINE 3
#elif SSR_QUALITY == 1
    #define SSR_STEPS 20
    #define SSR_REFINE 4
#else
    #define SSR_STEPS 36
    #define SSR_REFINE 6
#endif

/*
    Returns vec4(color, hit alpha). Alpha is 0 when nothing was hit.
*/
vec4 screenSpaceReflection(vec3 viewPos, vec3 reflDir, float noise) {
    // keep the ray in front of the near plane
    float rayLen = far * 1.5;
    if (reflDir.z > 0.0) rayLen = min(rayLen, (-near * 1.01 - viewPos.z) / reflDir.z);
    vec3 startV = viewPos + reflDir * 0.02 * length(viewPos);
    vec3 endV = viewPos + reflDir * rayLen;

    vec3 start = viewToScreen(startV);
    vec3 end = viewToScreen(endV);
    vec3 delta = end - start;

    // clip to screen
    float tMax = 1.0;
    if (delta.x > 0.0) tMax = min(tMax, (1.0 - start.x) / delta.x);
    if (delta.x < 0.0) tMax = min(tMax, -start.x / delta.x);
    if (delta.y > 0.0) tMax = min(tMax, (1.0 - start.y) / delta.y);
    if (delta.y < 0.0) tMax = min(tMax, -start.y / delta.y);
    delta *= max(tMax, 0.0);

    float stepSize = 1.0 / float(SSR_STEPS);
    float t = stepSize * noise;
    float prevT = 0.0;
    vec3 hitPos = vec3(-1.0);

    for (int i = 0; i < SSR_STEPS; i++) {
        // slightly nonlinear stepping: finer near the start
        float tt = t * t * 0.4 + t * 0.6;
        vec3 p = start + delta * tt;
        if (p.z >= 1.0) break;
        float d = texture(depthtex0, p.xy).r;
        if (d > 0.56 && p.z > d) {
            // binary refinement
            float lo = prevT, hi = t;
            for (int j = 0; j < SSR_REFINE; j++) {
                float mid = (lo + hi) * 0.5;
                float mt = mid * mid * 0.4 + mid * 0.6;
                vec3 mp = start + delta * mt;
                float md = texture(depthtex0, mp.xy).r;
                if (mp.z > md) hi = mid; else lo = mid;
            }
            float ft = hi * hi * 0.4 + hi * 0.6;
            vec3 fp = start + delta * ft;
            float fd = texture(depthtex0, fp.xy).r;
            float linRay = linearizeDepth(fp.z);
            float linScene = linearizeDepth(fd);
            float thickness = max(0.5, linScene * 0.08) + length(delta.xy) * 2.0;
            if (abs(linRay - linScene) < thickness && fd < 1.0) {
                hitPos = fp;
            }
            break;
        }
        prevT = t;
        t += stepSize;
    }

    if (hitPos.x < 0.0) return vec4(0.0);
    vec2 edge = smoothstep(0.0, 0.08, hitPos.xy) * smoothstep(1.0, 0.92, hitPos.xy);
    float fade = edge.x * edge.y;
    return vec4(texture(colortex0, hitPos.xy).rgb, fade);
}

#endif
