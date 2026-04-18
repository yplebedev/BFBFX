#pragma once
#include "OpenRSF.fxh"

#define MODE BORDER
#define ADDRESS\
AddressU = MODE;\
AddressV = MODE;\
AddressW = MODE

texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; MipLevels = 4; };
sampler sAO { Texture = tAO; };

texture tAOhistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sAOhistory { Texture = tAOhistory; ADDRESS; };

texture tAccumLength { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; };
sampler sAccumLength { POINT_SAMPLE; Texture = tAccumLength; };

texture tGI { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 6; };
sampler sGI { Texture = tGI; MagFilter = POINT; MinFilter = POINT; };

texture tGIhistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sGIhistory { Texture = tGIhistory; };

texture tLumaSquared { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 6; };
sampler sLumaSquared { Texture = tLumaSquared; };

texture tLumaSquaredHistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sLumaSquaredHistory { Texture = tLumaSquaredHistory; };

texture tVariance { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sVariance { Texture = tVariance; };

texture tVarianceS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sVarianceS { Texture = tVarianceS; };

#ifndef GI_SHADER
texture tDenoised0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sDenoised0 { Texture = tDenoised0; };

texture tDenoised1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sDenoised1 { Texture = tDenoised1; };
#else
texture tDenoised0g { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=RGBA16F; };
sampler sDenoised0g { Texture = tDenoised0g; };

texture tDenoised1g { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=RGBA16F; };
sampler sDenoised1g { Texture = tDenoised1g; };
#endif

void increment(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float by : SV_Target0) {
	by = 1.;
}


bool onscreen(float2 uv) {
	// could be 0.5, but this is more robust (check border)
	const float threshold = 0.5 - max(ReShade::PixelSize.x, ReShade::PixelSize.y);
	float2 clip_h = abs(uv - 0.5);
	return clip_h.x < threshold && clip_h.y < threshold;
}

void reset(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float accumulation : SV_Target0) {
	float3 motion = getMotion(uv);
	
	accumulation = ((motion.z > 0.8) && onscreen(uv + motion.xy)) ? 100000. : 0.;
}

void clamp_accum(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float max : SV_Target0) {
	max = 32.0;
}


void copy_ao(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	output = tex2D(sAO, uv).r;
}

void copy_gi(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 output : SV_Target0, out float luma_squared : SV_Target1) {
	output = tex2D(sGI, uv);
	luma_squared = tex2D(sLumaSquared, uv).r;
}

#define loop_3x3(callback)\
for (int dx = -1; dx <= 1; dx++) {\
for (int dy = -1; dy <= 1; dy++) {\
	callback\
}\
}\

#define loop_7x7(callback)\
for (int dx = -3; dx <= 3; dx++) {\
for (int dy = -3; dy <= 3; dy++) {\
	callback\
}\
}

uint get_slice(int dx, int dy) {
	return (dx + 1) + 3*(dy + 1);
}

uint get_slice_wide(int dx, int dy) {
	return (dx + 3) + 7*(dy + 3);
}

float3 getNormalOffset(float2 uv, int2 offset) {
	if (all(abs(offset) < 7))
		return normalize(UVtoOCT(tex2Doffset(ORSFShared::sTexN, uv, offset).xy));
	else
		return normalize(UVtoOCT(tex2Dlod(ORSFShared::sTexN, float4(uv + offset * ReShade::PixelSize, 0., 0.)).xy));
}

#ifndef GI_SHADER
float normal_similarity(float3 center, float3 checked) {
	const float sigma = 3.;
	return pow(max(dot(center, checked), 0.), sigma);
}

float color_similarity(float center, float checked) {
	// This will NaN at 0!
	const float sigma = 0.04;
	
	return exp(-distance(center, checked) / (sigma));
}

float tex2DoffsetLOD(sampler source, float2 uv, int2 offset, float LOD) {
	return tex2Dlod(source, float4(uv + offset * ReShade::PixelSize, 0., LOD)).x;
}


float denoise(sampler source, float2 uv, uint scale) {
	float accum = 0.;
	float weights[9];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	float center_value = tex2Dlod(source, float4(uv, 0., 0.)).x;
	
	loop_3x3(weights[get_slice(dx, dy)] = GAUSS_3[get_slice(dx, dy)];
				 weights[get_slice(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy) * scale)); )
	loop_3x3(float val = tex2DoffsetLOD(source, uv, int2(dx, dy) * scale, (3. - tex2D(sAccumLength, uv).x)).x;
			 weights[get_slice(dx, dy)] *= color_similarity(val, center_value);
			 accum += val * weights[get_slice(dx, dy)];
			 cumulation += weights[get_slice(dx, dy)]; )
	
	return accum / cumulation;
}

float denoise_wide(sampler source, float2 uv) {
	float accum = 0.;
	float weights[49];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	float center_value = tex2Dlod(source, float4(uv, 0., 0.)).x;
	
	loop_7x7(weights[get_slice_wide(dx, dy)] = GAUSS_7[get_slice_wide(dx, dy)];
				 weights[get_slice_wide(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy))); )
	loop_7x7(float val = tex2DoffsetLOD(source, uv, int2(dx, dy), (3. - tex2Dlod(sAccumLength, float4(uv, 0., 0.)).x)).x;
			 accum += val * weights[get_slice_wide(dx, dy)];
			 cumulation += weights[get_slice_wide(dx, dy)]; )
	
	return accum / cumulation;
}

