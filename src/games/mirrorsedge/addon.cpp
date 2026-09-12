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
// shader/faithfulluma/ share the vanilla register layout.
const std::unordered_set<uint32_t> FAITHFUL_LUMA_SHADER_HASHES = {
    0x09C4EF79,  // TdToneMappingPixelShader
    0xC7C7E0A5,  // TdToneMapExposurePixelShader
    0x476CD0BA,  // DOFAndBloomGatherPixelShader (16 samples)
    0x79B1C315,  // DOFAndBloomGatherPixelShader (4 samples)
    0xB2EC74D6,  // DOFAndBloomBlendPixelShader
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

// XgarhontX's original creative defaults.
const std::unordered_map<std::string, float> P_HDR_LOOK = {
    {"fakewcg_strength", 0.5f},
    {"fakewcgcorrect_chroma", 0.f},
    {"fakewcgcorrect_luma", 0.8f},
    {"fakewcgcorrect_sat", 1.005f},
    {"c_speedlines", 0.4f},
    {"c_sunglare", 3.8f},
    {"c_sunsize", 1.f},
    {"c_sunlens", 1.f},
    {"c_worldflare", 1.f},
    {"c_worldflare_addblur", 1.f},
    {"c_sky", 1.25f},
    {"bloom_model", BLOOM_SOFT_LEGACY},
    {"c_bloom", 1.f},
    {"c_bloom_contrast", 1.f},
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
        .group = "button-line-1",
        .tooltip = "Vanilla-matching defaults.",
        .on_change = []() {
          for (auto* setting : settings) {
            if (setting->key.empty()) continue;
            if (!setting->can_reset) continue;
            renodx::utils::settings::UpdateSetting(setting->key, setting->default_value);
          }
          renodx::utils::settings::SaveSettings(renodx::utils::settings::global_name + "-preset" + std::to_string(renodx::utils::settings::preset_index));
        },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "HDR Look",
        .section = "Presets",
        .group = "button-line-1",
        .tooltip = "Fake wide gamut, boosted sun glare with a sun disc, shaped world flares, brighter sky, soft bloom, subdued speed lines.",
        .on_change = []() {
          ApplyPreset(settings, P_HDR_LOOK);
        },
    },

    // Brightness //////////////////////////////////////////////////////////////////////////////////////
    new renodx::utils::settings::Setting{
        .key = "diffuse_white_nits",
        .binding = &shader_injection.diffuse_white_nits,
        .default_value = 203.f,
        .label = "Game",
        .section = "Brightness",
        .tooltip = "Sets the value of 100% white in nits.",
        .min = 1.f,
        .max = 500.f,
    },
    new renodx::utils::settings::Setting{
        .key = "graphics_white_nits",
        .binding = &shader_injection.graphics_white_nits,
        .default_value = 203.f,
        .label = "UI",
        .section = "Brightness",
        .tooltip = "Sets the brightness of UI and HUD elements in nits.",
        .min = 1.f,
        .max = 500.f,
    },
    new renodx::utils::settings::Setting{
        .key = "c_mov",
        .binding = &shader_injection.c_mov,
        .default_value = 203.f,
        .label = "Movies",
        .section = "Brightness",
        .tooltip = "Sets the brightness of Bink videos (intro, loading movies) in nits.",
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
        .tooltip = "Emulates an SDR display EOTF for game and UI output.\nThe in-game Brightness slider still sets the game's own gamma (2.0 at the middle position).",
        .labels = {"Off", "2.2", "BT.1886"},
    },

    // Tone Map //////////////////////////////////////////////////////////////////////////////////////
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BULLET,
        .label = "Faithful Luma shaders: detected.",
        .section = "Tone Map",
        .is_visible = []() { return shader_injection.faithful_luma_detected != 0.f; },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BULLET,
        .label = "Faithful Luma shaders: not detected (vanilla shaders in use).",
        .section = "Tone Map",
        .is_visible = []() { return shader_injection.faithful_luma_detected == 0.f; },
    },
    new renodx::utils::settings::Setting{
        .key = "tone_map_type",
        .binding = &shader_injection.tone_map_type,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 2.f,
        .label = "Type",
        .section = "Tone Map",
        .tooltip = "SDR*: Tonemap is clamped just like SDR, *but some other shaders for scene rendering may still take effect.\n\nOff (Debug): No tonemapping, with maximum chrominance.\n\nHDR Luminance w/ SDR Per-Channel Blowout: Superimpose a low peak tonemap for hue shifted blowouts, then do luminance scaled HDR tonemap (Hermite Spline).",
        .labels = {"SDR*", "Off", "HDR Luminance w/ SDR Per-Channel Blowout"},
    },
    new renodx::utils::settings::Setting{
        .key = "tone_map_look",
        .binding = &shader_injection.tone_map_look,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = LOOK_AUTO,
        .label = "Look",
        .section = "Tone Map",
        .tooltip = "Auto: Faithful Luma when its shaders are detected, otherwise Vanilla.\n\nVanilla: per-channel grade with SDR blowout emulation.\n\nFaithful Luma: luminance-anchored Reinhard, hue-stable highlights, blended per-channel/neutral midtone grade, selective white neutralization.",
        .labels = {"Auto", "Vanilla", "Faithful Luma"},
    },
    new renodx::utils::settings::Setting{
        .key = "fl_black_floor",
        .binding = &shader_injection.fl_black_floor,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = 0.f,
        .label = "Black Floor Rolloff",
        .section = "Tone Map",
        .tooltip = "Faithful Luma's near-black rolloff (2.5/255 -> 0, unchanged above 16/255).\nThe mod's shaders do not have the vanilla #020202 floor this was written for, so it is off by default.",
        .labels = {"Off", "On"},
        .is_visible = []() { return IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "peak_white_nits",
        .binding = &shader_injection.peak_white_nits,
        .default_value = 1000.f,
        .can_reset = false,
        .label = "Peak",
        .section = "Tone Map",
        .tooltip = "Maximum luminance output to display.",
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
        .tooltip = "Expected max of HDR luminance.\nLower to white clip.",
        .min = 1000.f,
        .max = 10000.f,
        .is_visible = []() { return shader_injection.tone_map_type >= 2.f; },
    },

    // Blowout (vanilla look only) ///////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Vanilla+",
        .section = "Blowout",
        .group = "button-line-1",
        .on_change = []() {
          ApplyPreset(settings, P_BLOWOUT_HC_VANILLA);
        },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "No Hue Shift",
        .section = "Blowout",
        .group = "button-line-1",
        .on_change = []() {
          ApplyPreset(settings, P_BLOWOUT_HC_NOHUE);
        },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },

    new renodx::utils::settings::Setting{
        .key = "pblow_chue",
        .binding = &shader_injection.pblow_chue,
        .default_value = 0.76f,
        .label = "Hue Influence",
        .section = "Blowout",
        .tooltip = "Hue shift of blownout color's influence on HDR color.",
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
        .tooltip = "Chrominance/Saturation of blownout color's influence on HDR color.",
        .max = 1.f,
        .format = "%.2f",
        .is_visible = []() { return shader_injection.tone_map_type >= 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_satboost",
        .binding = &shader_injection.pblow_satboost,
        .default_value = 1.00f,
        .label = "Chrominance Boost",
        .section = "Blowout",
        .tooltip = "Boost to counteract chrominance lost to the blowout.",
        .min = 1.f,
        .max = 1.1f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type >= 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_guaranteed",
        .binding = &shader_injection.pblow_guaranteed,
        .default_value = 0.5f,
        .label = "Guaranteed",
        .section = "Blowout",
        .tooltip = "Blowout the most extreme of highlights.",
        .min = 0.f,
        .max = 1.f,
        .format = "%.3f",
        .is_visible = []() { return shader_injection.tone_map_type >= 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Gradual",
        .section = "Blowout",
        .group = "button-line-1",
        .on_change = []() {
          ApplyPreset(settings, P_BLOWOUT_T_GRADUAL);
        },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .value_type = renodx::utils::settings::SettingValueType::BUTTON,
        .label = "Brickwall",
        .section = "Blowout",
        .group = "button-line-1",
        .on_change = []() {
          ApplyPreset(settings, P_BLOWOUT_T_BRICKWALL);
        },
        .is_visible = []() { return shader_injection.tone_map_type == 2 && !IsFaithfulLumaLook(); },
    },
    new renodx::utils::settings::Setting{
        .key = "pblow_start",
        .binding = &shader_injection.pblow_start,
        .default_value = 0.8f,
        .label = "Shoulder Start",
        .section = "Blowout",
        .tooltip = "The threshold before the low peak tonemapper engages.",
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
        .tooltip = "The peak of the low peak tonemapper.",
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
        .tooltip = "Exposure for raw HDR input color.",
        .max = 2.f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "lut_colornwc",
        .binding = &shader_injection.vcg_colornwc,
        .default_value = 1.5f,
        .label = "Highlights Saturation Restore",
        .section = "Vanilla Color Grade",
        .tooltip = "Roll off the color passed to color grading and LUT, restoring highlights saturation.\nSet 0 for Brickwall like Vanilla.\nNot used by the Faithful Luma look.",
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
        .tooltip = "Scene shadows, highlights, midtones, desaturation and overlay tint.",
        .max = 1.f,
        .format = "%.3f",
    },
    new renodx::utils::settings::Setting{
        .key = "lut",
        .binding = &shader_injection.vcg_lut,
        .default_value = 1.f,
        .label = "LUT",
        .section = "Vanilla Color Grade",
        .tooltip = "Color grade from LUT curves.",
        .max = 1.f,
        .format = "%.3f",
    },

    // RenoDX Luminance Color Grade //////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "cg_middle",
        .binding = &shader_injection.cg_middle,
        .default_value = 1.0f,
        .label = "Middle Gray",
        .section = "RenoDX Luminance Color Grade",
        .tooltip = "The middle point for RenoDX's luma based color grade.",
        .max = 4.0f,
        .format = "%.3f",
    },
    new renodx::utils::settings::Setting{
        .key = "cg_contrast",
        .binding = &shader_injection.cg_contrast,
        .default_value = 1.0f,
        .label = "Contrast",
        .section = "RenoDX Luminance Color Grade",
        .tooltip = "Both shadows and highlights stretching by luminance.",
        .max = 2.0f,
        .format = "%.3f",
    },
    new renodx::utils::settings::Setting{
        .key = "cg_shadows",
        .binding = &shader_injection.cg_shadows,
        .default_value = 1.0f,
        .label = "Shadows",
        .section = "RenoDX Luminance Color Grade",
        .tooltip = "Shadow stretching by luminance.",
        .max = 2.0f,
        .format = "%.3f",
    },
    new renodx::utils::settings::Setting{
        .key = "cg_highlights",
        .binding = &shader_injection.cg_highlights,
        .default_value = 1.0f,
        .label = "Highlights",
        .section = "RenoDX Luminance Color Grade",
        .tooltip = "Highlight stretching by luminance.",
        .max = 2.0f,
        .format = "%.3f",
    },

    // Fake Wide Color Gamut /////////////////////////////////////////////////////////////////////////

    new renodx::utils::settings::Setting{
        .key = "fakewcg_strength",
        .binding = &shader_injection.fakewcgcorrect_gamma,
        .default_value = 0.f,
        .label = "Strength",
        .section = "Fake Wide Color Gamut",
        .tooltip = "Gamma gamut expansion strength. 0 = off.",
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
        .tooltip = "Correct saturation boost's chroma to original.",
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
        .tooltip = "Correct saturation boost's luma to original.",
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
        .tooltip = "Simple saturation multiplier.",
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
        .default_value = EXPOSURE_AUTO,
        .label = "Auto Exposure",
        .section = "Effects",
        .tooltip = "Auto: Faithful Luma when its shaders are detected, otherwise Vanilla.\n\nVanilla: square-root key, frame-rate dependent adaptation.\n\nFaithful Luma: linear key, Rec.709 luminance, frame-rate independent asymmetric adaptation, dark-scene boost.",
        .labels = {"Auto", "Vanilla", "Faithful Luma"},
    },
    new renodx::utils::settings::Setting{
        .key = "fl_dark_boost",
        .binding = &shader_injection.fl_dark_boost,
        .default_value = 0.f,
        .label = "Dark Scene Boost",
        .section = "Effects",
        .tooltip = "Faithful Luma exposure: maximum extra exposure above the level's ExposureHigh clamp in dark scenes. 0 = respect the level's clamp (Faithful Luma ships with 1.0).",
        .min = 0.f,
        .max = 1.f,
        .format = "%.2f",
        .is_visible = []() {
          if (shader_injection.exposure_model == EXPOSURE_FAITHFUL_LUMA) return true;
          return shader_injection.exposure_model == EXPOSURE_AUTO && shader_injection.faithful_luma_detected != 0.f;
        },
    },
    new renodx::utils::settings::Setting{
        .key = "bloom_model",
        .binding = &shader_injection.bloom_model,
        .value_type = renodx::utils::settings::SettingValueType::INTEGER,
        .default_value = BLOOM_AUTO,
        .label = "Bloom Extraction",
        .section = "Effects",
        .tooltip = "Auto: Faithful Luma when its shaders are detected, otherwise Vanilla.\n\nVanilla: blooms when any channel exceeds 1.0.\n\nFaithful Luma: Rec.709 luminance soft knee with a bloom core.\n\nSoft (Legacy): ungated bloom shaped by a contrast curve.",
        .labels = {"Auto", "Vanilla", "Faithful Luma", "Soft (Legacy)"},
    },
    new renodx::utils::settings::Setting{
        .key = "c_bloom",
        .binding = &shader_injection.c_bloom,
        .default_value = 1.0f,
        .label = "Bloom",
        .section = "Effects",
        .min = 0.0f,
        .max = 2.0f,
        .format = "%.2f",
    },
    new renodx::utils::settings::Setting{
        .key = "c_bloom_contrast",
        .binding = &shader_injection.c_bloom_contrast,
        .default_value = 1.f,
        .label = "Bloom Contrast",
        .section = "Effects",
        .tooltip = "Soft (Legacy) bloom only.",
        .min = 0.8f,
        .max = 1.2f,
        .format = "%.3f",
        .is_enabled = []() { return shader_injection.bloom_model == BLOOM_SOFT_LEGACY; },
    },
    new renodx::utils::settings::Setting{
        .key = "c_speedlines",
        .binding = &shader_injection.c_speedlines,
        .default_value = 1.f,
        .label = "Speed Lines",
        .section = "Effects",
        .tooltip = "Screen edge speed lines strength. 1.0 = vanilla.",
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
        .tooltip = "Sky material brightness. 1.0 = vanilla.",
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
        .tooltip = "Billboard flares that simulate sun reflections on glass. 1.0 = vanilla.",
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
        .tooltip = "Above 0 enables the shaped HDR flare: extra gain, radial falloff and a bloom-like center glow of this strength. 0 = vanilla shape.",
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
        .tooltip = "Brightness of sun glare. 1.0 = vanilla; saturation is restored progressively as the glare is boosted.",
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
        .tooltip = "Size of a synthetic HDR sun disc drawn at the glare center. 0 = off.",
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
        .tooltip = "Sun lens flare strength. 1.0 = vanilla.",
        .min = 0.f,
        .max = 3.f,
        .format = "%.3f",
    },

};

