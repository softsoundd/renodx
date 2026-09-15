/*
 * Copyright (C) 2024 Carlos Lopez
 * SPDX-License-Identifier: MIT
 */

#include <cfloat>
#include <unordered_map>
#include <unordered_set>

#define ImTextureID ImU64

#define RENODX_MODS_SWAPCHAIN_VERSION 2

// #define DEBUG_LEVEL_0

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>

#include <embed/shaders.h>

#include "../../mods/shader.hpp"
#include "../../mods/swapchain.hpp"
#include "../../utils/date.hpp"
#include "../../utils/hash.hpp"
#include "../../utils/settings.hpp"
#include "./shared.h"

namespace {

renodx::mods::shader::CustomShaders custom_shaders = {
    __ALL_CUSTOM_SHADERS,
};

ShaderInjectData shader_injection;

// Pixel shaders the game compiles from the Faithful Luma .usf sources. Their replacements in
// shader/faithfulluma/ share the vanilla register layout. The hashes are CRC32s of the bytecode
// d3dx9_35 produces for those sources under the engine's D3D9 environment (PIXELSHADER=1,
// VERTEXSHADER=0, COMPILER_HLSL=1, COMPILER_SUPPORTS_ATTRIBUTES=1, no flags; the gather adds
// NUM_SAMPLES and D3DXSHADER_AVOID_FLOW_CONTROL), which reproduces the vanilla hashes exactly.
const std::unordered_set<uint32_t> FAITHFUL_LUMA_SHADER_HASHES = {
    0xB0241043,  // TdToneMappingPixelShader
    0x9E378457,  // TdToneMapExposurePixelShader
    0xC7EFBFAE,  // DOFAndBloomGatherPixelShader (16 samples)
    0xBAE6E7E9,  // DOFAndBloomGatherPixelShader (4 samples)
    0xEA2A4332,  // TdCalibrationShader
    0x1EAAAADF,  // GammaCorrectionPixelShader
};

// Presets //////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void ApplyPreset(const renodx::utils::settings::Settings& settings, const std::unordered_map<std::string, float>& preset) {
  for (auto* setting : settings) {
    if (setting->key.empty()) continue;
    if (!setting->can_reset) continue;

    if (preset.contains(setting->key)) {
      float value = preset.at(setting->key);
      if (value == FLT_MIN) value = setting->default_value;
      renodx::utils::settings::UpdateSetting(setting->key, value);
    }
  }
}

const std::unordered_map<std::string, float> P_BLOWOUT_HC_VANILLA = {
    {"pblow_chue", FLT_MIN},
    {"pblow_csat", FLT_MIN},
};
const std::unordered_map<std::string, float> P_BLOWOUT_HC_NOHUE = {
    {"pblow_chue", 0.f},
    {"pblow_csat", FLT_MIN},
};

const std::unordered_map<std::string, float> P_BLOWOUT_T_GRADUAL = {
    {"pblow_start", FLT_MIN},
    {"pblow_max", FLT_MIN},
};

const std::unordered_map<std::string, float> P_BLOWOUT_T_BRICKWALL = {
    {"pblow_start", 1.f},
    {"pblow_max", 0.f},
};

bool IsFaithfulLumaLook() {
  if (shader_injection.tone_map_look == LOOK_FAITHFUL_LUMA) return true;
  return shader_injection.tone_map_look == LOOK_AUTO && shader_injection.faithful_luma_detected != 0.f;
}

