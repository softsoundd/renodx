#include "../shared.h"

// Set by the shader/faithfulluma/ files, which replace the shaders the game compiles from the
// Faithful Luma .usf sources.
#ifndef FAITHFUL_LUMA_COMPILED
#define FAITHFUL_LUMA_COMPILED 0
#endif

static const float3 LUMA_WEIGHTS_709 = float3(0.2126f, 0.7152f, 0.0722f);
static const float MAX_SCENE_COLOR = 4.0f;  // UE3 fixed point filter buffer scale

float InverseLerp1(float a, float b, float v) {
  return saturate((v - a) / (b - a));
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// "Auto" modes follow the shaders the game is running.

bool FaithfulLumaActive() {
  return FAITHFUL_LUMA_COMPILED || FAITHFUL_LUMA_DETECTED != 0;
}

bool UseFaithfulLumaLook() {
  if (TONE_MAP_LOOK == LOOK_FAITHFUL_LUMA) return true;
  if (TONE_MAP_LOOK == LOOK_VANILLA) return false;
  return FaithfulLumaActive();
}

bool UseFaithfulLumaExposure() {
  if (EXPOSURE_MODEL == EXPOSURE_FAITHFUL_LUMA) return true;
  if (EXPOSURE_MODEL == EXPOSURE_VANILLA) return false;
  return FaithfulLumaActive();
}

float ResolveBloomModel() {
  if (BLOOM_MODEL != BLOOM_AUTO) return BLOOM_MODEL;
  return FaithfulLumaActive() ? BLOOM_FAITHFUL_LUMA : BLOOM_VANILLA;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Faithful Luma (TdToneMappingPixelShader.usf), evaluated in linear HDR.

// Luminance-anchored extended Reinhard with hue-stable RGB reconstruction and a quadratic
// highlight desaturation above LumaHDR = 2.0.
float3 FaithfulLumaToneMap(float3 graded_hdr, out float luma_tm) {
  const float linear_white = MAX_SCENE_COLOR;
  float luma_hdr = dot(graded_hdr, LUMA_WEIGHTS_709);
  luma_tm = luma_hdr * (1.0f + (luma_hdr / (linear_white * linear_white))) / (1.0f + luma_hdr);
  float3 reconstructed = graded_hdr * (luma_tm / max(luma_hdr, 0.0001f));

  float highlight_chroma_weight = saturate((luma_hdr - (linear_white * 0.5f)) / (linear_white * 1.5f));
  highlight_chroma_weight *= highlight_chroma_weight;
  return lerp(reconstructed, luma_tm.xxx, highlight_chroma_weight * 0.55f);
}

// Per-channel SceneMidTones pow in shadows, fading to a neutral luminance exponent by LumaTM ~= 0.73.
float3 FaithfulLumaMidTones(float3 tonemapped, float luma_tm, float3 scene_mid_tones) {
  float neutral_mid_tone = dot(scene_mid_tones, LUMA_WEIGHTS_709);
  float3 neutral = pow(max(0.0001f, tonemapped), neutral_mid_tone.xxx);
  float3 per_channel = pow(max(0.0001f, tonemapped), scene_mid_tones);
  float grade_preserve_weight = 1.0f - saturate((luma_tm - 0.16f) * 1.75f);
  return lerp(neutral, per_channel, grade_preserve_weight);
}

// Display space: blends bright, near-neutral pixels toward their own luminance without adding energy.
float3 FaithfulLumaWhiteNeutrality(float3 color) {
  const float white_luma_start = 0.72f;
  const float white_luma_range = 0.28f;
  const float white_chroma_start = 0.04f;
  const float white_chroma_range = 0.30f;
  const float white_neutrality_strength = 0.85f;

  float luma = dot(color, LUMA_WEIGHTS_709);
  float display_energy = (color.r + color.g + color.b) / 3.0f;
  float peak = max(max(color.r, color.g), color.b);
  float low_channel = min(min(color.r, color.g), color.b);
  float relative_chroma = (peak - low_channel) / max(peak, 0.001f);
  float luma_mask = saturate((luma - white_luma_start) / white_luma_range);
  float neutrality_mask = 1.0f - saturate((relative_chroma - white_chroma_start) / white_chroma_range);
  float white_mask = luma_mask * luma_mask * neutrality_mask * neutrality_mask;
  float3 corrected = lerp(color, luma.xxx, white_mask * white_neutrality_strength);
  float corrected_energy = (corrected.r + corrected.g + corrected.b) / 3.0f;
  float energy_protection = min(1.0f, display_energy / max(corrected_energy, 0.001f));
  return saturate(corrected * lerp(1.0f, energy_protection, white_mask));
}

// Display space: near-black rolloff, 2.5/255 -> 0, unchanged from 16/255 up.
float3 FaithfulLumaBlackFloor(float3 color) {
  const float old_black_point = 2.5f / 255.0f;
  const float roll_off_stopping_point = 16.0f / 255.0f;
  const float roll_off_range = roll_off_stopping_point - old_black_point;
  const float min_lum = (0.0f - old_black_point) / roll_off_range;

  float display_luma = dot(color, LUMA_WEIGHTS_709);
  if (display_luma >= roll_off_stopping_point) return color;

  float t = (display_luma - old_black_point) / roll_off_range;
  float toe = 1.0f - t;
  toe *= toe;
  toe *= toe;
  float corrected_luma = max(0.0f, (min_lum * toe + t) * roll_off_range + old_black_point);
  return saturate(color * (corrected_luma / max(display_luma, 0.0001f)));
}

// Faithful Luma bloom (DOFAndBloomGather/Blend .usf): Rec.709 luminance quadratic soft knee.
// Returns the factor applied to the scene color; `scatter` adds the gather pass hot-source weight.
float FaithfulLumaBloomFactor(float3 scene_color, float luma, bool scatter) {
  const float threshold = 1.0f;
  const float knee = 0.5f;
  float strength = scatter
                       ? 1.0f / (MAX_SCENE_COLOR - 1.0f)
                       : 1.0f / (MAX_SCENE_COLOR * (MAX_SCENE_COLOR - 1.0f));

  float soft = clamp(luma - threshold + knee, 0.0f, 2.0f * knee);
  float soft_excess = soft * soft / max(4.0f * knee, 0.001f);
  float bloom_energy = max(soft_excess, luma - threshold);
  float peak = max(max(scene_color.r, scene_color.g), scene_color.b);
  float neutrality = saturate(((luma / max(peak, 0.001f)) - 0.25f) * 1.5f);
  float scatter_weight = 1.0f;
  if (scatter) {
    float hot_weight = saturate((luma - threshold) / max(MAX_SCENE_COLOR - threshold, 0.001f));
    scatter_weight = 1.0f + hot_weight * hot_weight;
  }
  return strength * lerp(0.65f, 1.0f, neutrality) * scatter_weight * bloom_energy / max(luma, 0.001f);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

namespace renodx {
namespace color {
namespace ictcp {
namespace from {
float3 BT2020(float3 bt2020_color, float scaling = 100.f) {
  float3 lms = mul(mul(XYZ_TO_DOLBY_LMS_MAT, BT2020_TO_XYZ_MAT), bt2020_color);
  float3 plms = pq::Encode(max(0, lms), scaling);
  return mul(PLMS_TO_ICTCP_MAT, plms);
}

float4 BT709WithY(float3 bt709_color, float scaling = 100.f) {
  float3 xyz = mul(BT709_TO_XYZ_MAT, bt709_color);
  float3 lms = mul(XYZ_TO_DOLBY_LMS_MAT, xyz);
  float3 plms = pq::Encode(max(0, lms), scaling);
  return float4(mul(PLMS_TO_ICTCP_MAT, plms), xyz.y);
}
}}}}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// From https://github.com/Filoppi/Luma-Framework/blob/main/Shaders/Includes/ColorGradingLUT.hlsl
// Restores the source hue (and optionally lightness) in a UCS Lab space, then the target chrominance.
// Works on colors beyond SDR brightness and gamut; a hue strength of ~0.75 is a strong restoration.
float3 RestoreHueAndChrominance(float3 targetUcsLab, float3 sourceUcsLab, float hueStrength = 1.0, float chrominanceStrength = 1.0, float lightnessStrength = 0.0, float saturation = 1.0)
{
  const static float minChrominanceChange = 0;
  const static float maxChrominanceChange = renodx::math::FLT16_MAX;

  targetUcsLab.x = lerp(targetUcsLab.x, sourceUcsLab.x, lightnessStrength);

  float currentChrominance = length(targetUcsLab.yz);

  if (hueStrength != 0.0)
  {
    // Blending ab corrects hue and chrominance together (works toward white too, never flipping past it);
    // the original chrominance is restored right after.
    const float chrominancePre = currentChrominance;
    targetUcsLab.yz = lerp(targetUcsLab.yz, sourceUcsLab.yz, hueStrength);
    const float chrominancePost = length(targetUcsLab.yz);
    float chrominanceRatio = renodx::math::SafeDivision(chrominancePre, chrominancePost, 1);
    targetUcsLab.yz *= chrominanceRatio;
  }

  if (chrominanceStrength != 0.0)
  {
    const float sourceChrominance = length(sourceUcsLab.yz);
    float targetChrominanceRatio = renodx::math::SafeDivision(sourceChrominance, currentChrominance, 1);
    targetChrominanceRatio = clamp(targetChrominanceRatio, minChrominanceChange, maxChrominanceChange);
    targetUcsLab.yz *= lerp(1.0, targetChrominanceRatio, chrominanceStrength);
  }

  targetUcsLab.yz *= saturation;

  return targetUcsLab;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Gamma-domain BT.709 -> BT.2020 expansion, corrected back toward the source hue/chroma/luma in ICtCp.
float3 FakeWCGBT709(float3 color, float DecodeGamma = 2.2, float CorrectionChrominance = 0.5, float CorrectionLuminance = 0.6, float Saturation = 1.0) {
  if (DecodeGamma <= 0) return color;

  float3 colorRef = renodx::color::bt2020::from::BT709(color);
  float3 colorExp = color;

  colorExp = renodx::color::gamma::EncodeSafe(colorExp, DecodeGamma);
  colorExp = renodx::color::bt2020::from::BT709(colorExp);
  colorExp = renodx::color::gamma::DecodeSafe(colorExp, DecodeGamma);

  colorExp = renodx::color::ictcp::from::BT2020(colorExp);
  colorRef = renodx::color::ictcp::from::BT2020(colorRef);
  colorExp = RestoreHueAndChrominance(colorExp, colorRef, 1.0, CorrectionChrominance, CorrectionLuminance, Saturation);
  colorExp = renodx::color::bt709::from::ICtCp(colorExp);

  return colorExp;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Luminance-delta HDR bridge: adds the luminance the SDR proxy removed back onto the graded SDR color.
float3 UpgradeToneMap1(float3 color_untonemapped, float3 color_tonemapped, float3 color_tonemapped_graded) {
  float y_untonemapped = renodx::color::y::from::BT709(color_untonemapped);
  float y_tonemapped = renodx::color::y::from::BT709(color_tonemapped);
  float y_tonemapped_graded = renodx::color::y::from::BT709(color_tonemapped_graded);

  float ratio;
  if (y_untonemapped < y_tonemapped) {
    // Subtracting (user contrast or paperwhite): scale down instead
    ratio = y_untonemapped / y_tonemapped;
  } else {
    const float y_new = y_tonemapped_graded + max(0, y_untonemapped - y_tonemapped);
    ratio = (y_tonemapped_graded > 0) ? (y_new / y_tonemapped_graded) : 0;  // ignores black and NaN
  }

  float3 color_scaled = color_tonemapped_graded * ratio;
  return renodx::color::correct::HueICtCp(color_scaled, color_tonemapped_graded);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Sun glare/lens sprites (additive billboards). Neutral at C_SUNGLARE == 1 and C_SUNSIZE == 0;
// the saturation restore ramps in with the glare boost.
float3 SunPass(in float3 color, in float2 uv, in float strength) {
  if (TONE_MAP_TYPE == 0) return color;

  if (C_SUNGLARE != 1.f) {
    color = renodx::color::grade::Saturation(color, lerp(1.f, 1.5f, saturate((C_SUNGLARE - 1.f) / 2.8f)));
    color *= C_SUNGLARE;
  }

  const float sunSizeScaled = C_SUNSIZE * 0.002f;
  if (sunSizeScaled > 0) {
    float dist = distance((float2)0.5f, uv);
    const float glowSizeOffset = 0.0075f;
    if (dist < sunSizeScaled + glowSizeOffset && strength > 0.75f) {
      float s = InverseLerp1(sunSizeScaled, sunSizeScaled + glowSizeOffset, dist);
      s = 1 - s;
      s = pow(s, 3);
      color += lerp(0, 20000 / 203, s);
    }
  }

  return color;
}
