struct MeshVertex {
    float3 position;
    float uv_x;
    float3 normal;
    float uv_y;
    float4 color;
};

struct SceneData
{
    float4x4 view;
    float4x4 proj;
    float4x4 view_proj;
    float4 ambient_color;
    float4 sunlight_direction; // w for sun power
    float4 sunlight_color;
};

struct GLTFMaterialData
{
    float4 color_factors;
    float4 metal_rough_factors;
};

[[vk::binding(0, 0)]]
StructuredBuffer<MeshVertex> vertex_buffer;

[[vk::binding(0, 1)]]
ParameterBlock<SceneData> scene_data;

[[vk::binding(0, 2)]]
ParameterBlock<GLTFMaterialData> material_data;

[[vk::binding(1, 2)]]
Sampler2D color_tex;
[[vk::binding(2, 2)]]
Sampler2D metal_rough_tex;