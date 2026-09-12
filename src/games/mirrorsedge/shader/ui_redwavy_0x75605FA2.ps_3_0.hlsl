// Menu selection highlight material. Its emissive constants exceed 1.0, which the vanilla 8-bit
// render target clamped on write; the outputs are saturated here to keep that clamp on the FP16
// target, otherwise the highlight lands above UI white and text edges blended over it alias.

sampler2D Texture2D_0 : register(s0);
sampler2D Texture2D_1 : register(s1);
sampler2D Texture2D_2 : register(s2);
sampler2D Texture2D_3 : register(s3);

float4 UniformVector_0 : register(c0);
float4 UniformVector_1 : register(c2);
float4 UniformVector_2 : register(c3);
float4 UniformVector_3 : register(c4);
float4 UniformVector_4 : register(c5);
float4 UniformScalar_1 : register(c6);
float4 UniformScalar_3 : register(c7);
float4 UniformScalar_5 : register(c8);
float4 UniformScalar_13 : register(c9);
float4 UniformScalar_17 : register(c10);
float4 UniformScalar_18 : register(c11);
float4 UniformScalar_26 : register(c12);

struct PS_INPUT
{
    float2 v0 : TEXCOORD0;
    float4 v1 : TEXCOORD4;
};

struct PS_OUTPUT
{
    float4 oC0 : COLOR0;
};

PS_OUTPUT main(PS_INPUT i)
{
    PS_OUTPUT o;

    const float4 c1  = float4(-0.100000001, -0.200000003, -0.400000006, -1);
    const float4 c13 = float4(512, 20, -0.5, 5);
    const float4 c14 = float4(0, 40, 0.150000006, 0.5);

    float4 r0, r1, r2, r3;

    r0 = tex2D(Texture2D_0, UniformScalar_17.xx);
    r0.x = r0.y + c13.z;
    r0.x = r0.x * UniformScalar_18.x;
    r0.y = r0.x * c13.w;
    r1.xy = c13.xy;
    r0.y = UniformScalar_26.x * r1.y + r0.y;
    r2.z = r0.y + c1.w;
    r2.y = c14.x;
    r2.w = c14.x;
    r0.y = i.v0.x * c14.y - r2.z;
    r0.z = i.v0.y * c14.z - r2.w;
    r0.y = r0.y + UniformVector_4.x;
    r0.z = r0.z + UniformVector_4.y;
    r3 = tex2D(Texture2D_3, r0.yz);
    r0.y = UniformScalar_13.x * r1.y + r1.y;
    r2.x = r0.x * c13.w + r0.y;
    r0.x = i.v0.x * c14.y - r2.x;
    r0.y = i.v0.y * c14.z - r2.y;
    r0.xy = r0.xy + UniformVector_3.xy;
    r0.z = r0.x - c14.w;
    r0.w = r0.y - c14.x;
    r2 = tex2D(Texture2D_1, r0.xy);
    r0 = tex2D(Texture2D_2, r0.zw);
    r0.x = saturate(r2.x + r0.x);
    o.oC0.w = saturate(r3.x * r0.x);

    r0.x = saturate(i.v0.y * (-r1.x) + UniformScalar_1.x);
    r0.y = saturate(i.v0.y * r1.x + (-UniformScalar_3.x));
    r0.x = r0.x + r0.y;
    r0.x = saturate(r0.x + UniformScalar_5.x);
    r1.xyz = UniformVector_1.xyz;
    r0.y = -r1.x + UniformVector_2.x;
    r0.z = -r1.y + UniformVector_2.y;
    r0.w = -r1.z + UniformVector_2.z;
    r0.xyz = r0.x * r0.yzw + UniformVector_1.xyz;
    r0.xyz = r0.xyz + c1.xyz;
    r0.xyz = r2.y * r0.xyz + UniformVector_0.xyz;
    r0.xyz = r0.xyz + (-c1.xyz);
    o.oC0.xyz = saturate(r0.xyz * i.v1.w + i.v1.xyz);

    return o;
}

/*
    ps_3_0
      def c1, -0.100000001, -0.200000003, -0.400000006, -1
      def c13, 512, 20, -0.5, 5
      def c14, 0, 40, 0.150000006, 0.5
      dcl_texcoord v0.xy
      dcl_texcoord4_pp v1
      dcl_2d s0
      dcl_2d s1
      dcl_2d s2
      dcl_2d s3
      texld r0, c10.x, s0
      add r0.x, r0.y, c13.z
      mul r0.x, r0.x, c11.x
      mul r0.y, r0.x, c13.w
      mov r1.xy, c13
      mad r0.y, c12.x, r1.y, r0.y
      add r2.z, r0.y, c1.w
      mov r2.yw, c14.x
      mad r0.yz, v0.xxyw, c14, -r2.xzww
      add r0.yz, r0, c5.xxyw
      texld r3, r0.yzzw, s3
      mad r0.y, c9.x, r1.y, r1.y
      mad r2.x, r0.x, c13.w, r0.y
      mad r0.xy, v0, c14.yzzw, -r2
      add r0.xy, r0, c4
      add r0.zw, r0.xyxy, -c14.xywx
      texld r2, r0, s1
      texld r0, r0.zwzw, s2
      add_sat r0.x, r2.x, r0.x
      mul_pp oC0.w, r3.x, r0.x
      mad_sat r0.x, v0.y, -r1.x, c6.x
      mad_sat r0.y, v0.y, r1.x, -c7.x
      add r0.x, r0.x, r0.y
      add_sat r0.x, r0.x, c8.x
      mov r1.xyz, c2
      add r0.yzw, -r1.xxyz, c3.xxyz
      mad r0.xyz, r0.x, r0.yzww, c2
      add r0.xyz, r0, c1
      mad r0.xyz, r2.y, r0, c0
      add_pp r0.xyz, r0, -c1
      mad_pp oC0.xyz, r0, v1.w, v1
*/
