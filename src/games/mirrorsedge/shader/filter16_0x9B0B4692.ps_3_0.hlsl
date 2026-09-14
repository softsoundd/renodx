// FilterPixelShader.usf (16 taps): blur/downsample used by the exposure meter's chain and the bloom
// blur. Every buffer these filters read and write is fixed point in the shipped game, so taps and
// output are clamped to keep that range after the FP16 upgrade; otherwise highlights above 1.0
// inflate the meter and the exposure settles darker than the game's.
sampler2D FilterTexture : register( s0 );
float4 SampleWeights[16] : register( c2 );

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

float4 Tap(float2 uv) {
	return saturate(tex2D(FilterTexture, uv));
}

float4 main(PS_IN i) : COLOR
{
	float4 o;

	o  = Tap(i.texcoord.xy) * SampleWeights[0];
	o += Tap(i.texcoord.wz) * SampleWeights[1];
	o += Tap(i.texcoord1.xy) * SampleWeights[2];
	o += Tap(i.texcoord1.wz) * SampleWeights[3];
	o += Tap(i.texcoord2.xy) * SampleWeights[4];
	o += Tap(i.texcoord2.wz) * SampleWeights[5];
	o += Tap(i.texcoord3.xy) * SampleWeights[6];
	o += Tap(i.texcoord3.wz) * SampleWeights[7];
	o += Tap(i.texcoord4.xy) * SampleWeights[8];
	o += Tap(i.texcoord4.wz) * SampleWeights[9];
	o += Tap(i.texcoord5.xy) * SampleWeights[10];
	o += Tap(i.texcoord5.wz) * SampleWeights[11];
	o += Tap(i.texcoord6.xy) * SampleWeights[12];
	o += Tap(i.texcoord6.wz) * SampleWeights[13];
	o += Tap(i.texcoord7.xy) * SampleWeights[14];
	o += Tap(i.texcoord7.wz) * SampleWeights[15];

	return saturate(o);
}
