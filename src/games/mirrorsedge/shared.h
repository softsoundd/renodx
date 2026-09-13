#ifndef SRC_MIRRORSEDGE_SHARED_H_
#define SRC_MIRRORSEDGE_SHARED_H_

#define CBUFFER  13
#define CBUFFERB b13

// tone_map_look
#define LOOK_AUTO          0.f
#define LOOK_VANILLA       1.f
#define LOOK_FAITHFUL_LUMA 2.f

// exposure_model
#define EXPOSURE_AUTO          0.f
#define EXPOSURE_VANILLA       1.f
#define EXPOSURE_FAITHFUL_LUMA 2.f

// bloom_model
#define BLOOM_AUTO          0.f
#define BLOOM_VANILLA       1.f
#define BLOOM_FAITHFUL_LUMA 2.f
#define BLOOM_SOFT_LEGACY   3.f

// Must be 32bit aligned
// Should be 4x32
struct ShaderInjectData {
  float gamma_correction;     // renodx::draw::GAMMA_CORRECTION_*
  float swap_chain_encoding;  // renodx::draw::ENCODING_PQ or ENCODING_SCRGB
  float fakewcgcorrect_gamma;
  float fakewcgcorrect_chroma;

  float fakewcgcorrect_luma;
  float fakewcgcorrect_sat;
  float peak_white_nits;
  float graphics_white_nits;

  float diffuse_white_nits;
  float expected_white_nits;
  float tone_map_type;
  float vcg_lut;

  float vcg_other;
  float vcg_colornwc;
  float vcg_exposure;
  float c_worldflare;

  float c_worldflare_addblur;
  float c_sunglare;
  float c_sunsize;
  float c_sunlens;

  float cg_middle;
  float cg_contrast;
  float cg_highlights;
  float cg_shadows;

  float pblow_chue;
  float pblow_csat;
  float pblow_start;
  float pblow_max;

  float pblow_satboost;
  float pblow_guaranteed;
  float c_bloom;
  float c_bloom_contrast;

  float c_speedlines;
  float c_mov;
  float c_sky;
  float tone_map_look;

  float exposure_model;
  float bloom_model;
  float fl_dark_boost;
  float faithful_luma_detected;           // set when the game creates a Faithful Luma compiled shader

  float swap_chain_encoding_color_space;  // color::convert::COLOR_SPACE_BT2020 for HDR10, BT709 for scRGB
  float tone_map_exposure;                // RenoDRT grade (tone map type 3)
  float tone_map_highlights;
  float tone_map_shadows;

  float tone_map_contrast;
  float tone_map_saturation;
  float tone_map_highlight_saturation;
  float tone_map_blowout;

  float tone_map_flare;
  float color_grade_strength;
  float custom_saturation_clip;  // vanilla per-channel clip emulation in the SDR proxy (RenoDRT type)
  float custom_hue_clip;
};

#ifndef __cplusplus
#if (__SHADER_TARGET_MAJOR == 3)

float4 shader_injection[13] : register(c50);

#define GAMMA_CORRECTION                 shader_injection[0][0]
#define SWAP_CHAIN_ENCODING              shader_injection[0][1]
#define FAKEWCGCORRECT_GAMMA             shader_injection[0][2]
#define FAKEWCGCORRECT_CHROMA            shader_injection[0][3]

#define FAKEWCGCORRECT_LUMA              shader_injection[1][0]
#define FAKEWCGCORRECT_SAT               shader_injection[1][1]
#define PEAK_WHITE_NITS                  shader_injection[1][2]
#define GRAPHICS_WHITE_NITS              shader_injection[1][3]

#define DIFFUSE_WHITE_NITS               shader_injection[2][0]
#define EXPECTED_WHITE_NITS              shader_injection[2][1]
#define TONE_MAP_TYPE                    shader_injection[2][2]
#define VCG_LUT                          shader_injection[2][3]

#define VCG_OTHER                        shader_injection[3][0]
#define VCG_COLORNWC                     shader_injection[3][1]
#define VCG_EXPOSURE                     shader_injection[3][2]
#define C_WORLDFLARE                     shader_injection[3][3]

#define C_WORLDFLARE_ADDBLUR             shader_injection[4][0]
#define C_SUNGLARE                       shader_injection[4][1]
#define C_SUNSIZE                        shader_injection[4][2]
#define C_SUNLENS                        shader_injection[4][3]

#define CG_MIDDLE                        shader_injection[5][0]
#define CG_CONTRAST                      shader_injection[5][1]
#define CG_HIGHLIGHTS                    shader_injection[5][2]
#define CG_SHADOWS                       shader_injection[5][3]

#define PBLOW_CHUE                       shader_injection[6][0]
#define PBLOW_CSAT                       shader_injection[6][1]
#define PBLOW_START                      shader_injection[6][2]
#define PBLOW_MAX                        shader_injection[6][3]

