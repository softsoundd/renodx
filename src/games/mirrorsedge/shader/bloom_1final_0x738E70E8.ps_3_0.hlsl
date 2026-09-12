// DOFAndBloomBlendPixelShader.usf (also included by shader/faithfulluma/bloom_blend_0xB2EC74D6)
#include "./common.hlsl"
sampler2D BlurredImage : register(s1);
float2 MinMaxBlurClamp : register(c2);
float4 PackedParameters : register(c0);
sampler2D SceneColorTexture : register(s0);

struct PS_IN {
  float2 texcoord : TEXCOORD;
  float2 texcoord1 : TEXCOORD1;
};

float4 main(PS_IN i) : COLOR {
  float4 o;

  float4 r0;
  float4 r1;
  float4 r2;

  r0 = tex2D(SceneColorTexture, i.texcoord1);  // focused scene color, depth in alpha
  float3 focused_color = r0.xyz;

  // FocusedWeight = saturate(1 - CalcUnfocusedPercent(depth))
  r1.x = r0.w + -PackedParameters.x;
  r1.y = abs(r1.x) * PackedParameters.y;
  r1.x = (r1.x >= 0) ? MinMaxBlurClamp.y : MinMaxBlurClamp.x;
  r2.x = max(r1.y, 0.0001);
  r1.y = pow(r2.x, PackedParameters.z);
  r2.x = min(r1.y, r1.x);
  r1.x = saturate(-r2.x + 1);

  r2 = tex2D(BlurredImage, i.texcoord);  // unfocused color + bloom (rgb), unfocused weight (a), / MAX_SCENE_COLOR

  r1.yzw = r2.xyz * MAX_SCENE_COLOR;
  r2.x = r2.w * MAX_SCENE_COLOR + r1.x;  // WeightSum
  r0.xyz = r0.xyz * r1.x + r1.yzw;
  o.w = r0.w;

  r0.w = r2.x;
  r0.w = r0.w > 0 ? rcp(r0.w) : 0;  // vanilla: max(WeightSum, 0.001)

  o.xyz = r0.xyz * r0.w;

  // Faithful Luma: crisp bloom core from the full resolution focused sample
  if (ResolveBloomModel() == BLOOM_FAITHFUL_LUMA) {
    float focused_luma = dot(focused_color, LUMA_WEIGHTS_709);
    o.xyz += focused_color * FaithfulLumaBloomFactor(focused_color, focused_luma, false) * C_BLOOM;
  }

  return o;
}

/*
    ps_3_0
      def c1, 9.99999975e-005, 1, 4, 0.00100000005
      dcl_texcoord v0.xy
      dcl_texcoord1 v1.xy
      dcl_2d s0
      dcl_2d s1
      texld_pp r0, v1, s0
      add_pp r1.x, r0.w, -c0.x
      mul_sat r1.y, r1_abs.x, c0.y
      cmp_pp r1.x, r1.x, c2.y, c2.x
      max r2.x, r1.y, c1.x
      pow_pp r1.y, r2.x, c0.z
      min_pp r2.x, r1.y, r1.x
      add_sat_pp r1.x, -r2.x, c1.y
      texld r2, v0, s1
      mul_pp r1.yzw, r2.xxyz, c1.z
      mad_pp r2.x, r2.w, c1.z, r1.x
      mad_pp r0.xyz, r0, r1.x, r1.yzww
      mov_pp oC0.w, r0.w
      max_pp r0.w, r2.x, c1.w
      rcp r0.w, r0.w
      mul_pp oC0.xyz, r0, r0.w
*/
