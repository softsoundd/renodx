// Game gamma encode + Ms/Bs colour curves, shared by TdToneMapping and TdCalibration (both bind
// the curve textures at s1/s2). 15/16 is LUT addressing: the curve textures are point sampled,
// segment = floor(15x), texel 15 only at x = 1.
#include "../shared.h"

sampler2D ColorCurvesKTexture : register(s1);
sampler2D ColorCurvesMTexture : register(s2);

float3 GammaAndCurves(float3 color, float gamma_inv) {
  float3 encoded = pow(color, gamma_inv);  // 1/DisplayGamma, 1/2.0 at the in-game Brightness midpoint

  const float correction = (15.f / 16.f);
  float4 r_curve = tex2D(ColorCurvesKTexture, float2(encoded.x * correction, 0));
  float4 g_curve = tex2D(ColorCurvesKTexture, float2(encoded.y * correction, 0));
  float4 b_curve = tex2D(ColorCurvesMTexture, float2(encoded.z * correction, 0));
  float3 curved;
  curved.x = encoded.x * r_curve.x + r_curve.y;
  curved.y = encoded.y * g_curve.z + g_curve.w;
  curved.z = encoded.z * b_curve.x + b_curve.y;

  return lerp(encoded, curved, VCG_LUT);  // strength
}
