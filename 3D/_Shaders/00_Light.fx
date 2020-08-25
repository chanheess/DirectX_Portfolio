struct LightDesc
{
    float4 Ambient;
    float4 Specular;
    float3 Direction;
    float Padding;
    float3 Position;
};

cbuffer CB_Light
{
    LightDesc GlobalLight;
};

struct MaterialDesc
{
    float4 Ambient;
    float4 Diffuse;
    float4 Specular;
    float4 Emissive;
};

cbuffer CB_Material
{
    MaterialDesc Material;
};

float3 MaterialToColor(MaterialDesc result)
{
    return (result.Ambient + result.Diffuse + result.Specular + result.Emissive).rgb;
}

MaterialDesc MakeMaterial()
{
    MaterialDesc output;
    output.Ambient = float4(0, 0, 0, 0);
    output.Diffuse = float4(0, 0, 0, 0);
    output.Specular = float4(0, 0, 0, 0);
    output.Emissive = float4(0, 0, 0, 0);

    return output;
}

void AddMaterial(inout MaterialDesc result, MaterialDesc val)
{
    result.Ambient += val.Ambient;
    result.Diffuse += val.Diffuse;
    result.Specular += val.Specular;
    result.Emissive += val.Emissive;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

void Texture(inout float4 color, Texture2D t, float2 uv, SamplerState samp)
{
    float4 sampling = t.Sample(samp, uv);
    
    //if (any(sampling.rgb))
    color = color * sampling;
}

void Texture(inout float4 color, Texture2D t, float2 uv)
{
    Texture(color, t, uv, LinearSampler);
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

void ComputeLight(out MaterialDesc output, float3 normal, float3 wPosition)
{
    output = MakeMaterial();

    
    float3 direction = -GlobalLight.Direction;
    float NdotL = dot(direction, normalize(normal));
    
    output.Ambient = GlobalLight.Ambient * Material.Ambient;
    float3 E = normalize(ViewPosition() - wPosition);
    
    [flatten]
    if(NdotL > 0.0f)
    {
        output.Diffuse = Material.Diffuse * NdotL;
        
        [flatten]
        if (any(Material.Specular.rgb))
        {
            float3 R = normalize(reflect(-direction, normal)); //reflect �ݻ縸�����
            float RdotE = saturate(dot(R, E));
            
            float specular = pow(RdotE, Material.Specular.a);   //���ǰ��� specular.a
            output.Specular = Material.Specular * specular * GlobalLight.Specular; //GlobalLight.Specular �¾��
        }
    }
    
    [flatten]
    if(any(Material.Emissive.rgb))
    {
        float NdotE = dot(E, normalize(normal));
        float emissive = smoothstep(1.0f - Material.Emissive.a, 1.0f, 1.0f - saturate(NdotE));
        
        output.Emissive = Material.Emissive * emissive;
    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////////

void NormalMapping(float2 uv, float3 normal, float3 tangent, SamplerState samp)
{
    float4 map = NormalMap.Sample(samp, uv);
    
    [flatten]
    if(any(map.rgb) == false)
        return;
    
    
    //tangent space
    float3 N = normalize(normal); //Z
    //float3 T = normalize(tangent); //X
    float3 T = normalize(tangent - dot(tangent, N) * N); //X
    float3 B = cross(N, T); //tangent
    float3x3 TBN = float3x3(T, B , N);
    
    //�̹��� �ȼ��κ��� ��ֺ��� ����
    float3 coord = map.rgb * 2.0f - 1.0f; // -1~1���� ������ �����
    
    //ź��Ʈ �������� ��ȯ
    coord = mul(coord, TBN);
    
    Material.Diffuse *= saturate(dot(coord, -GlobalLight.Direction));
}

void NormalMapping(float2 uv, float3 normal, float3 tangent)
{
    NormalMapping(uv, normal, tangent, LinearSampler);
}

///////////////////////////////////////////////////////////////////////////////////

struct PointLightDesc   //������ ���� ��
{
    float4 Ambient;
    float4 Diffuse;     //�ڱ��(����Ʈ) 
    float4 Specular;    //����Ʈ�� �ݻ��
    float4 Emissive;    //�ܰ����� ��������

    float3 Position;    //��ġ
    float Range;        

    float Intensity;    //����
    float3 Padding;
};

#define MAX_POINT_LIGHT 256
cbuffer CB_PointLights
{
    uint PointLightCount;
    float3 CB_PointLights_Padding;
    
    PointLightDesc PointLights[MAX_POINT_LIGHT];
};

void ComputePointLight(inout MaterialDesc output, float3 normal, float3 wPosition)
{
    output = MakeMaterial();
    MaterialDesc result = MakeMaterial();
    
    //[nuroll(MAX_POINT_LIGHT)]
    for (uint i = 0; i < PointLightCount;i++)
    {
        float3 light = PointLights[i].Position - wPosition;
        float dist = length(light);
        
        [flatten]
        if(dist > PointLights[i].Range)
            continue;
        
        
        light /= dist;  //normalize
        
        result.Ambient = Material.Ambient * PointLights[i].Ambient;
        
        float NdotL = dot(light, normalize(normal));  //���� �ݴ���
        float3 E = normalize(ViewPosition() - wPosition);
    
        [flatten]
        if (NdotL > 0.0f)
        {
        
            float3 R = normalize(reflect(-light, normal)); //reflect �ݻ縸�����
            float RdotE = saturate(dot(R, E));
            float specular = pow(RdotE, Material.Specular.a); //���ǰ��� specular.a
            
            result.Diffuse = Material.Diffuse * NdotL * PointLights[i].Diffuse;
            result.Specular = Material.Specular * specular * PointLights[i].Specular; //GlobalLight.Specular �¾��
        }
        
        float NdotE = dot(E, normalize(normal));
        float emissive = smoothstep(1.0f - Material.Emissive.a, 1.0f, 1.0f - saturate(NdotE));  //������ �ܰ�����
        
        result.Emissive = Material.Emissive * emissive * PointLights[i].Emissive;
        
        
        float temp = 1.0f / saturate(dist / PointLights[i].Range);
        float att = temp * temp * (1.0f / max(1.0f - PointLights[i].Intensity, 1e-8f)); 
        
        output.Ambient += result.Ambient * temp;
        output.Diffuse += result.Diffuse * att;
        output.Specular += result.Specular * att;
        output.Emissive += result.Emissive * att;
    }
}

///////////////////////////////////////////////////////////////////////////////////

struct SpotLightDesc   //������ ���� ��
{
    float4 Ambient;
    float4 Diffuse; //�ڱ��(����Ʈ) 
    float4 Specular; //����Ʈ�� �ݻ��
    float4 Emissive; //�ܰ����� ��������

    float3 Position; //��ġ
    float Range;    //���ΰŸ�
    
    float3 Direction;   //����
    float Angle;    //���� ������ ����

    float Intensity; //����
    float3 Padding;
};

#define MAX_SPOT_LIGHT 256
cbuffer CB_SpotLights
{
    uint SpotLightCount;
    float3 CB_SpotLights_Padding;
    
    SpotLightDesc SpotLights[MAX_SPOT_LIGHT];
};

void ComputeSpotLight(inout MaterialDesc output, float3 normal, float3 wPosition)
{
    output = MakeMaterial();
    MaterialDesc result = MakeMaterial();
    
    //[nuroll(MAX_Spot_LIGHT)]
    for (uint i = 0; i < SpotLightCount; i++)
    {
        float3 light = SpotLights[i].Position - wPosition;
        float dist = length(light);
        
        [flatten]
        if (dist > SpotLights[i].Range)
            continue;
        
        
        light /= dist; //normalize
        
        result.Ambient = Material.Ambient * SpotLights[i].Ambient;
        
        float NdotL = dot(light, normalize(normal)); //���� �ݴ���
        float3 E = normalize(ViewPosition() - wPosition);
    
        [flatten]
        if (NdotL > 0.0f)
        {
        
            float3 R = normalize(reflect(-light, normal)); //reflect �ݻ縸�����
            float RdotE = saturate(dot(R, E));
            float specular = pow(RdotE, Material.Specular.a); //���ǰ��� specular.a
            
            result.Diffuse = Material.Diffuse * NdotL * SpotLights[i].Diffuse;
            result.Specular = Material.Specular * specular * SpotLights[i].Specular; //GlobalLight.Specular �¾��
        }
        
        float NdotE = dot(E, normalize(normal));
        float emissive = smoothstep(1.0f - Material.Emissive.a, 1.0f, 1.0f - saturate(NdotE)); //������ �ܰ�����
        
        result.Emissive = Material.Emissive * emissive * SpotLights[i].Emissive;
        
        
        float temp = pow(saturate(dot(-light, SpotLights[i].Direction)), SpotLights[i].Angle);
        float att = temp * (1.0f / max(1.0f - SpotLights[i].Intensity, 1e-8f));
        
        output.Ambient += result.Ambient * temp;
        output.Diffuse += result.Diffuse * att;
        output.Specular += result.Specular * att;
        output.Emissive += result.Emissive * att;
    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////

float4 PS_AllLight(MeshOutput input)
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
    
    float4 color = float4(MaterialToColor(result), 1.0f);
    //color =  CalculateFogColor(color, input.wPosition);
    
    return float4(color.rgb, 1.0f);
}

//////////////////////////////////////////////////////////////////////////////////////////////////

Texture2D ProjectorMap;

struct ProjectorDesc
{
    matrix View;
    matrix Projection;
    
    float4 Color;
};

cbuffer CB_Projector
{
    ProjectorDesc Projector;
};

void VS_Projector(inout float4 wvp, float4 position)
{
    wvp = WorldPosition(position);
    
    wvp = mul(wvp, Projector.View);
    wvp = mul(wvp, Projector.Projection);
}

void PS_Projector(inout float4 color, float4 wvp)
{
    float3 uvw = 0;
    
    uvw.x = wvp.x / wvp.w * 0.5f + 0.5f;  //ndc��ȯ�� 0~1������ ����
    uvw.y = -wvp.y / wvp.w * 0.5f + 0.5f;   //������ߵ�
    uvw.z = wvp.z / wvp.w;

    [flatten]
    if (saturate(uvw.x) == uvw.x && saturate(uvw.y) == uvw.y && saturate(uvw.z) == uvw.z)   //ndc �������� ������
    {
        float4 map = ProjectorMap.Sample(LinearSampler, uvw.xy);
        map.rgb *= Projector.Color.rgb;
        color = lerp(color, map, map.a);
    }

}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

cbuffer CB_Shadow
{
    matrix ShadowView;  //light���������� view
    matrix ShadowProjection; //light���������� projection
    
    float2 ShadowMapSize;   //�׸��� �ؽ����� ũ��
    float ShadowBias;
    
    uint ShadowQuality;
};

float4 PS_Shadow(float4 position, float4 color) //sposition, psAllLight �Ƹ���
{
    position.xyz /= position.w; //ndc
    
    [flatten]   //ndc ���� ������� �׸��ڰ� ���� ����
    if (position.x < -1.0f || position.x > +1.0f ||
        position.y < -1.0f || position.y > +1.0f ||
        position.z < +0.0f || position.z > +1.0f)
    {
        return color; //�׷��� �׳� color�� ����
    }
    
    position.x = position.x * 0.5f + 0.5f;
    position.y = -position.y * 0.5f + 0.5f;
    position.z -= ShadowBias; // ���� ���� �ذ� / z���� ������ ������ �־� ������ �������� �߻���Ų��
    
    float depth = 0.0f;
    float factor = 0.0f;
    
    if (ShadowQuality == 0)
    {
        depth = ShadowMap.Sample(LinearSampler, position.xy).r;
        factor = (float) position.z <= depth;
    }
    else if (ShadowQuality == 1)
    {
        depth = position.z;
        //�ؽ��İ��� �츮�� ���� ����
        factor = ShadowMap.SampleCmpLevelZero(ShadowSampler, position.xy, depth).r; //factor = (float) position.z <= depth;�� ������ ���⼭�Ѵ�

    }
    else if (ShadowQuality == 2)
    {
        depth = position.z;
        
        float2 size = 1.0f / ShadowMapSize; //ShadowTextureMap�� ������ �� �ȼ��� ����
        float2 offsets[] =  //�� �ȼ��� �ֺ� �ȼ���
        {
            float2(-size.x, -size.y), float2(0.0f, -size.y), float2(+size.x, -size.y),
            float2(-size.x, 0.0f), float2(0.0f, 0.0f), float2(+size.x, 0.0f),
            float2(-size.x, +size.y), float2(0.0f, +size.y), float2(+size.x, +size.y),
        };
        
        float2 uv = 0;
        float sum = 0;
        
        [unroll(9)]
        for (int i = 0; i < 9; i++)
        {
            uv = position.xy + offsets[i];
            sum += ShadowMap.SampleCmpLevelZero(ShadowSampler, uv, depth).r;
        }
        
        factor = sum / 9.0f;    //��հ�
    }
    
    
    //factor = saturate(factor + depth);
    
    //return float4(1, 1, 1, 1) * factor;
    factor = saturate(factor + depth);
    return float4(color.rgb * factor, 1);
}