// TdToneMapExposurePixelShader.usf (also included by the shader/faithfulluma/exposure_* variant)
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

// The level's exposure floor (Scene_ExposureLow^2) on the stored value's scale. Both models write it
// to the output's green channel, which nothing else reads, so the tone mapper knows the meter's gain
// over the floor for the Faithful Luma shoulder whichever exposure model is running.
float FloorOutput() {
  return ExposureSettings.z * ExposureSettings.z * max(ExposureSettings.x, 0.001f) / 64.0f;
}

// Faithful Luma (TdToneMapExposurePixelShader.usf): the shipped meter, key and sqrt-domain clamps,
// then movement in stops at a fixed speed per second that eases in exponentially inside the
// transition distance, with a per-frame step floor in codes of the game's 16-bit exposure store (at
// or above one ulp of the FP16 target the mod upgrades it to). The engine uploads
// ExposureSettings.y = dt * min(SpeedUp, 2.5) and MaxDeltaDown = dt * min(SpeedDown, 3.0); each
// direction recovers dt from its own upload, so a level's lowered or zeroed speed slows or holds
// that direction as shipped.
static const float FL_ADAPTATION_SPEED_TO_LIGHT = 12.0f;  // stops/s, exposure falling
static const float FL_ADAPTATION_SPEED_TO_DARK = 6.0f;    // stops/s, exposure rising
static const float FL_EXPONENTIAL_TRANSITION_STOPS = 1.5f;
static const float FL_MIN_STEP_CODES = 2.0f;
static const float FL_EXPOSURE_CODE = 64.0f / 65535.0f;

float4 FaithfulLumaExposure() {
  float luminosity = dot(SampleAverageSceneColor(), float3(0.3f, 0.59f, 0.11f));

  float target_sqrt = sqrt(0.25f / clamp(luminosity, 1e-7f, 5000.0f));
  float clamped_sqrt = clamp(target_sqrt, ExposureSettings.z, ExposureSettings.w);
  float low_exposure = ExposureSettings.z * ExposureSettings.z;
  float high_exposure = ExposureSettings.w * ExposureSettings.w;
  float target_exposure = clamped_sqrt * clamped_sqrt;

  // Scene_ExposureManual is multiplied into the stored value; divide it back out of the state.
  float manual = max(ExposureSettings.x, 0.001f);
  float previous = saturate(tex2D(PreviousExposureTexture, 0.5).r) * 64.0f / manual;
  // A cleared target (0) carries no state: start on the target instead of fading up from the floor.
  float current_exposure = (previous > 0.0f)
                               ? clamp(previous, max(low_exposure, 0.0001f), high_exposure)
                               : target_exposure;

  bool to_light = target_exposure < current_exposure;
  float delta_time = to_light ? MaxDeltaDown / 3.0f : ExposureSettings.y / 2.5f;
  float speed = to_light ? FL_ADAPTATION_SPEED_TO_LIGHT : FL_ADAPTATION_SPEED_TO_DARK;

  float gap_stops = abs(log2(target_exposure / current_exposure));
  float linear_stops = speed * delta_time;
  float eased_stops = gap_stops * (1.0f - exp(-speed * delta_time / FL_EXPONENTIAL_TRANSITION_STOPS));
  float step_stops = min((gap_stops > FL_EXPONENTIAL_TRANSITION_STOPS) ? linear_stops : eased_stops, gap_stops);
  float gap = target_exposure - current_exposure;
  float step = abs(current_exposure * exp2(sign(gap) * step_stops) - current_exposure);
  float step_magnitude = min(max(step, FL_MIN_STEP_CODES * FL_EXPOSURE_CODE), abs(gap));
  float new_exposure = current_exposure + (delta_time > 0.0f ? sign(gap) * step_magnitude : 0.0f);

  return float4(saturate(new_exposure * manual / 64.0f), FloorOutput(), 0, 0);
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
  o.y = FloorOutput();

  return o;
}