#define PBLOW_SATBOOST                   shader_injection[7][0]
#define PBLOW_GUARANTEED                 shader_injection[7][1]
#define C_BLOOM                          shader_injection[7][2]
#define C_BLOOM_CONTRAST                 shader_injection[7][3]

#define C_SPEEDLINES                     shader_injection[8][0]
#define C_MOV                            shader_injection[8][1]
#define C_SKY                            shader_injection[8][2]
#define TONE_MAP_LOOK                    shader_injection[8][3]

#define EXPOSURE_MODEL                   shader_injection[9][0]
#define BLOOM_MODEL                      shader_injection[9][1]
#define FL_DARK_BOOST                    shader_injection[9][2]
#define FAITHFUL_LUMA_DETECTED           shader_injection[9][3]

#define SWAP_CHAIN_ENCODING_COLOR_SPACE  shader_injection[10][0]
#define TONE_MAP_EXPOSURE                shader_injection[10][1]
#define TONE_MAP_HIGHLIGHTS              shader_injection[10][2]
#define TONE_MAP_SHADOWS                 shader_injection[10][3]

#define TONE_MAP_CONTRAST                shader_injection[11][0]
#define TONE_MAP_SATURATION              shader_injection[11][1]
#define TONE_MAP_HIGHLIGHT_SATURATION    shader_injection[11][2]
#define TONE_MAP_BLOWOUT                 shader_injection[11][3]

#define TONE_MAP_FLARE                   shader_injection[12][0]
#define COLOR_GRADE_STRENGTH             shader_injection[12][1]
#define CUSTOM_SATURATION_CLIP           shader_injection[12][2]
#define CUSTOM_HUE_CLIP                  shader_injection[12][3]

#else

#if ((__SHADER_TARGET_MAJOR == 5 && __SHADER_TARGET_MINOR >= 1) || __SHADER_TARGET_MAJOR >= 6)
cbuffer shader_injection : register(CBUFFERB, space50) {
  ShaderInjectData shader_injection : packoffset(c0);
}
#elif (__SHADER_TARGET_MAJOR < 5) || ((__SHADER_TARGET_MAJOR == 5) && (__SHADER_TARGET_MINOR < 1))
cbuffer shader_injection : register(CBUFFERB) {
  ShaderInjectData shader_injection : packoffset(c0);
}
#endif

#define GAMMA_CORRECTION                 shader_injection.gamma_correction
#define SWAP_CHAIN_ENCODING              shader_injection.swap_chain_encoding
#define FAKEWCGCORRECT_GAMMA             shader_injection.fakewcgcorrect_gamma
#define FAKEWCGCORRECT_CHROMA            shader_injection.fakewcgcorrect_chroma
#define FAKEWCGCORRECT_LUMA              shader_injection.fakewcgcorrect_luma
#define FAKEWCGCORRECT_SAT               shader_injection.fakewcgcorrect_sat
#define PEAK_WHITE_NITS                  shader_injection.peak_white_nits
#define GRAPHICS_WHITE_NITS              shader_injection.graphics_white_nits
#define DIFFUSE_WHITE_NITS               shader_injection.diffuse_white_nits
#define EXPECTED_WHITE_NITS              shader_injection.expected_white_nits
#define TONE_MAP_TYPE                    shader_injection.tone_map_type
#define VCG_LUT                          shader_injection.vcg_lut
#define VCG_OTHER                        shader_injection.vcg_other
#define VCG_COLORNWC                     shader_injection.vcg_colornwc
#define VCG_EXPOSURE                     shader_injection.vcg_exposure
#define C_WORLDFLARE                     shader_injection.c_worldflare
#define C_WORLDFLARE_ADDBLUR             shader_injection.c_worldflare_addblur
#define C_SUNGLARE                       shader_injection.c_sunglare
#define C_SUNSIZE                        shader_injection.c_sunsize
#define C_SUNLENS                        shader_injection.c_sunlens
#define CG_MIDDLE                        shader_injection.cg_middle
#define CG_CONTRAST                      shader_injection.cg_contrast
#define CG_HIGHLIGHTS                    shader_injection.cg_highlights
#define CG_SHADOWS                       shader_injection.cg_shadows
#define PBLOW_CHUE                       shader_injection.pblow_chue
#define PBLOW_CSAT                       shader_injection.pblow_csat
#define PBLOW_START                      shader_injection.pblow_start
#define PBLOW_MAX                        shader_injection.pblow_max
#define PBLOW_SATBOOST                   shader_injection.pblow_satboost
#define PBLOW_GUARANTEED                 shader_injection.pblow_guaranteed
#define C_BLOOM                          shader_injection.c_bloom
#define C_BLOOM_CONTRAST                 shader_injection.c_bloom_contrast
#define C_SPEEDLINES                     shader_injection.c_speedlines
#define C_MOV                            shader_injection.c_mov
#define C_SKY                            shader_injection.c_sky
#define TONE_MAP_LOOK                    shader_injection.tone_map_look
#define EXPOSURE_MODEL                   shader_injection.exposure_model
#define BLOOM_MODEL                      shader_injection.bloom_model
#define FL_DARK_BOOST                    shader_injection.fl_dark_boost
#define FAITHFUL_LUMA_DETECTED           shader_injection.faithful_luma_detected
#define SWAP_CHAIN_ENCODING_COLOR_SPACE  shader_injection.swap_chain_encoding_color_space
#define TONE_MAP_EXPOSURE                shader_injection.tone_map_exposure
#define TONE_MAP_HIGHLIGHTS              shader_injection.tone_map_highlights
#define TONE_MAP_SHADOWS                 shader_injection.tone_map_shadows
#define TONE_MAP_CONTRAST                shader_injection.tone_map_contrast
#define TONE_MAP_SATURATION              shader_injection.tone_map_saturation
#define TONE_MAP_HIGHLIGHT_SATURATION    shader_injection.tone_map_highlight_saturation
#define TONE_MAP_BLOWOUT                 shader_injection.tone_map_blowout
#define TONE_MAP_FLARE                   shader_injection.tone_map_flare
#define COLOR_GRADE_STRENGTH             shader_injection.color_grade_strength
#define CUSTOM_SATURATION_CLIP           shader_injection.custom_saturation_clip
#define CUSTOM_HUE_CLIP                  shader_injection.custom_hue_clip