renodx::utils::settings::Settings settings = {
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Neutral (Reset All)",
        .section = "Presets",
        .tooltip = "Restores every setting to its default value.",
        .on_change = []() {
          for (auto* setting : settings) {
            if (setting->key.empty()) continue;
            if (!setting->can_reset) continue;
            renodx::utils::settings::UpdateSetting(setting->key, setting->default_value);
          }
          renodx::utils::settings::SaveSettings(renodx::utils::settings::global_name + "-preset" + std::to_string(renodx::utils::settings::preset_index));
        },
    },

    // Brightness //////////////////////////////////////////////////////////////////////////////////////
    new renodx::utils::settings::Setting{
        .key = "diffuse_white_nits",
        .binding = &shader_injection.diffuse_white_nits,
        .default_value = 203.f,
        .label = "Game",
        .section = "Brightness",
        .tooltip = "Brightness of the game's 100% white in nits; the whole scene scales with it.\n203 is the HDR reference white.",
        .min = 1.f,
        .max = 500.f,
    },
    new renodx::utils::settings::Setting{
        .key = "graphics_white_nits",
        .binding = &shader_injection.graphics_white_nits,
        .default_value = 203.f,
        .label = "UI",
        .section = "Brightness",
        .tooltip = "Brightness of the HUD and menus in nits.",
        .min = 1.f,
        .max = 500.f,
    },
    new renodx::utils::settings::Setting{
        .key = "c_mov",
        .binding = &shader_injection.c_mov,
        .default_value = 203.f,
        .label = "Movies",
        .section = "Brightness",
        .tooltip = "Brightness of the pre-rendered videos (intro and loading movies) in nits.",
        .min = 0.f,
        .max = 500.f,
    },
    new renodx::utils::settings::Setting{
        .key = "GammaCorrection",
        .binding = &shader_injection.gamma_correction,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 1.f,
        .label = "Gamma Correction",
        .section = "Brightness",
        .tooltip = "Matches the picture to how an SDR display would have shown it. Off treats the game's output as sRGB; 2.2 and BT.1886 emulate those display gammas, which deepens shadows slightly.\nThe in-game Brightness slider still controls the game's own gamma (2.0 at its middle position).",
        .labels = {"Off", "2.2", "BT.1886"},
    },

    // Tone Map //////////////////////////////////////////////////////////////////////////////////////
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BULLET,
        .label = "Faithful Luma shaders detected.",
        .section = "Tone Map",
        .is_visible = []() { return shader_injection.faithful_luma_detected != 0.f; },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BULLET,
        .label = "Faithful Luma shaders not detected; the game's original shaders are in use.",
        .section = "Tone Map",
        .is_visible = []() { return shader_injection.faithful_luma_detected == 0.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "tone_map_type",
        .binding = &shader_injection.tone_map_type,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 3.f,
        .label = "Type",
        .section = "Tone Map",
        .tooltip = "SDR: the game's own SDR picture, clipped at white as shipped. The Auto Exposure and Bloom Extraction choices still apply.\n\nOff: no tone mapping; the scene goes to the display as is. For debugging.\n\nHDR Luminance + SDR Blowout: extends the SDR picture's brightness into HDR while reproducing the game's clipped highlights with the Blowout settings; highlights roll off toward the display Peak.\n\nRenoDRT (Neutwo): RenoDX's display rendering transform, recommended. Carries the game's grade into HDR and rolls highlights off smoothly toward the display Peak. Tuned with the RenoDRT Color Grade settings.",
        .labels = {"SDR", "Off", "HDR Luminance + SDR Blowout", "RenoDRT (Neutwo)"},
    },
    new renodx::utils::settings::Setting{
        .key = "tone_map_look",
        .binding = &shader_injection.tone_map_look,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = LOOK_AUTO,
        .label = "Look",
        .section = "Tone Map",
        .tooltip = "Auto: follows the installed shaders (Faithful Luma when detected, otherwise Vanilla).\n\nVanilla: the game's original look. Bright colors clip per channel, so they desaturate and shift hue as they did on an SDR display; the Saturation Clip, Hue Clip and Blowout settings set how much of that is kept in HDR.\n\nFaithful Luma: the Faithful Luma shaders' look. Bright colors keep their hue and only light sources whiten, with the highlight shoulder following the auto exposure as the shaders do.",
        .labels = {"Auto", "Vanilla", "Faithful Luma"},
    },
    new renodx::utils::settings::Setting{
        .key = "FlAuthoredHue",
        .binding = &shader_injection.fl_authored_hue,
        .default_value = 100.f,
        .label = "Authored Hue",
        .section = "Tone Map",
        .tooltip = "How far strongly lit colors keep the hue the game's per-channel clip gave them, which is the hue the levels were graded and approved through, rather than the scene's hue. Only light above display white is affected: a few degrees on sunlit saturated paint, nothing on whites, lamps or anything displayable.\n100 = as the Faithful Luma shaders, 0 = scene hue.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.01f; },
        .is_visible = []() { return shader_injection.tone_map_type > 0.f && IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "peak_white_nits",
        .binding = &shader_injection.peak_white_nits,
        .default_value = 1000.f,
        .can_reset = false,
        .label = "Peak",
        .section = "Tone Map",
        .tooltip = "Your display's peak brightness in nits; highlights roll off toward it. Read from the display when it reports one.",
        .min = 203.f,
        .max = 4000.f,
        .is_visible = []() { return shader_injection.tone_map_type >= 2.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "expected_peak_white_nits",
        .binding = &shader_injection.expected_white_nits,
        .default_value = 4000.f,
        .label = "Expected Peak",
        .section = "Tone Map",
        .tooltip = "Scene brightness in nits that lands on the display Peak. Lower values push more of the highlights to white.",
        .min = 1000.f,
        .max = 10000.f,
        .is_visible = []() { return shader_injection.tone_map_type == 2.f; },
    },

    // Blowout (vanilla look only) ///////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Vanilla+",
        .section = "Blowout",
        .group = "button-line-1",
        .tooltip = "Preset: keeps both the hue shift and the desaturation of the game's clipped highlights.",
        .on_change = []() { ApplyPreset(settings, P_BLOWOUT_HC_VANILLA); },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "No Hue Shift",
        .section = "Blowout",
        .group = "button-line-1",
        .tooltip = "Preset: keeps the desaturation of the game's clipped highlights but not their hue shift.",
        .on_change = []() { ApplyPreset(settings, P_BLOWOUT_HC_NOHUE); },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },

    new renodx::utils::settings::Setting{
        .key = "pblow_chue",
        .binding = &shader_injection.pblow_chue,
        .default_value = 0.76f,
        .label = "Hue Influence",
        .section = "Blowout",
        .tooltip = "How much of the hue shift the game's clipped highlights had is carried into the HDR picture. 0 = scene hue kept.",
        .max = 1.f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_csat",
        .binding = &shader_injection.pblow_csat,
        .default_value = 0.72f,
        .label = "Chrominance Influence",
        .section = "Blowout",
        .tooltip = "How much of the desaturation the game's clipped highlights had is carried into the HDR picture. 0 = scene saturation kept.",
        .max = 1.f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_satboost",
        .binding = &shader_injection.pblow_satboost,
        .default_value = 1.00f,
        .label = "Chrominance Boost",
        .section = "Blowout",
        .tooltip = "Restores some of the saturation the blowout removes. 1.0 = off.",
        .min = 1.f,
        .max = 1.1f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_guaranteed",
        .binding = &shader_injection.pblow_guaranteed,
        .default_value = 0.5f,
        .label = "Guaranteed",
        .section = "Blowout",
        .tooltip = "Forces the very brightest highlights to white whatever the settings above; higher whitens them sooner. 0 = off.",
        .min = 0.f,
        .max = 1.f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Gradual",
        .section = "Blowout",
        .group = "button-line-1",
        .tooltip = "Preset: highlights compress gradually into the blown-out look (Shoulder Start 0.8, Peak 1.25).",
        .on_change = []() { ApplyPreset(settings, P_BLOWOUT_T_GRADUAL); },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Brickwall",
        .section = "Blowout",
        .group = "button-line-1",
        .tooltip = "Preset: highlights clip hard at SDR white, exactly as the game did.",
        .on_change = []() { ApplyPreset(settings, P_BLOWOUT_T_BRICKWALL); },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_start",
        .binding = &shader_injection.pblow_start,
        .default_value = 0.8f,
        .label = "Shoulder Start",
        .section = "Blowout",
        .tooltip = "Brightness (1.0 = SDR white) above which highlights start compressing toward the Blowout Peak.",
        .max = 1.5f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_max",
        .binding = &shader_injection.pblow_max,
        .default_value = 1.25f,
        .label = "Peak",
        .section = "Blowout",
        .tooltip = "Brightness the compressed highlights level off at, which sets how blown out they look. Below Shoulder Start it becomes a hard clip.",
        .max = 3.0f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },

    // Vanilla Color Grade ///////////////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "vcg_exposure",
        .binding = &shader_injection.vcg_exposure,
        .default_value = 1.0f,
        .label = "Exposure",
        .section = "Vanilla Color Grade",
        .tooltip = "Multiplier on the scene's exposure before the game's grade. 1.0 = the game's auto exposure.",
        .max = 2.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "lut_colornwc",
        .binding = &shader_injection.vcg_colornwc,
        .default_value = 0.f,
        .label = "Highlights Saturation Restore",
        .section = "Vanilla Color Grade",
        .tooltip = "Vanilla look only. Compresses bright colors before the game's grade instead of clipping them, so they keep more of their saturation. 0 = vanilla clip.",
        .max = 2.f,
        .format = "%.3f",
        .is_enabled = []() { return !IsFaithfulLumaLook(); },
        .parse = [](float value) { return value + 1.0f; },
    },
    new renodx::utils::settings::Setting{
        .key = "vcg_other",
        .binding = &shader_injection.vcg_other,
        .default_value = 1.f,
        .label = "Other",
        .section = "Vanilla Color Grade",
        .tooltip = "Strength of the level's grade applied on top of the tone map: desaturation and overlay tints such as the red damage tint, plus shadows, midtones and highlights for the Vanilla look. 1.0 = vanilla.",
        .max = 1.f,
        .format = "%.3f",
    },
    new renodx::utils::settings::Setting{
        .key = "lut",
        .binding = &shader_injection.vcg_lut,
        .default_value = 1.f,
        .label = "LUT",
        .section = "Vanilla Color Grade",
        .tooltip = "Strength of the game's per-level color curves. 1.0 = vanilla.",
        .max = 1.f,
        .format = "%.3f",
    },

    // HDR Luminance Color Grade (HDR Luminance type) ///////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "cg_middle",
        .binding = &shader_injection.cg_middle,
        .default_value = 1.0f,
        .label = "Middle Gray",
        .section = "HDR Luminance Color Grade",
        .tooltip = "Pivot for the Contrast, Shadows and Highlights sliders below. 1.0 = the game's middle gray.",
        .max = 4.0f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "cg_contrast",
        .binding = &shader_injection.cg_contrast,
        .default_value = 1.0f,
        .label = "Contrast",
        .section = "HDR Luminance Color Grade",
        .tooltip = "Stretches shadows and highlights away from Middle Gray. 1.0 = off.",
        .max = 2.0f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "cg_shadows",
        .binding = &shader_injection.cg_shadows,
        .default_value = 1.0f,
        .label = "Shadows",
        .section = "HDR Luminance Color Grade",
        .tooltip = "Deepens or lifts everything below Middle Gray. 1.0 = off.",
        .max = 2.0f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "cg_highlights",
        .binding = &shader_injection.cg_highlights,
        .default_value = 1.0f,
        .label = "Highlights",
        .section = "HDR Luminance Color Grade",
        .tooltip = "Brightens or compresses everything above Middle Gray. 1.0 = off.",
        .max = 2.0f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type == 2.f; },
    },

    // RenoDRT Color Grade (RenoDRT type) ////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "ColorGradeExposure",
        .binding = &shader_injection.tone_map_exposure,
        .default_value = 1.f,
        .label = "Exposure",
        .section = "RenoDRT Color Grade",
        .tooltip = "Overall brightness of the scene before tone mapping. 1.0 = off.",
        .max = 2.f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeHighlights",
        .binding = &shader_injection.tone_map_highlights,
        .default_value = 50.f,
        .label = "Highlights",
        .section = "RenoDRT Color Grade",
        .tooltip = "Brightness of the highlights. 50 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeShadows",
        .binding = &shader_injection.tone_map_shadows,
        .default_value = 50.f,
        .label = "Shadows",
        .section = "RenoDRT Color Grade",
        .tooltip = "Brightness of the shadows. 50 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeContrast",
        .binding = &shader_injection.tone_map_contrast,
        .default_value = 50.f,
        .label = "Contrast",
        .section = "RenoDRT Color Grade",
        .tooltip = "Overall contrast. 50 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeSaturation",
        .binding = &shader_injection.tone_map_saturation,
        .default_value = 50.f,
        .label = "Saturation",
        .section = "RenoDRT Color Grade",
        .tooltip = "Overall color saturation. 50 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeHighlightSaturation",
        .binding = &shader_injection.tone_map_highlight_saturation,
        .default_value = 50.f,
        .label = "Highlight Saturation",
        .section = "RenoDRT Color Grade",
        .tooltip = "Saturation of bright lights and highlights. 50 = keeps their color; lower whitens them the way the game's clip did, higher adds color.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeBlowout",
        .binding = &shader_injection.tone_map_blowout,
        .default_value = 0.f,
        .label = "Blowout",
        .section = "RenoDRT Color Grade",
        .tooltip = "Whitens highlights as they approach the display Peak, like an overexposed camera. 0 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.01f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeFlare",
        .binding = &shader_injection.tone_map_flare,
        .default_value = 0.f,
        .label = "Flare",
        .section = "RenoDRT Color Grade",
        .tooltip = "Lifts the deepest shadows to compensate for a display's flare or glare. 0 = off.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.02f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "FxSaturationClip",
        .binding = &shader_injection.custom_saturation_clip,
        .default_value = 50.f,
        .label = "Saturation Clip",
        .section = "RenoDRT Color Grade",
        .tooltip = "Vanilla look only. Reproduces the desaturation the game's per-channel clip gave bright colors. 100 = vanilla, 0 = full color kept.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.01f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "FxHueClip",
        .binding = &shader_injection.custom_hue_clip,
        .default_value = 50.f,
        .label = "Hue Clip",
        .section = "RenoDRT Color Grade",
        .tooltip = "Vanilla look only. Reproduces the hue shift the game's per-channel clip gave bright colors. 100 = vanilla, 0 = scene hue kept.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.01f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "ColorGradeScene",
        .binding = &shader_injection.color_grade_strength,
        .default_value = 100.f,
        .label = "Scene Grading",
        .section = "RenoDRT Color Grade",
        .tooltip = "Strength of the game's color grading carried into HDR (level shadows, midtones and color curves). 100 = vanilla.",
        .max = 100.f,
        .parse = [](float value) { return value * 0.01f; },
        .is_visible = []() { return shader_injection.tone_map_type == 3.f; },
    },

    // Fake Wide Color Gamut /////////////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "fakewcg_strength",
        .binding = &shader_injection.fakewcgcorrect_gamma,
        .default_value = 0.f,
        .label = "Strength",
        .section = "Fake Wide Color Gamut",
        .tooltip = "Expands the game's colors beyond their native BT.709 gamut for a wider-color look. 0 = off.",
        .min = 0.f,
        .max = 1.0f,
        .format = "%.3f",
        .parse = [](float value) { return value == 0.f ? 0.f : value + 1.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "fakewcgcorrect_chroma",
        .binding = &shader_injection.fakewcgcorrect_chroma,
        .default_value = 0.0f,
        .label = "Correct Chroma",
        .section = "Fake Wide Color Gamut",
        .tooltip = "Pulls the expanded colors' saturation back toward the original. 1.0 = fully corrected.",
        .min = 0.f,
        .max = 1.f,
        .format = "%.3f",
        .is_enabled = []() { return shader_injection.fakewcgcorrect_gamma > 0.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "fakewcgcorrect_luma",
        .binding = &shader_injection.fakewcgcorrect_luma,
        .default_value = 0.8f,
        .label = "Correct Luma",
        .section = "Fake Wide Color Gamut",
        .tooltip = "Keeps the expanded colors' brightness at the original. 0 = uncorrected.",
        .min = 0.f,
        .max = 0.9f,
        .format = "%.3f",
        .is_enabled = []() { return shader_injection.fakewcgcorrect_gamma > 0.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "fakewcgcorrect_sat",
        .binding = &shader_injection.fakewcgcorrect_sat,
        .default_value = 1.005f,
        .label = "Saturation",
        .section = "Fake Wide Color Gamut",
        .tooltip = "Saturation multiplier applied after the expansion. 1.0 = off.",
        .min = 0.5f,
        .max = 1.5f,
        .format = "%.3f",
        .is_enabled = []() { return shader_injection.fakewcgcorrect_gamma > 0.f; },
    },

    // Effects ///////////////////////////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "exposure_model",
        .binding = &shader_injection.exposure_model,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = EXPOSURE_FAITHFUL_LUMA,
        .label = "Auto Exposure",
        .section = "Effects",
        .tooltip = "Auto: follows the installed shaders (Faithful Luma when detected, otherwise Vanilla).\n\nVanilla: the game's adaptation as shipped. It settles short of its target by an amount that depends on frame rate and on the previous scene, so the same place can end up brighter or darker on different visits.\n\nFaithful Luma: the same metering and per-level range, adapting at a fixed rate in stops per second, faster into light than into dark, and settling in well under a second, the same way every time. Works with the game's original shaders too.",
        .labels = {"Auto", "Vanilla", "Faithful Luma"},
    },
    new renodx::utils::settings::Setting{
        .key = "bloom_model",
        .binding = &shader_injection.bloom_model,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = BLOOM_AUTO,
        .label = "Bloom Extraction",
        .section = "Effects",
        .tooltip = "Auto: follows the installed shaders (Faithful Luma when detected, otherwise Vanilla).\n\nVanilla: anything with a single color channel over white blooms, so bright surfaces haze and saturated paint glows.\n\nFaithful Luma: only light above display white blooms, in its own color, so light sources glow and bright paint does not.",
        .labels = {"Auto", "Vanilla", "Faithful Luma"},
    },
    new renodx::utils::settings::Setting{
        .key = "c_bloom",
        .binding = &shader_injection.c_bloom,
        .default_value = 1.0f,
        .label = "Bloom",
        .section = "Effects",
        .tooltip = "Bloom strength. 1.0 = vanilla.",
        .min = 0.0f,
        .max = 2.0f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_speedlines",
        .binding = &shader_injection.c_speedlines,
        .default_value = 1.f,
        .label = "Speed Lines",
        .section = "Effects",
        .tooltip = "Strength of the screen-edge speed lines. 1.0 = vanilla, 0 = off.",
        .min = 0.f,
        .max = 1.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_sky",
        .binding = &shader_injection.c_sky,
        .default_value = 1.f,
        .label = "Sky",
        .section = "Effects",
        .tooltip = "Brightness of the sky in HDR. 1.0 = vanilla.",
        .min = 0.5f,
        .max = 2.f,
        .format = "%.2f",
    },

    // World Flares ////////////////////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "c_worldflare",
        .binding = &shader_injection.c_worldflare,
        .default_value = 1.f,
        .label = "Strength",
        .section = "World Flares",
        .tooltip = "Brightness of the sun reflections on glass and metal. 1.0 = vanilla, 0 = off.",
        .min = 0.f,
        .max = 2.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_worldflare_addblur",
        .binding = &shader_injection.c_worldflare_addblur,
        .default_value = 0.f,
        .label = "HDR Shaping",
        .section = "World Flares",
        .tooltip = "Reshapes the reflections for HDR: a brighter core that falls off toward the edge, with a glow of this strength. 0 = vanilla.",
        .min = 0.f,
        .max = 2.f,
        .format = "%.2f",
    },

    // Sun //////////////////////////////////////////////////////////////////////////////////////
    new renodx::utils::settings::Setting{
        .key = "c_sunglare",
        .binding = &shader_injection.c_sunglare,
        .default_value = 1.f,
        .label = "Glare",
        .section = "Sun",
        .tooltip = "Brightness of the sun's glare in HDR. 1.0 = vanilla; boosting it also brings back some of the glare's color.",
        .min = 0.f,
        .max = 6.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_sunsize",
        .binding = &shader_injection.c_sunsize,
        .default_value = 0.f,
        .label = "Sun Disc",
        .section = "Sun",
        .tooltip = "Adds a bright HDR sun disc of this size at the center of the glare. 0 = off.",
        .min = 0.f,
        .max = 2.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_sunlens",
        .binding = &shader_injection.c_sunlens,
        .default_value = 1.f,
        .label = "Lens Flare",
        .section = "Sun",
        .tooltip = "Strength of the sun's lens flare in HDR. 1.0 = vanilla, 0 = off.",
        .min = 0.f,
        .max = 3.f,
        .format = "%.3f",
    },

};

