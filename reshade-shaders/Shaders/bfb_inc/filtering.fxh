#pragma once
#include "OpenRSF.fxh"


texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sAO { Texture = tAO; };

texture tAOhistory { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format=R16; };
sampler sAOhistory { Texture = tAOhistory; };

texture tAccumLength { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32F; };
sampler sAccumLength { POINT_SAMPLE; Texture = tAccumLength; };

void increment(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float by : SV_Target0) {
	by = 1.;
}

float min3x3(sampler input, float2 uv) {
	float min_found = 1.0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * float2(deltaX, deltaY);
			min_found = min(min_found, tex2Dlod(input, float4(uv + offset, 0., 0.)).z );
		}
	}
	return min_found;
}

void reset(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float accumulation : SV_Target0) {
	float disocclusion = min3x3(ORSFShared::sMotion, uv);
	accumulation = (disocclusion > 0.8) ? 100000. : 0.;
}

void clamp(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float max : SV_Target0) {
	max = 128.0;
}



void copy_ao(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	output = tex2D(sAO, uv).r;
}