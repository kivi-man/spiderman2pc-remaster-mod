// MSM post-process pass, run on the finished frame right before Present (msm_graphics.cpp).
//   FXAA (Lottes, "console" variant), unsharp-mask sharpening, gamma ramp lookup.
// Build: fxc /nologo /T ps_2_b /E main /Vn g_postfxPS /Fh msm_postfx_ps.h msm_postfx.hlsl
sampler2D Scene : register(s0);
sampler2D Ramp : register(s1);   // 256x1, the game's gamma ramp (used when windowed / borderless)

float4 C0 : register(c0);        // xy = 1 / size, z = sharpen amount, w = FXAA on (0/1)
float4 C1 : register(c1);        // x = apply the ramp (0/1)

static const float3 kLuma = float3(0.299, 0.587, 0.114);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
	float2 px = C0.xy;

	float3 rgbNW = tex2D(Scene, uv + float2(-1, -1) * px).rgb;
	float3 rgbNE = tex2D(Scene, uv + float2(1, -1) * px).rgb;
	float3 rgbSW = tex2D(Scene, uv + float2(-1, 1) * px).rgb;
	float3 rgbSE = tex2D(Scene, uv + float2(1, 1) * px).rgb;
	float3 rgbM = tex2D(Scene, uv).rgb;

	float lumaNW = dot(rgbNW, kLuma);
	float lumaNE = dot(rgbNE, kLuma);
	float lumaSW = dot(rgbSW, kLuma);
	float lumaSE = dot(rgbSE, kLuma);
	float lumaM = dot(rgbM, kLuma);
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

	float2 dir;
	dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
	dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));
	float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * (1.0 / 8.0)), 1.0 / 128.0);
	float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = clamp(dir * rcpDirMin, -8.0, 8.0) * px;

	float3 rgbA = 0.5 * (tex2D(Scene, uv + dir * (1.0 / 3.0 - 0.5)).rgb + tex2D(Scene, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
	float3 rgbB = rgbA * 0.5 + 0.25 * (tex2D(Scene, uv + dir * -0.5).rgb + tex2D(Scene, uv + dir * 0.5).rgb);
	float lumaB = dot(rgbB, kLuma);
	float3 aa = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;

	float3 c = lerp(rgbM, aa, C0.w);

	// unsharp mask against the four diagonal neighbours
	float3 blur = (rgbNW + rgbNE + rgbSW + rgbSE) * 0.25;
	c = saturate(c + (rgbM - blur) * C0.z);

	float3 g;
	g.r = tex2D(Ramp, float2((c.r * 255.0 + 0.5) / 256.0, 0.5)).r;
	g.g = tex2D(Ramp, float2((c.g * 255.0 + 0.5) / 256.0, 0.5)).g;
	g.b = tex2D(Ramp, float2((c.b * 255.0 + 0.5) / 256.0, 0.5)).b;
	c = lerp(c, g, C1.x);

	return float4(c, 1);
}