void OnPresetOff() {
  renodx::utils::settings::UpdateSettings({
      {"tone_map_type", 0.f},
      {"tone_map_look", LOOK_AUTO},
      {"exposure_model", EXPOSURE_AUTO},
      {"bloom_model", BLOOM_AUTO},
      {"diffuse_white_nits", 203.f},
      {"graphics_white_nits", 203.f},
      {"c_mov", 203.f},
      {"vcg_exposure", 1.f},
      {"lut_colornwc", 0.f},
      {"vcg_other", 1.f},
      {"lut", 1.f},
      {"cg_middle", 1.f},
      {"cg_contrast", 1.f},
      {"cg_shadows", 1.f},
      {"cg_highlights", 1.f},
      {"ColorGradeExposure", 1.f},
      {"ColorGradeHighlights", 50.f},
      {"ColorGradeShadows", 50.f},
      {"ColorGradeContrast", 50.f},
      {"ColorGradeSaturation", 50.f},
      {"ColorGradeHighlightSaturation", 50.f},
      {"ColorGradeBlowout", 0.f},
      {"ColorGradeFlare", 0.f},
      {"ColorGradeScene", 100.f},
      {"FxSaturationClip", 100.f},
      {"FxHueClip", 100.f},
      {"FlAuthoredHue", 100.f},
      {"fakewcg_strength", 0.f},
      {"c_bloom", 1.f},
      {"c_speedlines", 1.f},
      {"c_sky", 1.f},
      {"c_worldflare", 1.f},
      {"c_worldflare_addblur", 0.f},
      {"c_sunglare", 1.f},
      {"c_sunsize", 0.f},
      {"c_sunlens", 1.f},
  });
}

