#pragma once
#include "OpenRSF.fxh"

#define MODE BORDER
#define ADDRESS\
AddressU = MODE;\
AddressV = MODE;\
AddressW = MODE

texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sAO { Texture = tAO; };

texture tAOhistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sAOhistory { Texture = tAOhistory; ADDRESS; };

texture tAccumLength { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; };
sampler sAccumLength { POINT_SAMPLE; Texture = tAccumLength; };

texture tDenoised0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sDenoised0 { Texture = tDenoised0; };

texture tDenoised1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sDenoised1 { Texture = tDenoised1; };

void increment(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float by : SV_Target0) {
	by = 1.;
}

float min3x3(sampler input, float2 uv) {
	float min_found = 1.0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * float2(deltaX, deltaY);
			float3 curr_sample = tex2Dlod(input, float4(uv + offset, 0., 0.)).xyz;
			min_found = min(min_found, curr_sample.z);
		}
	}
	return min_found;
}


bool onscreen(float2 uv) {
	// could be 0.5, but this is more robust (check border)
	const float threshold = 0.5 - max(ReShade::PixelSize.x, ReShade::PixelSize.y);
	float2 clip_h = abs(uv - 0.5);
	return clip_h.x < threshold && clip_h.y < threshold;
}

void reset(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float accumulation : SV_Target0) {
	float disocclusion = min3x3(ORSFShared::sMotion, uv);
	float3 motion = getMotion(uv);// 								    keep      restart
	accumulation = ((disocclusion > 0.8) && onscreen(uv + motion.xy)) ? 100000. : 0.;
}

void clamp(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float max : SV_Target0) {
	max = 32.0;
}


void copy_ao(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	output = tex2D(sAO, uv).r;
}

#define loop_3x3(callback)\
for (int dx = -1; dx <= 1; dx++) {\
for (int dy = -1; dy <= 1; dy++) {\
	callback;\
}\
}\

#define loop_7x7(callback)\
for (int dx = -3; dx <= 3; dx++) {\
for (int dy = -3; dy <= 3; dy++) {\
	callback;\
}\
}\

uint get_slice(int dx, int dy) {
	return (dx + 1) + 3*(dy + 1);
}

uint get_slice_wide(int dx, int dy) {
	return (dx + 3) + 7*(dy + 3);
}

float3 getNormalOffset(float2 uv, int2 offset) {
	return normalize(UVtoOCT(tex2Doffset(ORSFShared::sTexN, uv, offset).xy));
}

float normal_similarity(float3 center, float3 checked) {
	const float sigma = 2.;
	return pow(max(dot(center, checked), 0.), sigma);
}

float color_similarity(float center, float checked) {
	const float sigma = 16.;
	const float eps = .1;
	return exp(-abs(center - checked) / (sigma + eps));
}

float denoise(sampler source, float2 uv, uint scale) {
	float accum = 0.;
	float weights[9];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	float center_value = tex2Dlod(source, float4(uv, 0., 0.)).r;
	
	loop_3x3(weights[get_slice(dx, dy)] = GAUSS_3[get_slice(dx, dy)];
				 weights[get_slice(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy) * scale)) )
	loop_3x3(float val = tex2Doffset(source, uv, int2(dx, dy) * scale).x;
			 weights[get_slice(dx, dy)] *= color_similarity(val, center_value);
			 accum += val * weights[get_slice(dx, dy)];
			 cumulation += weights[get_slice(dx, dy)] )
	
	return accum / cumulation;
}

float denoise_wide(sampler source, float2 uv) {
	float accum = 0.;
	float weights[49];
	float cumulation = 0.;
	
	float3 center_normal = getNormal(uv);
	float center_value = tex2Dlod(source, float4(uv, 0., 0.)).r;
	
	loop_7x7(weights[get_slice_wide(dx, dy)] = GAUSS_7[get_slice_wide(dx, dy)];
				 weights[get_slice_wide(dx, dy)] *= normal_similarity(center_normal, getNormalOffset(uv, int2(dx, dy))) )
	loop_7x7(float val = tex2Doffset(source, uv, int2(dx, dy)).x;
			 accum += val * weights[get_slice_wide(dx, dy)];
			 cumulation += weights[get_slice_wide(dx, dy)] )
	
	return accum / cumulation;
}

void denoise_0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0) {
	if (tex2D(sAccumLength, uv).x < 4.0) {
		denoised = denoise_wide(sAO, uv);
		return;
	} else {
		denoised = denoise(sAO, uv, 1);
	}
}

void denoise_1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0) {
	denoised = denoise(sAO, uv, 2);
}

void denoise_2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float denoised : SV_Target0) {
	denoised = denoise(sAO, uv, 4);
}