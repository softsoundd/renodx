// GammaCorrectionPixelShader.usf: the plain scene -> display pass used when the TdToneMapping
// post process is not active (main menu, some transitions). Linear HDR scene in, display encoded out.
float3 ColorScale : register( c0 );
float InverseGamma : register( c3 );
float4 OverlayColor : register( c2 );
sampler2D SceneColorTexture : register( s0 );
#include "./common.hlsl"

float4 main(float2 texcoord : TEXCOORD) : COLOR
{
  float4 o;
  o.w = 1;

  float4 r0;
  float3 r1;
  float3 r2;
  r0 = tex2D(SceneColorTexture, texcoord);

  // LinearColor = lerp(scene * ColorScale, OverlayColor.rgb, OverlayColor.a)
  r1.xyz = r0.xyz * ColorScale.xyz;
  r2.xyz = ColorScale.xyz;

  r0.xyz = r0.xyz * -r2.xyz + OverlayColor.xyz;
  r0.xyz = OverlayColor.w * r0.xyz + r1.xyz;
  r0.xyz = max(r0.xyz, 0);

  const float gamma = 1 / InverseGamma;

  if (TONE_MAP_TYPE == 0) {
    // vanilla: pow(saturate(LinearColor), InverseGamma), then presented like the tonemap SDR path
    o.xyz = pow(saturate(r0.xyz), InverseGamma);
    o.xyz = renodx::color::srgb::Decode(o.xyz);
    o.xyz = renodx::draw::RenderIntermediatePass(o.xyz);
    return o;
  }

  // HDR: no clip; game gamma as shown by an sRGB display, then the same peak rolloff as the tonemap
  o.xyz = renodx::color::correct::Gamma(r0.xyz, true, gamma);
  if (TONE_MAP_TYPE >= 2) {
    const float p = PEAK_WHITE_NITS / DIFFUSE_WHITE_NITS;
    const float e = EXPECTED_WHITE_NITS / DIFFUSE_WHITE_NITS;
    o.xyz = renodx::tonemap::HermiteSplineLuminanceRolloff(o.xyz, p, e);
  }
  o.xyz = renodx::draw::RenderIntermediatePass(o.xyz);
  return o;
}

/*
    ps_3_0
      0x00000130:     def c1, 9.99999975e-005, 1, 0, 0
      0x00000148:     dcl_texcoord v0.xy
      0x00000154:     dcl_2d s0
   0  0x00000160:     texld_pp r0, v0, s0
   0  0x00000170:     mul_pp r1.xyz, r0, c0
   1  0x00000180:     mov_pp r2.xyz, c0
   2  0x0000018C:     mad_pp r0.xyz, r0, -r2, c2
   3  0x000001A0:     mad_sat r0.xyz, c2.w, r0, r1
   4  0x000001B4:     max r1.xyz, r0, c1.x
   5  0x000001C4:     log r0.x, r1.x
   6  0x000001D0:     log r0.y, r1.y
   7  0x000001DC:     log r0.z, r1.z
   8  0x000001E8:     mul r0.xyz, r0, c3.x
   9  0x000001F8:     exp oC0.x, r0.x
  10  0x00000204:     exp oC0.y, r0.y
  11  0x00000210:     exp oC0.z, r0.z
  12  0x0000021C:     mov oC0.w, c1.y

*/