bool fired_on_init_swapchain = false;

// The game's D3D9 swapchain fires first; only the DXGI proxy swapchain knows the display peak.
void OnInitSwapchain(reshade::api::swapchain* swapchain, bool resize) {
  if (fired_on_init_swapchain) return;
  if (!renodx::utils::swapchain::IsDXGI(swapchain)) return;

  const float peak = renodx::utils::swapchain::GetPeakNits(swapchain).value_or(1000.f);
  for (auto* setting : settings) {
    if (setting->binding != &shader_injection.peak_white_nits) continue;
    setting->default_value = peak;
    setting->can_reset = true;
  }

  fired_on_init_swapchain = true;
}

// Registered before mods::shader, so the hash is computed on the game's original bytecode.
bool OnCreatePipeline(
    reshade::api::device* device,
    reshade::api::pipeline_layout layout,
    uint32_t subobject_count,
    const reshade::api::pipeline_subobject* subobjects) {
  if (shader_injection.faithful_luma_detected != 0.f) return false;
  for (uint32_t i = 0; i < subobject_count; ++i) {
    if (subobjects[i].type != reshade::api::pipeline_subobject_type::pixel_shader) continue;
    const auto* desc = static_cast<const reshade::api::shader_desc*>(subobjects[i].data);
    if (desc == nullptr || desc->code == nullptr || desc->code_size == 0) continue;
    const auto hash = renodx::utils::hash::ComputeCRC32(static_cast<const uint8_t*>(desc->code), desc->code_size);
    if (!FAITHFUL_LUMA_SHADER_HASHES.contains(hash)) continue;
    shader_injection.faithful_luma_detected = 1.f;
    reshade::log::message(reshade::log::level::info, "Faithful Luma shaders detected.");
    break;
  }
  return false;
}

