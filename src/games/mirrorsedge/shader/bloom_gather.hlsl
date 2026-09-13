// DOFAndBloomGatherPixelShader.usf (PC, NUM_SAMPLES = 2 * BLOOM_GATHER_TEXCOORDS).
// Included by the 16-tap (0x7FC2150C / 0xC7EFBFAE) and 4-tap (0x0FA334D3 / 0xBAE6E7E9) hash files.
// Scene color rgb is HDR, alpha carries scene depth; output is scaled by 1/MAX_SCENE_COLOR for the filter buffer.
#ifndef BLOOM_GATHER_TEXCOORDS
#define BLOOM_GATHER_TEXCOORDS 8
#endif

#include "./common.hlsl"

sampler2D SceneColorTexture : register(s0);

float4 PackedParameters : register(c0);  // FocusDistance, InverseFocusRadius, FocusExponent
float4 MinMaxBlurClamp : register(c2);
float4 BloomScale : register(c3);

static const float NUM_SAMPLES = 2.0f * BLOOM_GATHER_TEXCOORDS;

struct PS_INPUT {
  float4 uvs[BLOOM_GATHER_TEXCOORDS] : TEXCOORD0;  // .xy = tap A, .wz = tap B
};

float3 BloomColor(float3 scene_color, float model) {
  if (model == BLOOM_FAITHFUL_LUMA) {
    return scene_color * FaithfulLumaBloomFactor(scene_color);
  }
  if (model == BLOOM_SOFT_LEGACY) {
    return scene_color;  // ungated, shaped below
  }
  return any(scene_color > 1) ? scene_color : 0;  // vanilla gate
}

void GatherTap(float2 uv, float model, inout float4 scene_sum, inout float3 bloom_sum) {
  float4 scene_color_and_depth = tex2D(SceneColorTexture, uv);
  scene_sum += scene_color_and_depth;
  float blur_cutoff = saturate(60000.0f - scene_color_and_depth.w);  // far depth guard
  bloom_sum += BloomColor(scene_color_and_depth.rgb, model) * blur_cutoff;
}

float4 main(PS_INPUT i) : COLOR {
  const float model = ResolveBloomModel();

  float4 scene_sum = 0;
  float3 bloom_sum = 0;

  [unroll]
  for (int t = 0; t < BLOOM_GATHER_TEXCOORDS; t++) {
    GatherTap(i.uvs[t].xy, model, scene_sum, bloom_sum);
    GatherTap(i.uvs[t].wz, model, scene_sum, bloom_sum);
  }

  if (model == BLOOM_SOFT_LEGACY) {
    const float y = renodx::color::y::from::BT709(bloom_sum);
    if (y > 0) {
      float y1 = y;
      y1 = renodx::color::grade::Contrast(y1, C_BLOOM_CONTRAST * 1.12, 0.36);
      y1 = renodx::color::grade::Shadows(y1, 0.1, 0.36);
      bloom_sum *= y1 / y;
      bloom_sum = max(bloom_sum, 0);
    }
  }
  bloom_sum *= C_BLOOM;

  float3 avg_bloom = bloom_sum * BloomScale.x / NUM_SAMPLES;
  float4 avg_scene = scene_sum / NUM_SAMPLES;

  // CalcUnfocusedPercent
  float relative_distance = avg_scene.w - PackedParameters.x;
  float max_unfocused = (relative_distance >= 0) ? MinMaxBlurClamp.y : MinMaxBlurClamp.x;
  float unfocused = saturate(abs(relative_distance) * PackedParameters.y);
  unfocused = pow(max(unfocused, 0.0001f), PackedParameters.z);
  unfocused = min(unfocused, max_unfocused);

  float4 o;
  o.xyz = unfocused * avg_scene.xyz + avg_bloom;
  o.w = unfocused;
  return o / MAX_SCENE_COLOR;
}
