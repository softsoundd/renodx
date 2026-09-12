// Sun glare sprite material (rotated double sample)
#include "./common.hlsl"

sampler2D Texture2D_0 : register(s0);
float4 UniformVector_0 : register(c0);

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

    const float4 c1 = float4(0.100000001, 1.0, 1000.0, -0.5);
    const float4 c2 = float4(0.992197692, -0.12467473, 0.0, 0.12467473);

    float4 r0, r1, r2;

    r0.xy = c1.w + i.v0.xy;
    r0.z = dot(c2.xy, r0.xy) + c2.z;
    r0.w = dot(float2(c2.w, c2.x), r0.xy) + c2.z;
    r0.xy = r0.zw + (-c1.w);
    r0 = tex2D(Texture2D_0, r0.xy);
    r1 = tex2D(Texture2D_0, i.v0.xy);
    r0.xyz = r0.xyz * r1.xyz;
    r0.w = max(i.v2.y, c1.x);
    r1.x = min(r0.w, c1.z);
    r0.w = saturate(-r1.x + c1.y);
    r1.xyz = r0.w * i.v1.xyz;
    r0.xyz = r0.xyz * r1.xyz;
    r1.xy = max(float2(i.v3.y, i.v3.x), c1.xy);
    r2.xy = min(r1.xy, c1.z);
    r0.xyz = r0.xyz * r2.y;
    r0.xyz = r2.x * r0.xyz + UniformVector_0.xyz;

    o.oC0.xyz = r0.xyz * i.v4.w;
    o.oC0.xyz = SunPass(o.oC0.xyz, i.v0.xy, i.v4.w);
    o.oC0.w = c2.z;

    return o;
}

/*
    ps_3_0
      def c1, 0.100000001, 1, 1000, -0.5
      def c2, 0.992197692, -0.12467473, 0, 0.12467473
      dcl_texcoord v0.xy
      dcl_texcoord1 v1.xyz
      dcl_texcoord2 v2.y
      dcl_texcoord3 v3.xy
      dcl_texcoord4_pp v4.w
      dcl_2d s0
      add r0.xy, c1.w, v0
      dp2add r0.z, c2, r0, c2.z
      dp2add r0.w, c2.wxzw, r0, c2.z
      add r0.xy, r0.zwzw, -c1.w
      texld r0, r0, s0
      texld r1, v0, s0
      mul r0.xyz, r0, r1
      max r0.w, v2.y, c1.x
      min r1.x, r0.w, c1.z
      add_sat r0.w, -r1.x, c1.y
      mul r1.xyz, r0.w, v1
      mul r0.xyz, r0, r1
      max r1.xy, v3.yxzw, c1
      min r2.xy, r1, c1.z
      mul r0.xyz, r0, r2.y
      mad_pp r0.xyz, r2.x, r0, c0
      mul_pp oC0.xyz, r0, v4.w
      mov_pp oC0.w, c2.z
*/