bool initialized = false;

}  // namespace

extern "C" __declspec(dllexport) constexpr const char* NAME = "RenoDX";
extern "C" __declspec(dllexport) constexpr const char* DESCRIPTION = "RenoDX (Mirror's Edge)";

BOOL APIENTRY DllMain(HMODULE h_module, DWORD fdw_reason, LPVOID lpv_reserved) {
  switch (fdw_reason) {
    case DLL_PROCESS_ATTACH:
      if (!reshade::register_addon(h_module)) return FALSE;

      if (!initialized) {
        renodx::mods::shader::expected_constant_buffer_space = 50;
        renodx::mods::shader::expected_constant_buffer_index = CBUFFER;
        renodx::mods::shader::constant_buffer_offset = 50 * 4;  // SM3 injection at c50, see shared.h

        renodx::mods::swapchain::expected_constant_buffer_index = CBUFFER;
        renodx::mods::swapchain::expected_constant_buffer_space = 50;
        renodx::mods::swapchain::use_resource_cloning = true;
        renodx::mods::swapchain::use_device_proxy = true;
        renodx::mods::swapchain::set_color_space = false;
        renodx::mods::swapchain::ignored_window_class_names = {
            "SplashScreenClass",  // UE3 splash screen
        };

        renodx::mods::swapchain::swap_chain_proxy_shaders = {
            {
                reshade::api::device_api::d3d11,
                {
                    .vertex_shader = __swap_chain_proxy_vertex_shader_dx11,
                    .pixel_shader = __swap_chain_proxy_pixel_shader_dx11,
                },
            },
        };

        renodx::mods::swapchain::resource_upgrade_infos.push_back({
            // scene color / LDR targets
            .old_format = reshade::api::format::b8g8r8a8_unorm,
            .new_format = reshade::api::format::r16g16b16a16_float,
            .ignore_size = true,
            .use_resource_view_cloning = false,
            .usage_include = reshade::api::resource_usage::render_target,
        });
        renodx::mods::swapchain::resource_upgrade_infos.push_back({
            // specular gbuffer, pixelated otherwise
            .old_format = reshade::api::format::r8g8b8a8_unorm,
            .new_format = reshade::api::format::r16g16b16a16_unorm,
            .ignore_size = true,
            .use_resource_view_cloning = false,
            .usage_include = reshade::api::resource_usage::render_target,
        });
        renodx::mods::swapchain::resource_upgrade_infos.push_back({
            // bloom filter buffers and exposure chain
            .old_format = reshade::api::format::r16g16b16a16_unorm,
            .new_format = reshade::api::format::r16g16b16a16_float,
            .ignore_size = true,
            .use_resource_view_cloning = false,
            .usage_include = reshade::api::resource_usage::render_target,
        });

        {
          auto* setting = new renodx::utils::settings::Setting{
              .key = "SwapChainEncoding",
              .value_type = renodx::utils::settings::SettingValueType::INTEGER,
              .default_value = 1.f,
              .label = "Output",
              .section = "Display Output (Restart Req.)",
              .tooltip = "HDR10: 10-bit output. Lighter on performance and more widely compatible; may show slight banding.\nscRGB: 16-bit output, best quality (default).",
              .labels = {"HDR10", "scRGB"},
              .is_global = true,
          };
          renodx::utils::settings::LoadSetting(renodx::utils::settings::global_name, setting);
          const bool is_hdr10 = setting->GetValue() == 0.f;
          shader_injection.swap_chain_encoding = is_hdr10 ? 4.f : 5.f;              // renodx::draw::ENCODING_PQ : ENCODING_SCRGB
          shader_injection.swap_chain_encoding_color_space = is_hdr10 ? 1.f : 0.f;  // COLOR_SPACE_BT2020 : COLOR_SPACE_BT709
          renodx::mods::swapchain::SetUseHDR10(is_hdr10);
          settings.push_back(setting);
        }

        {
          auto* setting = new renodx::utils::settings::Setting{
              .key = "SwapChainForceBorderless",
              .value_type = renodx::utils::settings::SettingValueType::INTEGER,
              .default_value = 0.f,
              .label = "Force Borderless",
              .section = "Display Output (Restart Req.)",
              .tooltip = "Runs the game's fullscreen mode as a borderless window, which HDR needs on most systems.",
              .labels = {
                  "Disabled",
                  "Enabled",
              },
              .on_change_value = [](float previous, float current) { renodx::mods::swapchain::force_borderless = (current == 1.f); },
              .is_global = true,
          };
          renodx::utils::settings::LoadSetting(renodx::utils::settings::global_name, setting);
          renodx::mods::swapchain::force_borderless = (setting->GetValue() == 1.f);
          settings.push_back(setting);
        }

        {
          auto* setting = new renodx::utils::settings::Setting{
              .key = "SwapChainPreventFullscreen",
              .value_type = renodx::utils::settings::SettingValueType::INTEGER,
              .default_value = 1.f,
              .label = "Prevent Fullscreen",
              .section = "Display Output (Restart Req.)",
              .tooltip = "Blocks exclusive fullscreen, which HDR needs on most systems.",
              .labels = {
                  "Disabled",
                  "Enabled",
              },
              .on_change_value = [](float previous, float current) { renodx::mods::swapchain::prevent_full_screen = (current == 1.f); },
              .is_global = true,
          };
          renodx::utils::settings::LoadSetting(renodx::utils::settings::global_name, setting);
          renodx::mods::swapchain::prevent_full_screen = (setting->GetValue() == 1.f);
          settings.push_back(setting);
        }

        {
          auto* setting = new renodx::utils::settings::Setting{
              .key = "SwapChainDeviceProxyBaseWaitIdle",
              .value_type = renodx::utils::settings::SettingValueType::INTEGER,
              .default_value = 0.f,
              .label = "Base Wait Idle",
              .section = "Display Proxy (Restart Req.)",
              .tooltip = "Makes the game's own swap chain wait for the GPU to finish before presenting. Try it if you see flicker or tearing.",
              .labels = {"Off", "On"},
              .is_global = true,
          };
          renodx::utils::settings::LoadSetting(renodx::utils::settings::global_name, setting);
          renodx::mods::swapchain::device_proxy_wait_idle_source = (setting->GetValue() == 1.f);
          settings.push_back(setting);
        }
        {
          auto* setting = new renodx::utils::settings::Setting{
              .key = "SwapChainDeviceProxyProxyWaitIdle",
              .value_type = renodx::utils::settings::SettingValueType::INTEGER,
              .default_value = 0.f,
              .label = "Proxy Wait Idle",
              .section = "Display Proxy (Restart Req.)",
              .tooltip = "Makes the mod's HDR swap chain wait for the GPU to finish before presenting. Try it if you see flicker or tearing.",
              .labels = {"Off", "On"},
              .is_global = true,
          };
          renodx::utils::settings::LoadSetting(renodx::utils::settings::global_name, setting);
          renodx::mods::swapchain::device_proxy_wait_idle_destination = (setting->GetValue() == 1.f);
          settings.push_back(setting);
        }

        {
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "Original Mod: XgarhontX",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "Update (fixes, Faithful Luma support): softsoundd",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "RenoDX: clshortfuse",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "shared.h Reference: Steve161803",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "Coding Help: Pumbo",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "Coding Help: Musa",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BULLET,
              .label = "Bug Hunter: Strale",
              .section = "Credits",
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BUTTON,
              .label = "RenoDX Discord",
              .section = "Credits",
              .group = "button-line-1",
              .tint = 0x5865F2,
              .on_change = []() {
                renodx::utils::platform::LaunchURL("https://discord.gg/", "F6AUTeWJHM");
              },
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BUTTON,
              .label = "HDRDen Discord",
              .section = "Credits",
              .group = "button-line-1",
              .tint = 0x5865F2,
              .on_change = []() {
                renodx::utils::platform::LaunchURL("https://discord.gg/", "5WZXDpmbpP");
              },
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::BUTTON,
              .label = "More Mods",
              .section = "Credits",
              .group = "button-line-1",
              .tint = 0x2B3137,
              .on_change = []() {
                renodx::utils::platform::LaunchURL("https://github.com/clshortfuse/renodx/wiki/Mods");
              },
          });
          settings.push_back(new renodx::utils::settings::Setting{
              .value_type = renodx::utils::settings::SettingValueType::TEXT,
              .label = std::string("Build: ") + renodx::utils::date::ISO_DATE_TIME,
              .section = "Credits",
          });
        }

        reshade::register_event<reshade::addon_event::create_pipeline>(OnCreatePipeline);
        reshade::register_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);

        initialized = true;
      }

      break;
    case DLL_PROCESS_DETACH:
      reshade::unregister_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);
      reshade::unregister_event<reshade::addon_event::create_pipeline>(OnCreatePipeline);
      reshade::unregister_addon(h_module);
      break;
  }

  renodx::utils::settings::Use(fdw_reason, &settings, &OnPresetOff);
  renodx::mods::swapchain::Use(fdw_reason, &shader_injection);
  renodx::mods::shader::Use(fdw_reason, custom_shaders, &shader_injection);

  return TRUE;
}
