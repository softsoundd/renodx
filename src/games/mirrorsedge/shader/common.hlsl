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
// Faithful Luma (TdToneMappingPixelShader.usf). Constants match the .usf defaults; the .usf
// documents them.

static const float FL_SOFT_CLIP_KNEE = 0.8f;        // graded value where the shoulder starts with the exposure at the level's floor
static const float FL_SOFT_CLIP_WHITE = 3.0f;       // graded value that reaches 1.0 at the floor
static const float FL_KNEE_GAIN_START = 1.25f;      // meter gain over the floor up to which the shoulder stays put
static const float FL_KNEE_GAIN_POWER = 2.0f;       // beyond it the knee falls as gain^-power ...
static const float FL_WHITE_GAIN_POWER = 0.5f;      // ... and the white rises as gain^power
static const float FL_SOFT_CLIP_KNEE_MIN = 0.35f;
static const float FL_SOFT_CLIP_WHITE_MAX = 6.0f;
static const float FL_BEZOLD_BRUCKE_PER_STOP = 1.5f;  // degrees of OKLab hue per stop the shoulder darkened the colour

// Identity below the knee, then an extended-Reinhard shoulder that is C1 at the knee and hits 1.0 at the white point.
float3 FaithfulLumaShoulder(float3 x, float knee, float white) {
  const float range = 1.0f - knee;
  const float white_u = (white - knee) / range;
  float3 u = max(x - knee, 0.0f) / range;
  float3 r = u * (1.0f + u / (white_u * white_u)) / (1.0f + u);
  return min(min(x, knee) + range * r, 1.0f);
}

float2 OklabChroma(float3 color) {
  return renodx::color::oklab::from::BT709(color).yz;
}

// Direction of the Bezold-Bruecke shift for an OKLab hue in degrees: +1 counter-clockwise (red toward
// yellow, green toward cyan), -1 clockwise; zero at the invariant hues yellow 110, green 165, blue 264,
// purplish red 355.
float BezoldBruckeDirection(float hue_deg) {
  const float pi = renodx::math::PI;
  float d = frac((hue_deg - 355.0f) / 360.0f) * 360.0f;
  float s = sin(pi * d / 115.0f);
  s = (d >= 115.0f) ? -sin(pi * (d - 115.0f) / 55.0f) : s;
  s = (d >= 170.0f) ? sin(pi * (d - 170.0f) / 99.0f) : s;
  s = (d >= 269.0f) ? -sin(pi * (d - 269.0f) / 91.0f) : s;
  return s;
}

// Signed misalignment of a colour's OKLab hue from a target chroma direction; zero when they match.
float HueMismatch(float3 color, float2 target) {
  float2 ab = OklabChroma(color);
  return ab.x * target.y - ab.y * target.x;
}

// The shoulder's knee and white for a meter gain over the level's floor (E / Low^2, read from the
// exposure buffer's r and g).
void FaithfulLumaShoulderShape(float gain, out float knee, out float white) {
  float gain_norm = max(gain / FL_KNEE_GAIN_START, 1.0f);
  knee = max(FL_SOFT_CLIP_KNEE * pow(gain_norm, -FL_KNEE_GAIN_POWER), FL_SOFT_CLIP_KNEE_MIN);
  white = min(FL_SOFT_CLIP_WHITE * pow(gain_norm, FL_WHITE_GAIN_POWER), FL_SOFT_CLIP_WHITE_MAX);
}

