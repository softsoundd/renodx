sampler2D Texture2D_0 : register( s0 );
float4 UniformVector_0 : register( c0 );

struct PS_IN
{
	float3 color : COLOR;
	float2 texcoord : TEXCOORD;
	float4 texcoord5 : TEXCOORD5;
};

#include "../shared.h"


float4 main(PS_IN i) : COLOR
{
	float4 o;

	float4 r0;
	float3 r1;
	r0.xy = i.texcoord.xy * float2(1, 4) + -3;
	r0 = tex2D(Texture2D_0, r0);
	r1.xyz = i.color.xyz * float3(0.4, 0.6, 1) + -r0.xyz;
	r0.xyz = r0.w * r1.xyz + r0.xyz;
	r0.w = 1.6;  // vanilla constant (c2.w)
	o.xyz = r0.xyz * r0.w + UniformVector_0.xyz;
	if (TONE_MAP_TYPE > 0) o.xyz *= C_SKY;  // 1.0 = vanilla
	o.w = i.texcoord5.w;

	return o;
}
