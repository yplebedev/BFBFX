#pragma once
#include "ReShade.fxh"

texture tExpRejMask { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sExpRejMask { Texture = tExpRejMask; };

// AO only
texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 4; };
sampler sAO { Texture = tAO; };

texture tAOs { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sAOs { Texture = tAOs; };

// GI
texture tGI { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 4; };
sampler sGI { Texture = tGI; MinLOD = 0.0f; MaxLOD = 3.0f;  };

texture tGIs { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sGIs { Texture = tGIs; };

texture tTAA { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 6; };
sampler sTAA { Texture = tTAA; MinLOD = 0.0f; MaxLOD = 5.0f; };


// svgf
texture tLumaSquaredTAA { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sLumaSquaredTAA { Texture = tLumaSquaredTAA; };

texture tLumaSquared { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 6; };
sampler sLumaSquared { Texture = tLumaSquared; MinLOD = 0.0f; MaxLOD = 5.0f; };

texture tLumaSquaredS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sLumaSquaredS { Texture = tLumaSquaredS; };



texture tAccum { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccum { Texture = tAccum; };

texture tAccumS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumS { Texture = tAccumS; };

texture tPrevG { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sPrevG { Texture = tPrevG; };

void incrementAccum(pData, out uint incremented : SV_Target0) {
	incremented = tex2D(sAccumS, uv) + 1u;
}

void swapAccum(pData, out uint swapped : SV_Target0) {
	swapped = tex2D(sAccum, uv);
	if (tex2D(sExpRejMask, uv).r < 0.05) {
		swapped = 1u; // if it runs after GI, one frame is always correct*
		return;
	}
	swapped = clamp(swapped, 1u, 256u); 
}

float getLerpWeight(float2 uv) {
	float3 mv = zfw::getVelocity(uv);
	float initial = (1.0 - rcp(1.0 + float(tex2D(sAccumS, uv)))) * tex2D(sExpRejMask, uv).r;
	
	initial = saturate(initial + 0.4) * 0.98;
	
	return initial * mv.z;
}

namespace FrameWork {
	texture2D tTempN0 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
	sampler2D sTempN0 { Texture = tTempN0; };
	
	float3 getRejN(float2 uv) {
		return tex2D(FrameWork::sTempN0, uv).rgb;
	}
}

float getNormalRejection(float2 uv, float2 mv) {
	return pow(dot(FrameWork::getRejN(uv), tex2D(sPrevG, uv + mv).xyz), 3.0);
}

float getZRejection(float2 uv, float2 mv) {
	float CD = zfw::getDepth(uv);
	float PD = tex2D(sPrevG, uv + mv).w;
	return min(saturate(pow(PD / CD, 10.0)), saturate(pow(CD / PD, 5.0)));
}

fastPS(expand) {
	float minW = 1.0;
	
	for (int delX = -1; delX <= 1; delX++) {
		for (int delY = -1; delY <= 1; delY++) {
			float2 uvOffset = float2(delX, delY)*BUFFER_PIXEL_SIZE;
			float3 mv = zfw::getVelocity(uv + uvOffset);
			float w = getNormalRejection(uv + uvOffset, mv.xy) * getZRejection(uv + uvOffset, mv.xy);
			minW = min(minW, w);
		}
	}
	
	return minW;
}

void TAA(pData, out float4 resolved : SV_Target0, out float sumOfSquares : SV_Target1) {
	float3 mv = zfw::getVelocity(uv);
	float weight = getLerpWeight(uv);
	
	resolved = lerp(tex2D(sGI, uv), tex2D(sGIs, uv + mv.xy), weight);
	sumOfSquares = lerp(tex2D(sLumaSquared, uv).r, tex2D(sLumaSquaredS, uv + mv.xy).r, weight);
}



fastPS(saveGbuffers) {
	return float4(FrameWork::getRejN(uv), zfw::getDepth(uv));
}