// The .usf hue step on a shaped (range-limited) rendering of graded: its peak and floor channels
// are kept while the middle channel is solved so the OKLab hue is the scene's, turned by the
// Bezold-Bruecke shift for the stops the shaping darkened the colour and, by authored_hue, toward
// the hue the shipped clip gave the colour weighted by the share of its luminance above display
// white. Neutral input and input with two channels tied have no middle channel and pass through.
float3 FaithfulLumaSolveHue(float3 graded, float3 shaped, float authored_hue, float bezold_brucke_per_stop) {
  float peak_in = max(graded.r, max(graded.g, graded.b));
  float low_in = min(graded.r, min(graded.g, graded.b));
  float peak_out = max(shaped.r, max(shaped.g, shaped.b));
  float low_out = min(shaped.r, min(shaped.g, shaped.b));
  float3 is_peak = (graded >= peak_in) ? 1.0f : 0.0f;
  float3 is_low = (graded <= low_in) ? 1.0f - is_peak : 0.0f;
  float3 is_mid = 1.0f - is_peak - is_low;
  float3 fixed = is_peak * peak_out + is_low * low_out;

  float2 chroma_in = OklabChroma(graded);
  float hue_in = degrees(atan2(chroma_in.y, chroma_in.x));
  float luma_in = max(renodx::color::y::from::BT709(graded), 1e-4f);
  float stops = max(log2(luma_in / max(renodx::color::y::from::BT709(shaped), 1e-4f)), 0.0f);
  float turn_deg = bezold_brucke_per_stop * stops * BezoldBruckeDirection(hue_in);
  if (authored_hue > 0.0f) {
    float3 clip = min(graded, 1.0f);
    float2 chroma_clip = OklabChroma(clip);
    float hue_clip = degrees(atan2(chroma_clip.y, chroma_clip.x));
    float share = saturate((luma_in - renodx::color::y::from::BT709(clip)) / luma_in);
    float chroma_kept = saturate(length(chroma_clip) / max(length(chroma_in), 1e-4f));
    float to_clip = hue_clip - hue_in;
    to_clip -= 360.0f * round(to_clip / 360.0f);
    turn_deg += authored_hue * share * chroma_kept * to_clip;
  }
  float turn = radians(turn_deg);
  float2 target = float2(chroma_in.x * cos(turn) - chroma_in.y * sin(turn), chroma_in.x * sin(turn) + chroma_in.y * cos(turn));

  // Hue is monotonic in the middle channel: two secant steps from the channel-ratio solution and
  // the shaped colour's own middle value land on the target.
  float mid0 = low_out + (dot(graded, is_mid) - low_in) * ((peak_out - low_out) / max(peak_in - low_in, 1e-4f));
  float mid1 = dot(shaped, is_mid);
  float f0 = HueMismatch(fixed + is_mid * mid0, target);
  float f1 = HueMismatch(fixed + is_mid * mid1, target);
  float mid2 = clamp(mid0 - f0 * (mid1 - mid0) / (f1 - f0 + 1e-6f), low_out, peak_out);
  float f2 = HueMismatch(fixed + is_mid * mid2, target);
  float mid3 = clamp(mid2 - f2 * (mid2 - mid1) / (f2 - f1 + 1e-6f), low_out, peak_out);
  return fixed + is_mid * mid3;
}

// The SDR output type shows the .usf result as installed: the meter-tightened shoulder per channel,
// then its hue solved with the Bezold-Bruecke turn and the full authored share of the clip's hue.
float3 FaithfulLumaSdrProxy(float3 graded, float gain) {
  float knee, white;
  FaithfulLumaShoulderShape(gain, knee, white);
  return FaithfulLumaSolveHue(graded, FaithfulLumaShoulder(graded, knee, white), 1.0f, FL_BEZOLD_BRUCKE_PER_STOP);
}

// The HDR bridge takes the proxy's chromaticity into HDR. The per-channel shoulder desaturates
// because SDR has no headroom; HDR has it, so up to diffuse white the scene's chromaticity is kept
// (the shoulder run on the peak channel), and from there to the shoulder's white point it blends
// toward the per-channel saturation, so light sources whiten as the shaders do while sunlit
// surfaces keep their tint. The hue is solved on that blend without the Bezold-Bruecke turn, which
// is for a rendering dimmer than the scene; the authored share of the clip's hue is the Authored
// Hue setting.
float3 FaithfulLumaHdrProxy(float3 graded, float gain) {
  float knee, white;
  FaithfulLumaShoulderShape(gain, knee, white);
  float peak = max(graded.r, max(graded.g, graded.b));
  float3 chromaticity_kept = graded * (FaithfulLumaShoulder(peak.xxx, knee, white).x / max(peak, 0.0001f));
  float3 per_channel = FaithfulLumaShoulder(graded, knee, white);  // same peak, lower floor channel
  float3 shaped = lerp(chromaticity_kept, per_channel, smoothstep(1.0f, white, peak));
  return FaithfulLumaSolveHue(graded, shaped, FL_AUTHORED_HUE, 0.0f);
}

// Faithful Luma bloom (DOFAndBloomGatherPixelShader.usf): only the Rec.709 luminance above the
// threshold blooms, through a quadratic knee, and the factor scales the whole colour so the bloom
// keeps the pixel's chromaticity. The gather sees scene colour before exposure, so the threshold is
// the scene luminance that is display white at the default volume's exposure floor; levels the
// meter exposes lower bloom sunlit surfaces below display white, as the shipped gate did more.
float FaithfulLumaBloomFactor(float3 scene_color) {
  const float default_floor_exposure = 0.85f * 0.85f;
  const float threshold = 1.0f / default_floor_exposure;
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
