#include "00_Global.fx"
#include "00_Light.fx"
#include "00_Render.fx"

int Selected;
float4 PS(MeshOutput input) : SV_Target
{
    NormalMapping(input.Uv, input.Normal, input.Tangent);
   
    Texture(Material.Diffuse, DiffuseMap, input.Uv);
    Texture(Material.Specular, SpecularMap, input.Uv);
    
    MaterialDesc result = MakeMaterial();
    MaterialDesc output = MakeMaterial();
    
    
    ComputeLight(output, input.Normal, input.wPosition);
    AddMaterial(result, output);
    
    ComputePointLight(output, input.Normal, input.wPosition);
    AddMaterial(result, output);
    
    ComputeSpotLight(output, input.Normal, input.wPosition);
    AddMaterial(result, output);
    
    return float4(MaterialToColor(result), 1.0f);
}

technique11 T0
{
    P_VP(P0, VS_Mesh, PS)
    P_VP(P1, VS_Model, PS)
    P_VP(P2, VS_Animation, PS)
}