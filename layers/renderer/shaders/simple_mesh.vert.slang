#include "simple_mesh_inc.slang"

struct PushConstants
{
    float4x4 render_matrix;
};

[vk_push_constant]
PushConstants push_constants;

struct VSOutput
{
    float4 pos : SV_Position;
    [vk_location(0)]
    float3 outNormal : NORMAL;
    [vk_location(1)]
    float3 outColor : COLOR;
    [vk_location(2)]
    float2 outUV : TEXCOORD0;
};

[shader("vertex")]
VSOutput main(uint vertex_index: SV_VertexID)
{
    MeshVertex v = vertex_buffer[vertex_index];

    float4 position = float4(v.position, 1.0);
    VSOutput output;
    output.pos = mul(scene_data.view_proj, mul(push_constants.render_matrix, position));

    output.outNormal = (mul(push_constants.render_matrix, float4(v.normal, 0.0))).xyz;
    output.outColor = v.color.xyz * material_data.color_factors.xyz;
    // output.outColor = abs(v.normal);
    output.outUV.x = v.uv_x;
    output.outUV.y = v.uv_y;

    return output;
}
