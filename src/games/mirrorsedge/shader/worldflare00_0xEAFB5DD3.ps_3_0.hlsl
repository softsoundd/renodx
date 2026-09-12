// World flare billboard material (sun reflections on glass). Vanilla shape by default;
// C_WORLDFLARE_ADDBLUR > 0 enables the shaped HDR flare (gain, radial falloff, center glow).
sampler2D Texture2D_0 : register( s0 );
float4 UniformVector_0 : register( c0 );

struct PS_IN
{
	float2 texcoord : TEXCOORD;
	float4 texcoord1 : TEXCOORD1;
	float4 texcoord4 : TEXCOORD4;
};

#include "./common.hlsl"

float4 main(PS_IN i) : COLOR
{
	float4 o;
	o.w = 0;

	const bool shaped = TONE_MAP_TYPE > 0 && C_WORLDFLARE_ADDBLUR > 0;

	float4 r0;
	r0 = tex2D(Texture2D_0, i.texcoord);

	r0.xyz = r0.xyz + float3(-1, -1, -0.75);
	r0.w = r0.w * i.texcoord1.w;
	if (shaped) r0.w *= 1.25;
	r0.xyz = r0.w * r0.xyz + float3(1, 1, 0.75);

	r0.xyz = r0.w * r0.xyz + UniformVector_0.xyz;
	r0.xyz = r0.xyz * i.texcoord4.w;
	if (shaped) r0.xyz *= 1.25;
	o.xyz = r0.w * r0.xyz;

	if (TONE_MAP_TYPE == 0) return o;  // vanilla

	if (shaped) {
		o.xyz *= 1.15;

		float3 colorCenter = tex2D(Texture2D_0, (float2)0.5f).xyz;
		float l = length(i.texcoord - float2(0.5, 0.5));
		l = l + 0.5;
		l = 1 - l;
		l = saturate(l * 2);
		l = pow(l, 3.75);

		o.xyz *= l;

		o.xyz += colorCenter * l * C_WORLDFLARE_ADDBLUR * 0.35;

		o.xyz *= 1.15;
	}

	o.xyz *= C_WORLDFLARE;

	return o;
}

/*
    ps_3_0
      def c1, -1, -0.75, 1, 0.75
      def c2, 0, 0, 0, 0
      dcl_texcoord v0.xy
      dcl_texcoord1 v1.w
      dcl_texcoord4_pp v2.w
      dcl_2d s0
      texld r0, v0, s0
      add r0.xyz, r0, c1.xxyw
      mul r0.w, r0.w, v1.w
      mad r0.xyz, r0.w, r0, c1.zzww
      mad_pp r0.xyz, r0.w, r0, c0
      mul_pp r0.xyz, r0, v2.w
      mul_pp oC0.xyz, r0.w, r0
      mov_pp oC0.w, c2.x
*/
