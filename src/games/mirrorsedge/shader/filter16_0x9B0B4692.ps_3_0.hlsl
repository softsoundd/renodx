// FilterPixelShader.usf (16 taps): blur/downsample used by the bloom and exposure chains.
// Taps are saturated to keep the original fixed point filter buffer range after the FP16 upgrade.
sampler2D FilterTexture : register( s0 );
float4 SampleWeights : register( c2 );

struct PS_IN
{
	float4 texcoord : TEXCOORD;
	float4 texcoord1 : TEXCOORD1;
	float4 texcoord2 : TEXCOORD2;
	float4 texcoord3 : TEXCOORD3;
	float4 texcoord4 : TEXCOORD4;
	float4 texcoord5 : TEXCOORD5;
	float4 texcoord6 : TEXCOORD6;
	float4 texcoord7 : TEXCOORD7;
};

float4 main(PS_IN i) : COLOR
{
	float4 o;

	float4 r0;
	float4 r1;
	r0 = tex2D(FilterTexture, i.texcoord.wzzw); r0 = saturate(r0);
	r0 = r0 * SampleWeights;
	r1 = tex2D(FilterTexture, i.texcoord); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord1); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord1.wzzw); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord2); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord2.wzzw); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord3); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord3.wzzw); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord4); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord4.wzzw); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord5); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord5.wzzw); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord6); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord6.wzzw); r1 = saturate(r1);
	r1 = tex2D(FilterTexture, i.texcoord7); r1 = saturate(r1);
	r0 = r1 * SampleWeights + r0;
	r1 = tex2D(FilterTexture, i.texcoord7.wzzw); r1 = saturate(r1);
	o = r1 * SampleWeights + r0;
	o = saturate(o);

	return o;
}