#endif

// renodx::draw configuration. The intermediate is BT.709 scaled by diffuse/graphics white and
// encoded with (gamma correction + 1): sRGB when correction is off, 2.2/2.4 when emulating.
// ToneMapPass is only called from this mod's "RenoDRT (Neutwo)" tone map type, so RenoDX's own
// type selector is pinned to RenoDRT.
#define RENODX_PEAK_WHITE_NITS                 PEAK_WHITE_NITS
#define RENODX_DIFFUSE_WHITE_NITS              DIFFUSE_WHITE_NITS
#define RENODX_GRAPHICS_WHITE_NITS             GRAPHICS_WHITE_NITS
#define RENODX_TONE_MAP_TYPE                   renodx::draw::TONE_MAP_TYPE_RENO_DRT
#define RENODX_RENO_DRT_TONE_MAP_METHOD        renodx::tonemap::renodrt::config::tone_map_method::NEUTWO
#define RENODX_TONE_MAP_EXPOSURE               TONE_MAP_EXPOSURE
#define RENODX_TONE_MAP_HIGHLIGHTS             TONE_MAP_HIGHLIGHTS
#define RENODX_TONE_MAP_SHADOWS                TONE_MAP_SHADOWS
#define RENODX_TONE_MAP_CONTRAST               TONE_MAP_CONTRAST
#define RENODX_TONE_MAP_SATURATION             TONE_MAP_SATURATION
#define RENODX_TONE_MAP_HIGHLIGHT_SATURATION   TONE_MAP_HIGHLIGHT_SATURATION
#define RENODX_TONE_MAP_BLOWOUT                TONE_MAP_BLOWOUT
#define RENODX_TONE_MAP_FLARE                  TONE_MAP_FLARE
#define RENODX_TONE_MAP_HUE_SHIFT              0.f  // the vanilla clip is emulated in the SDR proxy instead
#define RENODX_COLOR_GRADE_STRENGTH            COLOR_GRADE_STRENGTH
#define RENODX_GAMMA_CORRECTION                GAMMA_CORRECTION
#define RENODX_INTERMEDIATE_SCALING            (DIFFUSE_WHITE_NITS / GRAPHICS_WHITE_NITS)
#define RENODX_INTERMEDIATE_ENCODING           (GAMMA_CORRECTION + 1.f)
#define RENODX_INTERMEDIATE_COLOR_SPACE        color::convert::COLOR_SPACE_BT709
#define RENODX_SWAP_CHAIN_DECODING             RENODX_INTERMEDIATE_ENCODING
#define RENODX_SWAP_CHAIN_DECODING_COLOR_SPACE RENODX_INTERMEDIATE_COLOR_SPACE
#define RENODX_SWAP_CHAIN_SCALING_NITS         GRAPHICS_WHITE_NITS
#define RENODX_SWAP_CHAIN_CLAMP_NITS           PEAK_WHITE_NITS
#define RENODX_SWAP_CHAIN_CLAMP_COLOR_SPACE    color::convert::COLOR_SPACE_BT2020
#define RENODX_SWAP_CHAIN_ENCODING             SWAP_CHAIN_ENCODING
#define RENODX_SWAP_CHAIN_ENCODING_COLOR_SPACE SWAP_CHAIN_ENCODING_COLOR_SPACE

#include "../../shaders/renodx.hlsl"

#endif  // __cplusplus

#endif  // SRC_MIRRORSEDGE_SHARED_H_