void denoise_0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0, out float updated_variance : SV_Target1) {
	if (tex2D(sAccumLength, uv).x < 4.0) {
		denoised = denoise_wide(sAO, uv);
	} else {
		denoised = denoise(sAO, uv, 1);
	}
}

void denoise_1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0) {
	denoised = denoise(sDenoised0, uv, 2);
}

void denoise_2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0) {
	denoised = denoise(sDenoised1, uv, 4);
}
#else
float normal_similarity(float3 center, float3 checked) {
	const float sigma = 3.;
	return pow(max(dot(center, checked), 0.), sigma);
}

float color_similarity(float3 center, float3 checked, float variance = 1.0) {
	const float sigma = 1.28;
	const float eps = 0.005;
	
	return exp(-distance(center, checked) / (sigma * sqrt(variance) + eps));
}

float4 tex2DoffsetLOD(sampler source, float2 uv, int2 offset, float LOD) {
	return tex2Dlod(source, float4(uv + offset * ReShade::PixelSize, 0., LOD));
}

// If anyone ever finds the code below some 10-so years down the line, I will immediatly get fired. 
texture tGuide { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sGuide { Texture = tGuide; };
void pls_dont_guide_i_am_noisy(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	output = tex2D(sAccumLength, uv).x > 4.0 ? 1. : 0.;
}

float4 denoise(sampler source, sampler variance_source, float2 uv, uint scale, bool self_guide, inout float variance = 1.0) {
	float4 accum = 0.;
	float weights[9];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	const float4 center_value = tex2Dlod(source, float4(uv, 0., 0.));
	
	float old_variance = variance;
	float variance_accumulation = 0.;
	loop_3x3(weights[get_slice(dx, dy)] = GAUSS_3[get_slice(dx, dy)];
				 weights[get_slice(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy) * scale)); )
	loop_3x3(float4 val = tex2DoffsetLOD(source, uv, int2(dx, dy) * scale, (3. - tex2Dlod(sAccumLength, float4(uv, 0., 0.)).x));
			 if (self_guide) weights[get_slice(dx, dy)] *= color_similarity(val.rgb, center_value.rgb, old_variance);
			 accum += val * weights[get_slice(dx, dy)];
			 cumulation += weights[get_slice(dx, dy)]; )
			 
	loop_3x3(float temp_var = tex2DoffsetLOD(variance_source, uv, int2(dx, dy), 0.).x;
			 variance_accumulation += temp_var * weights[get_slice(dx, dy)]; )
	
	variance = variance_accumulation / cumulation;
	return accum / cumulation;
}

float4 denoise_wide(sampler source, float2 uv) {
	float4 accum = 0.;
	float weights[49];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	const float4 center_value = tex2Dlod(source, float4(uv, 0., 0.));
	
	loop_7x7(weights[get_slice_wide(dx, dy)] = GAUSS_7[get_slice_wide(dx, dy)];
				 weights[get_slice_wide(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy))); )
	loop_7x7(float4 val = tex2DoffsetLOD(source, uv, int2(dx, dy), (3. - tex2D(sAccumLength, uv).x));
			 accum += val * weights[get_slice_wide(dx, dy)];
			 cumulation += weights[get_slice_wide(dx, dy)]; )
	
	return accum / cumulation;
}

float min_guide(float2 uv) {
	float min_v = 128.0;
	loop_3x3(min_v = min(min_v, tex2Doffset(sGuide, uv, int2(dx, dy)).x););
	
	return min_v;
}

void denoise_0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 denoised : SV_Target0, out float variance : SV_Target1) {
	variance = blur3x3_1(sVariance, uv, 1.0);

	if (min_guide(uv).x < 0.5) {
		denoised = denoise_wide(sGI, uv);
	} else {
		denoised = denoise(sGI, sVariance, uv, 1, true, variance);
	}
}

void denoise_1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 denoised : SV_Target0, out float variance : SV_Target1) {
	bool self_guide = tex2D(sGuide, uv).x > 0.5;
	variance = tex2D(sVarianceS, uv).x;
	
	denoised = denoise(sDenoised0g, sVarianceS, uv, 2, self_guide, variance);
}

void denoise_2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 denoised : SV_Target0, out float variance : SV_Target1) {
	bool self_guide = tex2D(sGuide, uv).x > 0.5;
	variance = tex2D(sVariance, uv).x;
	
	
	denoised = denoise(sDenoised1g, sVariance, uv, 4, self_guide, variance);
}

void denoise_3(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 denoised : SV_Target0, out float variance : SV_Target1) {
	bool self_guide = tex2D(sGuide, uv).x > 0.5;
	variance = tex2D(sVarianceS, uv).x;
	
	
	denoised = denoise(sDenoised0g, sVarianceS, uv, 8, self_guide, variance);
}
#endif