void OnPresetOff() {
  renodx::utils::settings::UpdateSettings({
      {"tone_map_type", 0.f},
      {"tone_map_look", LOOK_AUTO},
      {"fl_black_floor", 0.f},
      {"exposure_model", EXPOSURE_AUTO},
      {"fl_dark_boost", 0.f},
      {"bloom_model", BLOOM_AUTO},
      {"diffuse_white_nits", 203.f},
      {"graphics_white_nits", 203.f},
      {"c_mov", 203.f},
      {"vcg_exposure", 1.f},
      {"vcg_other", 1.f},
      {"lut", 1.f},
      {"cg_middle", 1.f},
      {"cg_contrast", 1.f},
      {"cg_shadows", 1.f},
      {"cg_highlights", 1.f},
      {"fakewcg_strength", 0.f},
      {"c_bloom", 1.f},
      {"c_bloom_contrast", 1.f},
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

        renodx::mods::swapchain::resource_upgrade_infos.push_back({  // scene color / LDR targets
            .old_format = reshade::api::format::b8g8r8a8_unorm,
            .new_format = reshade::api::format::r16g16b16a16_float,
            .ignore_size = true,
            .use_resource_view_cloning = false,
            .usage_include = reshade::api::resource_usage::render_target,
        });
        renodx::mods::swapchain::resource_upgrade_infos.push_back({  // specular gbuffer, pixelated otherwise
            .old_format = reshade::api::format::r8g8b8a8_unorm,
            .new_format = reshade::api::format::r16g16b16a16_unorm,
            .ignore_size = true,
            .use_resource_view_cloning = false,
            .usage_include = reshade::api::resource_usage::render_target,
        });
        renodx::mods::swapchain::resource_upgrade_infos.push_back({  // bloom filter buffers and exposure chain
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
              .tooltip = "HDR10: 10bit, worse quality (banding?), but more performant and better compatibility.\nscRGB: Default 16bit max quality.",
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
              .tooltip = "Forces fullscreen to be borderless for proper HDR",
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
              .tooltip = "Prevent exclusive fullscreen for proper HDR",
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
              .tooltip = "Should underlying swapchain respect idle before presenting?\nMay help against multithreading artifacts.",
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
              .tooltip = "Should proxy swapchain respect idle before presenting?\nMay help against multithreading artifacts.",
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
