// TdToneMapExposurePixelShader.usf (also included by shader/faithfulluma/exposure_0xC7C7E0A5)
#include "./common.hlsl"

float4 ExposureSettings : register( c0 );  // Packed (Manual, MaxDeltaUp, LowClamp, HighClamp)
float MaxDeltaDown : register( c2 );
sampler2D PreviousExposureTexture : register( s1 );
sampler2D SceneDownsampledTexture : register( s0 );

// The average is clamped to [0,1] like the UNORM target the game authored against; the FP16
// upgrade would otherwise change exposure in scenes whose average exceeds 1.0.
float3 SampleAverageSceneColor() {
  float3 color = saturate(tex2D(SceneDownsampledTexture, 0.5).rgb);
  if (!(color.r > 0) && !(color.r < 0)) color = 0.25;  // vanilla NaN (and exact black) fallback
  return color;
}

// Faithful Luma: linear key, Rec.709 luminance, frame-rate independent asymmetric adaptation,
// dark-scene boost above the level's ExposureHigh clamp.
float4 FaithfulLumaExposure() {
  const float key_value = 0.25f;
  const float dark_boost_max = FL_DARK_BOOST;

  float avg_luminance = dot(SampleAverageSceneColor(), LUMA_WEIGHTS_709);

  float target_unclamped = key_value / max(avg_luminance, 0.001f);
  float target_clamped = clamp(target_unclamped, ExposureSettings.z, ExposureSettings.w);
  float clamp_deficit = saturate(1.0f - target_clamped / target_unclamped);
  float max_exposure = ExposureSettings.w * (1.0f + dark_boost_max);
  float target_exposure = target_clamped * (1.0f + dark_boost_max * clamp_deficit);

  float current_exposure = saturate(tex2D(PreviousExposureTexture, 0.5).r) * 64.0f;
  current_exposure = clamp(current_exposure, ExposureSettings.z, max_exposure);

  // ExposureSettings.y / MaxDeltaDown are engine rates already scaled by DeltaTime (shipped
  // defaults 0.275 / 0.475), used here as the frame-time proxy for 1.24/s up and 9.3/s down.
  float adaptation_alpha = (target_exposure < current_exposure)
                               ? saturate(MaxDeltaDown * (9.3f / 0.475f))
                               : saturate(ExposureSettings.y * (1.24f / 0.275f));

  float new_exposure = lerp(current_exposure, target_exposure, adaptation_alpha);
  new_exposure = clamp(new_exposure, ExposureSettings.z, max_exposure);

  return saturate(new_exposure * ExposureSettings.x / 64.0f);
}

float4 main() : COLOR
{
  if (UseFaithfulLumaExposure()) return FaithfulLumaExposure();

  // vanilla: square-root key model
  float4 o;

  float4 r0;
  float4 r1;
  float r2;
  r0.xyz = SampleAverageSceneColor();
  r0.x = dot(r0.xyz, float3(0.3, 0.59, 0.11));
  r1.x = max(r0.x, 1E-07);
  r0.x = min(r1.x, 5000);
  r0.x = 1 / r0.x;
  r0.x = r0.x * 0.25;
  r0.x = 1 / sqrt(r0.x);
  r0.x = 1 / r0.x;
  r1.x = max(r0.x, ExposureSettings.z);
  r0.x = min(ExposureSettings.w, r1.x);
  r1 = tex2D(PreviousExposureTexture, 0.5);
  r1 = saturate(r1);

  r0.y = r1.x * 64;
  r0.y = 1 / sqrt(r0.y);
  r0.y = 1 / r0.y;
  r1.x = max(r0.y, ExposureSettings.z);
  r0.y = min(ExposureSettings.w, r1.x);
  r0.x = r0.x + -r0.y;
  r0.z = abs(r0.x) * r0.x;
  r0.x = abs(r0.x) * abs(r0.x);
  r0.w = r0.x * -MaxDeltaDown.x;
  r0.x = r0.x * ExposureSettings.y;
  r1.x = max(r0.z, r0.w);
  r2.x = min(r0.x, r1.x);
  r0.x = r0.y + r2.x;
  r0.x = r0.x * r0.x;
  r0.x = r0.x * ExposureSettings.x;
  o = r0.x * 0.015625;  // 1 / 64
  o = saturate(o);

  return o;
}
