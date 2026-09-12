sampler2D SceneColorTexture : register(s0);
float4 ScreenPositionScaleBias : register(c1);
sampler2D Texture2D_0 : register(s1);
float UniformScalar_0 : register(c2);
float4 UniformVector_0 : register(c0);

struct PS_IN {
  float2 texcoord : TEXCOORD;
  float4 texcoord5 : TEXCOORD5;
};

// Sniper scope post-process material. Vanilla saturates its intermediates; omitted here so the
// HDR scene passes through the vignette unclamped.
float4 main(PS_IN i) : COLOR {
  float4 o;

  float4 r0;
  float4 r1;
  r0.xy = i.texcoord.xy * float2(2, -2) + float2(-1, 1);
  r0.xy = r0.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
  r0 = tex2D(SceneColorTexture, r0);
  r1.xy = -0.5 + i.texcoord.xy;
  r0.w = r1.y + r1.y;
  r1.x = r1.x * 3.56;
  r0.w = r0.w * r0.w;
  r0.w = r1.x * r1.x + r0.w;
  r0.w = 1 / sqrt(r0.w);
  r0.w = 1 / r0.w;
  r1.x = max(r0.w, 0.0001);
  r0.w = pow(r1.x, 10);
  r0.w = saturate(-r0.w + 1);  // vanilla: add_sat
  if (r0.w < 0.99) r0.xyz = max(0, r0.xyz);  // clamp negatives outside the scope view
  r0.xyz = r0.xyz * r0.w;  // vanilla: mul_sat (scene clamp)
  r0.xyz = r0.xyz * UniformScalar_0.x;
  r0.xyz = r0.w * r0.xyz;
  r1 = tex2D(Texture2D_0, i.texcoord);
  r0.w = r0.w * r1.x;
  r0.xyz = r0.xyz * r0.w;
  o.xyz = r0.xyz + UniformVector_0.xyz;
  o.w = i.texcoord5.w;

  return o;
}
