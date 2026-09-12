// Pause menu background post-process material: desaturates and tints the tonemapped scene.
// The sample is the mod's intermediate, so it is decoded/encoded through the renodx::draw helpers
// at UI (graphics white) scale.
sampler2D SceneColorTexture : register( s0 );
float4 ScreenPositionScaleBias : register( c1 );
float UniformScalar_0 : register( c2 );
float4 UniformVector_0 : register( c0 );

#include "../shared.h"

float4 main(float4 texcoord5 : TEXCOORD5) : COLOR
{
  float4 o;

  float4 r0;
  float3 r1;
  float3 r2;
  r0.x = 1 / texcoord5.w;
  r0.xy = r0.x * texcoord5.xy;
  r0.xy = r0.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
  r0 = tex2D(SceneColorTexture, r0);

  renodx::draw::Config config = renodx::draw::BuildConfig();
  config.intermediate_scaling = 1.f;
  r1.xyz = renodx::draw::InvertIntermediatePass(r0.xyz, config);

  float3 hdr = r1.xyz;
  {
    hdr = hdr * float3(0.3, 0.3, 0.7) + float3(0.65, 0.7, 1);
    float y = renodx::color::y::from::BT709(hdr);
    y = renodx::math::Rescale(y, 0.8, 1, 0.5, 0, true);
    hdr = renodx::color::grade::Saturation(hdr, y);
  }

  r1.xyz = renodx::draw::RenderIntermediatePass(hdr, config);

  r2.xyz = lerp(r0.xyz, r1.xyz, UniformScalar_0.x);
  o.xyz = r2.xyz + UniformVector_0.xyz;
  o.w = texcoord5.w;

  return o;
}

/*
    ps_3_0
      0x0000012C:     def c3, 0.425904989, 0.974300027, 0.481952012, 0.400000006
      0x00000144:     def c4, 0.300000012, 0.699999988, 0.649999976, 1
      0x0000015C:     dcl_texcoord5 v0.xyw
      0x00000168:     dcl_2d s0
   0  0x00000174:     rcp r0.x, v0.w
   1  0x00000180:     mul r0.xy, r0.x, v0
   2  0x00000190:     mad r0.xy, r0, c1, c1.wzzw
   3  0x000001A4:     texld r0, r0, s0
   3  0x000001B4:     dp3 r0.w, r0, c3
   4  0x000001C4:     lrp r1.xyz, c3.w, r0.w, r0
   5  0x000001D8:     mad_sat r1.xyz, r1, c4.xxyw, c4.zyww
   6  0x000001EC:     lrp r2.xyz, c2.x, r1, r0
   7  0x00000200:     add_pp oC0.xyz, r2, c0
   8  0x00000210:     mov oC0.w, v0.w

// approximately 10 instruction slots used (1 texture, 9 arithmetic)

//   Name                    Reg   Size
//   ----------------------- ----- ----
//   UniformVector_0         c0       1
//   ScreenPositionScaleBias c1       1
//   UniformScalar_0         c2       1
//   SceneColorTexture       s0       1
*/
