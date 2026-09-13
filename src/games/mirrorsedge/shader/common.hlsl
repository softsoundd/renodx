#include "../shared.h"

// Set by the shader/faithfulluma/ files, which replace the shaders the game compiles from the
// Faithful Luma .usf sources.
#ifndef FAITHFUL_LUMA_COMPILED
#define FAITHFUL_LUMA_COMPILED 0
#endif

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
// Faithful Luma (TdToneMappingPixelShader.usf). Constants match the .usf defaults.

static const float FL_SOFT_CLIP_KNEE = 0.25f;             // graded value where the shoulder starts; below it the image is the shipped image
static const float FL_SOFT_CLIP_WHITE = MAX_SCENE_COLOR;  // graded value that reaches 1.0
static const float FL_HUE_PRESERVATION = 0.5f;            // SDR proxy: 0 = per-channel shoulder, 1 = saturated colours keep exact chromaticity
static const float FL_HUE_BLOWOUT_START = 1.0f;           // light sources blow out from here to FL_SOFT_CLIP_WHITE

// SDR proxy: 1 = over-range colours desaturate to the chroma the shipped clip left them. Set per
// compiled variant by the shader/faithfulluma/tonemap_* files.
#ifndef FL_HIGHLIGHT_DESATURATION
#define FL_HIGHLIGHT_DESATURATION 0.0f
#endif

// Identity below the knee, then an extended-Reinhard shoulder that is C1 at the knee and hits 1.0 at the white point.
float3 FaithfulLumaShoulder(float3 x) {
  const float range = 1.0f - FL_SOFT_CLIP_KNEE;
  const float white_u = (FL_SOFT_CLIP_WHITE - FL_SOFT_CLIP_KNEE) / range;
  float3 u = max(x - FL_SOFT_CLIP_KNEE, 0.0f) / range;
  float3 r = u * (1.0f + u / (white_u * white_u)) / (1.0f + u);
  return min(min(x, FL_SOFT_CLIP_KNEE) + range * r, 1.0f);
}

float Saturation(float3 color) {
  return 1.0f - min(color.r, min(color.g, color.b)) / max(max(color.r, max(color.g, color.b)), 0.0001f);
}

// Scales chroma toward the peak channel (hue kept) until the saturation is no higher than the target.
float3 LimitSaturation(float3 color, float target_saturation) {
  float peak = max(color.r, max(color.g, color.b));
  return lerp(peak.xxx, color, min(target_saturation / max(Saturation(color), 0.0001f), 1.0f));
}

// The .usf display transform as shipped, for the SDR output type: per-channel shoulder, blended
// toward the input chromaticity by saturation (fading out for light sources far over range), then
// optionally desaturated to the chroma min(graded, 1) would have had. Nothing at or below 1.0 changes.
float3 FaithfulLumaSdrProxy(float3 graded) {
  float3 per_channel = FaithfulLumaShoulder(graded);
  float peak = max(graded.r, max(graded.g, graded.b));
  float3 hue_preserved = graded * (max(per_channel.r, max(per_channel.g, per_channel.b)) / max(peak, 0.0001f));

  float blowout = 1.0f - smoothstep(FL_HUE_BLOWOUT_START, FL_SOFT_CLIP_WHITE, peak);
  float3 color = lerp(per_channel, hue_preserved, FL_HUE_PRESERVATION * Saturation(graded) * blowout);

  return lerp(color, LimitSaturation(color, Saturation(min(graded, 1.0f))), FL_HIGHLIGHT_DESATURATION);
}

// The proxy for the HDR bridge, which carries the proxy's chromaticity into HDR. Up to white the
// shoulder runs on the peak channel so chromaticity is kept (the per-channel compression exists
// because SDR has no headroom; HDR has it). Over white, light sources lose as much saturation as
// the per-channel shoulder takes from them, ramping in with the .usf's blowout fade so they are
// white by FL_SOFT_CLIP_WHITE as shipped, with the hue kept.
float3 FaithfulLumaHdrProxy(float3 graded) {
  float peak = max(graded.r, max(graded.g, graded.b));
  float3 chromaticity_kept = graded * (FaithfulLumaShoulder(peak.xxx).x / max(peak, 0.0001f));
  float3 blown_out = LimitSaturation(chromaticity_kept, Saturation(FaithfulLumaShoulder(graded)));
  return lerp(chromaticity_kept, blown_out, smoothstep(FL_HUE_BLOWOUT_START, FL_SOFT_CLIP_WHITE, peak));
}

// Faithful Luma bloom (DOFAndBloomGatherPixelShader.usf): only the Rec.709 luminance above the
// threshold blooms, through a quadratic knee, and the factor scales the whole colour so the bloom
// keeps the pixel's chromaticity. The gather sees scene colour before exposure, so the threshold is
// the scene luminance that is display white at the authored exposure floor (Scene_ExposureLow^2).
float FaithfulLumaBloomFactor(float3 scene_color) {
  const float exposure_floor = 0.85f * 0.85f;
  const float threshold = 1.0f / exposure_floor;
  const float knee = 0.25f;
  const float strength = 1.0f;

  float luminance = renodx::color::y::from::BT709(scene_color);
  float soft = clamp(luminance - threshold + knee, 0.0f, 2.0f * knee);
  float soft_excess = soft * soft / (4.0f * knee);
  float energy = max(soft_excess, luminance - threshold);
  return strength * energy / max(luminance, 0.001f);
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
