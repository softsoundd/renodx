#include "../shared.h"
sampler2D Texture2D_0 : register(s0);
float UniformScalar_0 : register(c2);
float UniformScalar_1 : register(c3);
float UniformScalar_2 : register(c4);
float UniformScalar_3 : register(c5);
float4 UniformVector_0 : register(c0);

struct PS_IN {
  float2 texcoord : TEXCOORD;
  float3 texcoord1 : TEXCOORD1;
  float2 texcoord2 : TEXCOORD2;
  float2 texcoord3 : TEXCOORD3;
  float4 texcoord4 : TEXCOORD4;
};

float4 main(PS_IN i) : COLOR {
  float4 o;

  float4 r0;
  float3 r1;

  // if (C_SUNLENS <= 0) discard;

  r0.w = 0.5;
  r0.x = i.texcoord.x * r0.w + UniformScalar_0.x;
  r0.x = (i.texcoord.x >= 0) ? r0.x : UniformScalar_0.x;
  r1.x = min(UniformScalar_1.x, r0.x);
  r0.x = 0.25;
  r0.x = i.texcoord.y * r0.x + UniformScalar_2.x;
  r0.x = (i.texcoord.y >= 0) ? r0.x : UniformScalar_2.x;
  r1.y = min(UniformScalar_3.x, r0.x);
  r0 = tex2D(Texture2D_0, r1);
  r0.w = 1 + -i.texcoord2.y;
  r1.x = max(0.1, r0.w);
  r0.w = min(r1.x, 1000);
  r1.xyz = r0.w * i.texcoord1.xyz;
  r0.xyz = r0.xyz * r1.xyz;
  r0.xyz = r0.xyz * i.texcoord3.x;
  r0.xyz = i.texcoord3.y * r0.xyz + UniformVector_0.xyz;
  o.xyz = r0.xyz * i.texcoord4.w;  // vanilla: mul_pp oC0.xyz, r0, v4.w (fade)
  if (TONE_MAP_TYPE > 0) o.xyz *= C_SUNLENS;
  o.w = 0;

  return o;
}

/*
    ps_3_0
      def c1, 1, 0.100000001, 1000, 0.5
      def c6, 0.25, 0, 0, 0
      dcl_texcoord v0.xy
      dcl_texcoord1 v1.xyz
      dcl_texcoord2 v2.y
      dcl_texcoord3 v3.xy
      dcl_texcoord4_pp v4.w
      dcl_2d s0
      mov r0.w, c1.w
      mad r0.x, v0.x, r0.w, c2.x
      cmp r0.x, v0.x, r0.x, c2.x
      min r1.x, c3.x, r0.x
      mov r0.x, c6.x
      mad r0.x, v0.y, r0.x, c4.x
      cmp r0.x, v0.y, r0.x, c4.x
      min r1.y, c5.x, r0.x
      texld r0, r1, s0
      add r0.w, c1.x, -v2.y
      max r1.x, c1.y, r0.w
      min r0.w, r1.x, c1.z
      mul r1.xyz, r0.w, v1
      mul r0.xyz, r0, r1
      mul r0.xyz, r0, v3.x
      mad_pp r0.xyz, v3.y, r0, c0
      mul_pp oC0.xyz, r0, v4.w
      mov_pp oC0.w, c6.y
*/
