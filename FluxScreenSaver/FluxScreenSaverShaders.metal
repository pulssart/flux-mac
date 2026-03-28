#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 resolution;
    float time;
    float transitionProgress;
    float glow;
    float currentScale;
    float nextScale;
    float2 currentOffset;
    float2 nextOffset;
    uint currentHasTexture;
    uint nextHasTexture;
};

vertex VertexOut fluxSaverVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    constexpr float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float2 coverUV(float2 uv, float2 textureSize, float2 screenSize, float scale, float2 offset) {
    float textureAspect = textureSize.x / max(textureSize.y, 1.0);
    float screenAspect = screenSize.x / max(screenSize.y, 1.0);
    float2 fitted = uv;

    if (textureAspect > screenAspect) {
        float scaledWidth = screenAspect / textureAspect;
        fitted.x = (uv.x - 0.5) * scaledWidth + 0.5;
    } else {
        float scaledHeight = textureAspect / screenAspect;
        fitted.y = (uv.y - 0.5) * scaledHeight + 0.5;
    }

    return (fitted - 0.5 - offset) / scale + 0.5;
}

float3 fallbackGradient(float2 uv, float time) {
    float3 top = float3(0.12, 0.14, 0.28);
    float3 middle = float3(0.14, 0.36, 0.60);
    float3 bottom = float3(0.07, 0.52, 0.48);
    float mixA = smoothstep(0.0, 0.72, uv.y);
    float mixB = smoothstep(0.12, 1.0, uv.x + sin(time * 0.08) * 0.08);
    float3 base = mix(bottom, middle, mixA);
    return mix(base, top, mixB * 0.55);
}

float2 barrelDistortion(float2 uv, float amount) {
    float2 p = uv * 2.0 - 1.0;
    float radius = dot(p, p);
    p *= 1.0 + amount * radius;
    return p * 0.5 + 0.5;
}

fragment float4 fluxSaverFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]],
    sampler textureSampler [[sampler(0)]],
    texture2d<float> currentTexture [[texture(0)]],
    texture2d<float> nextTexture [[texture(1)]]
) {
    float2 uv = in.uv;
    float2 center = uv - 0.5;
    float pulse = sin(uniforms.time * 0.45) * 0.5 + 0.5;
    float noise = hash21(uv * 280.0 + uniforms.time * 0.05);
    float distort = (noise - 0.5) * 0.05;
    float transition = smoothstep(0.0, 1.0, uniforms.transitionProgress);
    float flicker = 0.985 + hash21(float2(uniforms.time * 0.37, 0.17)) * 0.03;

    float2 crtUV = barrelDistortion(uv, 0.055);
    float2 warpedCurrentUV = crtUV + center * distort * (1.0 - transition) * 0.9;
    float2 warpedNextUV = crtUV - center * distort * transition * 1.1;

    float3 currentColor = fallbackGradient(crtUV, uniforms.time);
    float3 nextColor = fallbackGradient(crtUV + 0.11, uniforms.time + 1.7);

    if (uniforms.currentHasTexture == 1) {
        float2 currentCoverUV = coverUV(
            warpedCurrentUV,
            float2(currentTexture.get_width(), currentTexture.get_height()),
            uniforms.resolution,
            uniforms.currentScale,
            uniforms.currentOffset
        );
        float aberration = 0.0025 + length(center) * 0.003;
        float r = currentTexture.sample(textureSampler, currentCoverUV + float2(aberration, 0.0)).r;
        float g = currentTexture.sample(textureSampler, currentCoverUV).g;
        float b = currentTexture.sample(textureSampler, currentCoverUV - float2(aberration, 0.0)).b;
        currentColor = float3(r, g, b);
    }

    if (uniforms.nextHasTexture == 1) {
        float2 nextCoverUV = coverUV(
            warpedNextUV,
            float2(nextTexture.get_width(), nextTexture.get_height()),
            uniforms.resolution,
            uniforms.nextScale,
            uniforms.nextOffset
        );
        float aberration = 0.0025 + length(center) * 0.003;
        float r = nextTexture.sample(textureSampler, nextCoverUV + float2(aberration, 0.0)).r;
        float g = nextTexture.sample(textureSampler, nextCoverUV).g;
        float b = nextTexture.sample(textureSampler, nextCoverUV - float2(aberration, 0.0)).b;
        nextColor = float3(r, g, b);
    }

    float lumaA = dot(currentColor, float3(0.2126, 0.7152, 0.0722));
    float lumaB = dot(nextColor, float3(0.2126, 0.7152, 0.0722));
    float glowMask = smoothstep(0.18, 0.9, mix(lumaA, lumaB, transition));

    float3 blended = mix(currentColor, nextColor, transition);
    float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
    float vignette = smoothstep(1.4, 0.14, length(center * float2(aspect, 1.0)));
    float scan = 0.045 * sin((crtUV.y + uniforms.time * 0.05) * uniforms.resolution.y * 0.19);
    float grille = 0.018 * sin(crtUV.x * uniforms.resolution.x * 0.045);
    float3 grade = float3(1.05, 1.03, 1.0);
    bool hasImage = uniforms.currentHasTexture == 1 || uniforms.nextHasTexture == 1;

    blended += float3(0.18, 0.26, 0.34) * glowMask * pulse * 0.18;
    blended += scan + grille;
    blended *= grade;
    blended = mix(blended, blended * vignette, hasImage ? 0.28 : 0.82);
    blended = pow(max(blended, 0.0), float3(0.95));
    blended *= flicker;
    blended += (noise - 0.5) * 0.045;
    blended = saturate(blended * (hasImage ? 1.08 : 1.0));

    return float4(blended, 1.0);
}
