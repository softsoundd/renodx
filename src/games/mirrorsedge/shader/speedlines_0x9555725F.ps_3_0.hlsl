// Screen edge speed lines post-process material, with a strength control on the line textures.
#include "../shared.h"

sampler2D SceneColorTexture : register(s0);
float4 ScreenPositionScaleBias : register(c1);
sampler2D Texture2D_0 : register(s1);
sampler2D Texture2D_1 : register(s2);
sampler2D Texture2D_2 : register(s3);
float4 UniformVector_0 : register(c0);
float4 UniformVector_1 : register(c2);
float4 UniformVector_2 : register(c3);
float4 UniformVector_3 : register(c4);

struct PS_IN {
  float2 texcoord : TEXCOORD;
  float4 texcoord4 : TEXCOORD4;
  float4 texcoord5 : TEXCOORD5;
};

float4 main(PS_IN i) : COLOR {
  float4 o;

  float4 r0;
  float4 r1;
  float4 r2;

  if (C_SPEEDLINES <= 0) discard;

  r0.x = 1 / i.texcoord5.w;
  r0.xy = r0.x * i.texcoord5.xy;
  r0.xy = r0.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
  r0 = tex2D(SceneColorTexture, r0);
  r0.w = dot(r0.xyz, float3(0.3, 0.59, 0.11));
  r1.x = max(abs(r0.w), 0.0001);
  r0.w = 1 / sqrt(r1.x);
  r0.w = 1 / r0.w;
  r1.xyz = r0.xyz * r0.w;
  r0.w = r0.w + 0.5;
  r1.xyz = r1.xyz * 1.38;
  r1.xyz = r0.xyz * 0.12 + r1.xyz;
  r0.xyz = r1.xyz * 1.5 + r0.xyz;
  r1.xyz = max(r0.xyz, 0.03);
  r0.xyz = min(r1.xyz, 3);
  r0.xyz = r0.xyz + UniformVector_0.xyz;
  r0.xyz = r0.xyz * i.texcoord4.w;
  r1 = float4(-1, 0.1, 2, 0.05);
  r1.xy = i.texcoord.xy * r1.xy + UniformVector_1.xy;
  r2 = tex2D(Texture2D_1, r1);
  r1.xy = i.texcoord.xy * r1.zw + UniformVector_2.xy;
  r1 = tex2D(Texture2D_1, r1);

  r1.x = r2.y + r1.y;
  r1.yz = 1 * i.texcoord.x;
  r1.yz = r1.x * 0.3 + r1.xy;
  r2 = tex2D(Texture2D_2, r1.yz);
  r2.xyz *= C_SPEEDLINES;

  r1.y = r2.x * UniformVector_3.w;
  r2 = tex2D(Texture2D_0, i.texcoord);
  r2.xyz *= C_SPEEDLINES;

  r1.z = r2.y * 5;
  r1.x = r1.x * r1.z;
  r1.x = r1.y * r1.x;
  r1.x = saturate(r1.x * 5);
  r0.w = r0.w * r1.x;
  o.xyz = r0.xyz * r0.w;
  o.w = 0;

  return o;
}

/*
    ps_3_0
      0x000001C4 : def c5, 0.300000012, 0.589999974, 0.109999999, 9.99999975e-005
      0x000001DC : def c6, 1.38, 0.119999997, 1.5, 0.0299999993
      0x000001F4 : def c7, 3, 0.5, 5, 0
      0x0000020C : def c8, 1, 0.800000012, 0, 0
      0x00000224 : def c9, -1, 0.100000001, 2, 0.0500000007
      0x0000023C : dcl_texcoord v0.xy
      0x00000248 : dcl_texcoord4_pp v1.w
      0x00000254 : dcl_texcoord5 v2.xyw
      0x00000260 : dcl_2d s0
      0x0000026C : dcl_2d s1
      0x00000278 : dcl_2d s2
      0x00000284 : dcl_2d s3
   0  0x00000290 : rcp r0.x, v2.w
   1  0x0000029C : mul r0.xy, r0.x, v2
   2  0x000002AC : mad r0.xy, r0, c1, c1.wzzw
   3  0x000002C0 : texld r0, r0, s0
   3  0x000002D0 : dp3 r0.w, r0, c5
   4  0x000002E0 : max r1.x, r0_abs.w, c5.w
   5  0x000002F0 : rsq r0.w, r1.x
   6  0x000002FC : rcp r0.w, r0.w
   7  0x00000308 : mul r1.xyz, r0, r0.w
   8  0x00000318 : add r0.w, r0.w, c7.y
   9  0x00000328 : mul r1.xyz, r1, c6.x
  10  0x00000338 : mad r1.xyz, r0, c6.y, r1
  11  0x0000034C : mad r0.xyz, r1, c6.z, r0
  12  0x00000360 : max r1.xyz, r0, c6.w
  13  0x00000370 : min r0.xyz, r1, c7.x
  14  0x00000380 : add_pp r0.xyz, r0, c0
  15  0x00000390 : mul_pp r0.xyz, r0, v1.w
  16  0x000003A0 : mov r1, c9
  17  0x000003AC : mad r1.xy, v0, r1, c2
  18  0x000003C0 : texld r2, r1, s2
  18  0x000003D0 : mad r1.xy, v0, r1.zwzw, c3
  19  0x000003E4 : texld r1, r1, s2
  19  0x000003F4 : add r1.x, r2.y, r1.y
  20  0x00000404 : mul r1.yz, c8.xxyw, v0.xxyw
  21  0x00000414 : mad r1.yz, r1.x, c5.x, r1
  22  0x00000428 : texld r2, r1.yzzw, s3
  22  0x00000438 : mul r1.y, r2.x, c4.w
  23  0x00000448 : texld r2, v0, s1
  23  0x00000458 : mul r1.z, r2.y, c7.z
  24  0x00000468 : mul r1.x, r1.x, r1.z
  25  0x00000478 : mul r1.x, r1.y, r1.x
  26  0x00000488 : mul_sat r1.x, r1.x, c7.z
  27  0x00000498 : mul_pp r0.w, r0.w, r1.x
  28  0x000004A8 : mul_pp oC0.xyz, r0, r0.w
  29  0x000004B8 : mov_pp oC0.w, c7.w

// approximately 35 instruction slots used (5 texture, 30 arithmetic)
*/
