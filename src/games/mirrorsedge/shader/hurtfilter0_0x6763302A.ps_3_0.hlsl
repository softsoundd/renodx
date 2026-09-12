sampler2D SceneColorTexture : register( s0 );
float4 ScreenPositionScaleBias : register( c1 );
float UniformScalar_0 : register( c2 );
float UniformScalar_2 : register( c3 );
float UniformScalar_4 : register( c4 );
float4 UniformVector_0 : register( c0 );

struct PS_IN
{
	float2 texcoord : TEXCOORD;
	float4 texcoord5 : TEXCOORD5;
};

// Hurt/damage post-process material. Vanilla saturates its intermediates; omitted here so the
// HDR scene passes through the red tint unclamped.
float4 main(PS_IN i) : COLOR
{
	float4 o;

	float4 r0;
	float4 r1;
	float3 r2;
	
	r0.x = abs(UniformScalar_0.x);
	r1.x = max(r0.x, 0.0001);
	r0.x = pow(r1.x, 1.5);
	r0.x = r0.x * 0.8 + 0.2;
	r0.x = i.texcoord.y * 0.6 + r0.x;
	r1.x = max(abs(r0.x), 0.0001);
	r0.x = r1.x * r1.x;
	r0.x = saturate(r0.x * UniformScalar_2.x);  // vanilla: mul_sat
	r0.xyz = r0.x * float3(-0, -5, -5) + 1;
	r0.w = 1 / i.texcoord5.w;
	r1.xy = r0.w * i.texcoord5.xy;
	r1.xy = r1.xy * ScreenPositionScaleBias.xy + ScreenPositionScaleBias.wz;
	r1 = tex2D(SceneColorTexture, r1);
	r2.xyz = r1.xyz * 0.3;
	r0.xyz = r2.xyz * r0.xyz + -r1.xyz;
	r0.xyz = UniformScalar_4.x * r0.xyz + r1.xyz;  // vanilla: mad_sat (scene clamp)
	o.xyz = r0.xyz + UniformVector_0.xyz;
	o.w = i.texcoord5.w;

	return o;
}
