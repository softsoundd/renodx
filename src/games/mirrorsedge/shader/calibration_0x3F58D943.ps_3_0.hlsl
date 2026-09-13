// TdCalibrationShader.usf: the brightness calibration screen. The scene sample is already the mod's
// intermediate and passes through; the reference quads go through the game gamma + colour curves and
// are written like the tonemap's SDR output, so quad white lands on Game white.
sampler2D SceneColorTexture : register(s0);
float4 GammaColorScaleAndInverse : register(c0);

#include "./common.hlsl"
#include "./color_curves.hlsl"

struct PS_IN {
  float2 scene_uv : TEXCOORD0;
  float2 screen_uv : TEXCOORD1;
};

float4 main(PS_IN i) : COLOR {
  float3 scene = tex2D(SceneColorTexture, i.scene_uv).rgb;

  const float2 uv = i.screen_uv;
  const bool in_x = uv.x > 0.65f && uv.x < 0.85f;
  const bool inner_x = uv.x > 0.7f && uv.x < 0.8f;

  float quad = 0.f;
  bool is_quad = false;
  if (in_x && uv.y > 0.35f && uv.y < 0.574f) {  // white quad, 0.95 inset
    quad = (inner_x && uv.y > 0.4f && uv.y < 0.524f) ? 0.95f : 1.f;
    is_quad = true;
  }
  if (in_x && uv.y > 0.605f && uv.y < 0.8375f) {  // black quad, 0.005 inset
    quad = (inner_x && uv.y > 0.655f && uv.y < 0.7875f) ? 0.005f : 0.f;
    is_quad = true;
  }
  if (!is_quad) return float4(scene, 1);

  float3 encoded = GammaAndCurves(saturate(quad * GammaColorScaleAndInverse.xyz), GammaColorScaleAndInverse.w);
  float3 linear_color = renodx::color::srgb::Decode(saturate(encoded));
  return float4(renodx::draw::RenderIntermediatePass(linear_color), 1);
}
