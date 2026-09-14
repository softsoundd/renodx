sampler2D SceneColorTexture : register(s0);
float4 ScreenPositionScaleBias : register(c1);
float UniformScalar_0 : register(c2);
float UniformScalar_4 : register(c3);
float4 UniformVector_0 : register(c0);

// Death post-process material: scales the tonemapped scene toward white as DeathAmount rises.
// Vanilla saturates the result, which would clip everything above graphics white the instant the
// effect starts. The range at or below white keeps the vanilla math; the excess above white is
// divided by the same gain so highlights converge on white together with the rest of the frame.
float4 main(float4 texcoord5 : TEXCOORD5) : COLOR {
  float4 o;

  float4 r0;
  r0.x = 1 / texcoord5.w;
  r0.xy = r0.x * texcoord5.xy;
  r0.xy = r0.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
  r0 = tex2D(SceneColorTexture, r0.xy);

  float gain = (1 + UniformScalar_0.x) * UniformScalar_4.x;
  float3 scaled = r0.xyz * gain;
  float3 sdr = saturate(scaled);  // vanilla: mul_sat
  float3 hdr = (gain > 1) ? 1 + (r0.xyz - 1) / gain : scaled;
  r0.xyz = lerp(sdr, hdr, step(1, r0.xyz));
  o.xyz = r0.xyz + UniformVector_0.xyz;
  o.w = texcoord5.w;

  return o;
}

/*
    ps_3_0
    dcl_texcoord5 v0.xyw
    dcl_2d s0
    rcp r0.x, v0.w
    mul r0.xy, r0.x, v0
    mad r0.xy, r0, c1, c1.wzzw
    texld r0, r0, s0
    mad r0.xyz, c2.x, r0, r0
    mul_sat r0.xyz, r0, c3.x
    add_pp oC0.xyz, r0, c0
    mov oC0.w, v0.w
*/
