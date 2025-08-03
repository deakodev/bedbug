struct MeshVertex {
    float3 position;
    float uv_x;
    float3 normal;
    float uv_y;
    float4 color;
};

[[vk::binding(0), vk::set(0)]]
StructuredBuffer<MeshVertex> vertex_buffer;

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
    float3 color : COLOR0;
    [vk_location(1)]
    float2 uv : TEXCOORD0;
};

[shader("vertex")]
VSOutput main(uint vertex_index: SV_VertexID)
{
    MeshVertex v = vertex_buffer[vertex_index];

    VSOutput output;
    output.pos = mul(push_constants.render_matrix, float4(v.position, 1.0));
    output.color = v.color.xyz;
    output.uv.x = v.uv_x;
    output.uv.y = v.uv_y;

    return output;
}
