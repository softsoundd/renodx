// Sun glare sprite material
#include "./common.hlsl"

sampler2D Texture2D_0 : register(s0);
float4 UniformVector_0          : register(c0);
float4 ScreenPositionScaleBias  : register(c1);

struct PS_INPUT
{
    float2 v0 : TEXCOORD0;
    float4 v1 : TEXCOORD4;  // only .w used
    float4 v2 : TEXCOORD5;  // .xyw used
};

struct PS_OUTPUT
{
    float4 oC0 : COLOR0;
};

PS_OUTPUT main(PS_INPUT i)
{
    PS_OUTPUT o;

    const float4 c2 = float4(0.5, 6.28318548, -3.14159274, 0.599999964);
    const float4 c3 = float4(1.5, 1.25, 1.0, 0.0);

    float4 r0, r1, r2;

    r0.x = 1.0 / i.v2.w;
    r0.xy = r0.x * i.v2.xy;
    r0.xy = r0.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
    r0.xy = r0.xy * c2.x + c2.x;
    r0.xy = frac(r0.xy);
    r0.xy = r0.xy * c2.y + c2.z;
    sincos(r0.x, r1.y, r0.z);
    sincos(r0.y, r2.y, r0.z);
    r0.x = r1.y + r2.y;
    r0.x = r0.x * c2.x + c2.w;
    r0.y = r0.x * c2.x + c2.x;
    r0.xy = r0.x * (-i.v0.xy) + r0.y;
    r0 = tex2D(Texture2D_0, r0.xy);
    r0.xyz = r0.xyz * r0.xyz;
    r1.xyz = c3.xyz;
    r0.xyz = r0.xyz * r1.xyz + UniformVector_0.xyz;

    o.oC0.xyz = r0.xyz * i.v1.w;
    o.oC0.xyz = SunPass(o.oC0.xyz, i.v0.xy, i.v1.w);
    o.oC0.w = c3.w;

    return o;
}

/*
    ps_3_0
      def c2, 0.5, 6.28318548, -3.14159274, 0.599999964
      def c3, 1.5, 1.25, 1, 0
      dcl_texcoord v0.xy
      dcl_texcoord4_pp v1.w
      dcl_texcoord5 v2.xyw
      dcl_2d s0
      rcp r0.x, v2.w
      mul r0.xy, r0.x, v2
      mad r0.xy, r0, c1, c1.wzzw
      mad r0.xy, r0, c2.x, c2.x
      frc r0.xy, r0
      mad r0.xy, r0, c2.y, c2.z
      sincos r1.y, r0.x
      sincos r2.y, r0.y
      add r0.x, r1.y, r2.y
      mad r0.x, r0.x, c2.x, c2.w
      mad r0.y, r0.x, c2.x, c2.x
      mad r0.xy, r0.x, -v0, r0.y
      texld r0, r0, s0
      mul r0.xyz, r0, r0
      mov r1.xyz, c3
      mad_pp r0.xyz, r0, r1, c0
      mul_pp oC0.xyz, r0, v1.w
      mov_pp oC0.w, c3.w
*/
