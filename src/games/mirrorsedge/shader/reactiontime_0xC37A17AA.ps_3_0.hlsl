sampler2D SceneColorTexture : register(s0);
float4 UniformVector_0 : register(c0);
float4 ScreenPositionScaleBias : register(c1);
float UniformScalar_0 : register(c2);
float UniformScalar_1 : register(c3);
float UniformScalar_2 : register(c4);

// Reaction time post-process material, run on the HDR scene before the tone map: tints the scene
// toward blue, adds a luminance-keyed blue glow toward the screen edges, and clamps the result to
// 10 scene units. That clamp is invisible in SDR, where anything that bright clips at the display
// anyway, but in HDR it caps every light above 10 scene units for the duration of the effect. The
// mod keeps the vanilla math and drops the upper clamp.
float4 main(float2 texcoord : TEXCOORD0, float4 texcoord5 : TEXCOORD5) : COLOR {
  float2 centred = texcoord - 0.5;
  centred.x *= 1.777;
  float r2 = dot(centred, centred);
  float edge = saturate(r2);
  float centre = 1 - saturate(UniformScalar_1 * (r2 * 15000 - 1) + 1);
  float weight = centre * UniformScalar_1 + edge * UniformScalar_2;

  float2 uv = texcoord5.xy / texcoord5.w * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
  float3 scene = tex2D(SceneColorTexture, uv).rgb;

  float luma = dot(scene, float3(0.3, 0.59, 0.11));
  float3 glow = weight * float3(0.1, 0.25, 0.5) + (weight * luma) * float3(0.9, 2.75, 14.5);
  float3 tinted = scene * UniformScalar_0 * float3(0, 0.2, 0.75) + scene;

  float4 o;
  o.xyz = max(glow + tinted, 0) + UniformVector_0.xyz;  // vanilla: clamp(glow + tinted, 0, 10)
  o.w = texcoord5.w;
  return o;
}

/*
    ps_3_0
    def c5, 1.77699995, 15000, -1, 1
    def c6, 0, 0.200000048, 0.75, -0.5
    def c7, 0.100000001, 0.25, 0.5, 0
    def c8, 0.300000012, 0.589999974, 0.109999999, 10
    def c9, 0.899999976, 2.75, 14.5, 0
    dcl_texcoord v0.xy
    dcl_texcoord5 v1.xyw
    dcl_2d s0
    add r0.xy, c6.w, v0
    mul r0.x, r0.x, c5.x
    mul r0.y, r0.y, r0.y
    mad r0.x, r0.x, r0.x, r0.y
    mad r0.y, r0.x, c5.y, c5.z
    mov_sat r0.x, r0.x
    mov r0.w, c5.w
    mad_sat r0.y, c3.x, r0.y, r0.w
    add r0.y, -r0.y, c5.w
    mul r0.x, r0.x, c4.x
    mad r0.x, r0.y, c3.x, r0.x
    rcp r0.y, v1.w
    mul r0.yz, r0.y, v1.xxyw
    mad r0.yz, r0, c1.xxyw, c1.xwzw
    texld r1, r0.yzzw, s0
    dp3 r0.y, r1, c8
    mul r0.y, r0.x, r0.y
    mul r0.yzw, r0.y, c9.xxyz
    mad r0.xyz, r0.x, c7, r0.yzww
    mul r2.xyz, r1, c2.x
    mad r1.xyz, r2, c6, r1
    add r0.xyz, r0, r1
    max r1.xyz, r0, c6.x
    min r0.xyz, r1, c8.w
    add_pp oC0.xyz, r0, c0
    mov oC0.w, v1.w
*/
