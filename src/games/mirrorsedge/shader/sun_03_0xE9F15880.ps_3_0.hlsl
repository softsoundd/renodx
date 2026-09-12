// Sun glare sprite material (two projected samples)
#include "./common.hlsl"

sampler2D Texture2D_0 : register(s0);
float4 UniformVector_0 : register(c0);
float4 UniformVector_1 : register(c2);
float4 UniformVector_2 : register(c3);
float4 UniformVector_3 : register(c4);
float4 UniformVector_4 : register(c5);

struct PS_INPUT
{
    float2 v0 : TEXCOORD0;
    float3 v1 : TEXCOORD1;
    float2 v2 : TEXCOORD2;  // vanilla reads .y
    float2 v3 : TEXCOORD3;
    float4 v4 : TEXCOORD4;  // only .w used
};

struct PS_OUTPUT
{
    float4 oC0 : COLOR0;
};

PS_OUTPUT main(PS_INPUT i)
{
    PS_OUTPUT o;

    const float4 c1 = float4(-0.5, 0.0, 0.5, 0.100000001);
    const float4 c6 = float4(1000.0, 1.0, 0.0, 0.0);

    float4 r0, r1, r2;

    r0.xy = c1.x + i.v0.xy;
    r1.y = c1.y;
    r0.z = dot(UniformVector_1.xy, r0.xy) + r1.y;
    r0.w = dot(UniformVector_2.xy, r0.xy) + r1.y;
    r0.z = r0.z + c1.z;
    r0.w = r0.w + c1.z;
    r2 = tex2D(Texture2D_0, r0.zw);
    r0.z = dot(UniformVector_3.xy, r0.xy) + r1.y;
    r0.w = dot(UniformVector_4.xy, r0.xy) + r1.y;
    r0.xy = r0.zw + c1.z;
    r0 = tex2D(Texture2D_0, r0.xy);
    r0.x = r2.y * r0.y;
    r0.y = max(i.v2.y, c1.w);
    r1.x = min(r0.y, c6.x);
    r0.y = saturate(-r1.x + c6.y);
    r0.yzw = r0.y * i.v1.xyz;
    r0.xyz = r0.x * r0.yzw;
    r0.xyz = r0.xyz * i.v3.x;
    r0.xyz = i.v3.y * r0.xyz + UniformVector_0.xyz;

    o.oC0.xyz = r0.xyz * i.v4.w;
    o.oC0.w = c1.y;

    o.oC0.xyz = SunPass(o.oC0.xyz, i.v0.xy, i.v4.w);

    return o;
}

/*
    ps_3_0
      def c1, -0.5, 0, 0.5, 0.100000001
      def c6, 1000, 1, 0, 0
      dcl_texcoord v0.xy
      dcl_texcoord1 v1.xyz
      dcl_texcoord2 v2.y
      dcl_texcoord3 v3.xy
      dcl_texcoord4_pp v4.w
      dcl_2d s0
      add r0.xy, c1.x, v0
      mov r1.y, c1.y
      dp2add r0.z, c2, r0, r1.y
      dp2add r0.w, c3, r0, r1.y
      add r0.zw, r0, c1.z
      texld r2, r0.zwzw, s0
      dp2add r0.z, c4, r0, r1.y
      dp2add r0.w, c5, r0, r1.y
      add r0.xy, r0.zwzw, c1.z
      texld r0, r0, s0
      mul r0.x, r2.y, r0.y
      max r0.y, v2.y, c1.w
      min r1.x, r0.y, c6.x
      add_sat r0.y, -r1.x, c6.y
      mul r0.yzw, r0.y, v1.xxyz
      mul r0.xyz, r0.x, r0.yzww
      mul r0.xyz, r0, v3.x
      mad_pp r0.xyz, v3.y, r0, c0
      mul_pp oC0.xyz, r0, v4.w
      mov_pp oC0.w, c1.y
*/
