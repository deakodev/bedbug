struct PushConstants
{
    float4 data1; // skyTop.rgb,   horizonSoftness
    float4 data2; // skyHorizon.rgb, horizonHeight
    float4 data3; // ground.rgb,   vignetteStrength
    float4 data4; // unused
};

[[vk_push_constant]]
PushConstants push_constants;

RWTexture2D<float4> image;

static float hash21(float2 p)
{
    // tiny noise for debanding (no texture needed)
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 globalID : SV_DispatchThreadID)
{
    uint2 size;
    image.GetDimensions(size.x, size.y);

    uint2 pix = globalID.xy;
    if (pix.x >= size.x || pix.y >= size.y) return;

    // Normalize coordinates to [0,1], center at pixel centers
    float2 uv = (float2(pix) + 0.5) / float2(size);

    // Unpack constants
    float3 skyTop        = push_constants.data1.rgb;
    float  horizonSoft   = saturate(push_constants.data1.a);
    float3 skyHorizon    = push_constants.data2.rgb;
    float  horizonHeight = saturate(push_constants.data2.a);
    float3 groundColor   = push_constants.data3.rgb;
    float  vignetteStr   = saturate(push_constants.data3.a);

    // --- Sky gradient (top -> horizon) ---
    // Map vertical 0..1 with horizon at horizonHeight.
    float tSky = smoothstep(horizonHeight - horizonSoft, 1.0, uv.y);
    float3 skyCol = lerp(skyHorizon, skyTop, tSky);

    // --- Ground (below horizon) ---
    // Blend ground up into horizon with the same softness band.
    float tGround = 1.0 - smoothstep(horizonHeight - horizonSoft, horizonHeight + horizonSoft, uv.y);
    float3 baseCol = lerp(skyCol, groundColor, tGround);

    // --- Subtle horizon “glow” band (optional: adds depth) ---
    float band = 1.0 - abs((uv.y - horizonHeight) / max(1e-5, horizonSoft * 2.0));
    band = saturate(band);
    baseCol = lerp(baseCol, skyHorizon, 0.15 * band);

    // --- Vignette (subtle) ---
    float2 v = uv * (1.0 - uv);                // peaks at center, 0 at edges
    float vignette = pow(saturate(16.0 * v.x * v.y), 0.5); // soft curve
    baseCol *= lerp(1.0 - 0.35 * vignetteStr, 1.0, vignette);

    // --- Tiny noise to fight banding ---
    float n = (hash21(pix) - 0.5) * (1.0 / 255.0); // ~1 LSB in 8-bit
    baseCol += n;

    image[pix] = float4(baseCol, 1.0);
}
