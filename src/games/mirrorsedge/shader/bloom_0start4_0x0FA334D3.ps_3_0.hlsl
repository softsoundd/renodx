// DOFAndBloomGatherPixelShader.usf, NUM_SAMPLES = 4 (QualityBloom=False)
#define BLOOM_GATHER_TEXCOORDS 2
#include "./bloom_gather.hlsl"

/*
    ps_3_0
      def c1, 60000, 1, 0, 0.25
      def c4, 9.99999975e-005, 0, 0, 0
      dcl_texcoord v0
      dcl_texcoord1 v1
      dcl_2d s0
      texld_pp r0, v0, s0
      add r1, -r0.wxyz, c1.xyyy
      mov_sat_pp r1.x, r1.x
      cmp r1.yzw, r1, c1.z, c1.y
      mul_pp r2.xyz, r0, r1.x
      dp3 r1.x, r1.yzww, r1.yzww
      cmp_pp r1.xyz, -r1.x, c1.z, r2
      texld_pp r2, v0.wzzw, s0
      add r3, -r2.wxyz, c1.xyyy
      mov_sat_pp r3.x, r3.x
      cmp r3.yzw, r3, c1.z, c1.y
      mul r4.xyz, r2, r3.x
      add_pp r0, r0, r2
      dp3 r1.w, r3.yzww, r3.yzww
      cmp r2.xyz, -r1.w, c1.z, r4
      add_pp r1.xyz, r1, r2
      texld_pp r2, v1, s0
      add r3, -r2.wxyz, c1.xyyy
      mov_sat_pp r3.x, r3.x
      cmp r3.yzw, r3, c1.z, c1.y
      mul r4.xyz, r2, r3.x
      add_pp r0, r0, r2
      dp3 r1.w, r3.yzww, r3.yzww
      cmp r2.xyz, -r1.w, c1.z, r4
      add_pp r1.xyz, r1, r2
      texld_pp r2, v1.wzzw, s0
      add r3, -r2.wxyz, c1.xyyy
      mov_sat_pp r3.x, r3.x
      cmp r3.yzw, r3, c1.z, c1.y
      mul r4.xyz, r2, r3.x
      add_pp r0, r0, r2
      dp3 r1.w, r3.yzww, r3.yzww
      cmp r2.xyz, -r1.w, c1.z, r4
      add_pp r1.xyz, r1, r2
      mul_pp r1.xyz, r1, c3.x
      mul_pp r1.xyz, r1, c1.w
      mov r1.w, c1.w
      mad_pp r0.w, r0.w, r1.w, -c0.x
      mul_pp r0.xyz, r0, c1.w
      mul_sat r1.w, r0_abs.w, c0.y
      cmp_pp r0.w, r0.w, c2.y, c2.x
      max r2.x, r1.w, c4.x
      pow_pp r1.w, r2.x, c0.z
      min_pp r2.w, r1.w, r0.w
      mad_pp r2.xyz, r2.w, r0, r1
      mul oC0, r2, c1.w
*/
