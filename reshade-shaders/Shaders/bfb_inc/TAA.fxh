#pragma once
#include "ReShade.fxh"
#include "bfb_inc\settings.fxh"


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

float3 lin2ok(float3 c) 
{
    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
	float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
	float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;

    float l_ = cbrtf(l);
    float m_ = cbrtf(m);
    float s_ = cbrtf(s);

    return float3(
        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_
    );
}

float3 ok2lin(float3 c) 
{
    float l_ = c.r + 0.3963377774f * c.g + 0.2158037573f * c.b;
    float m_ = c.r - 0.1055613458f * c.g - 0.0638541728f * c.b;
    float s_ = c.r - 0.0894841775f * c.g - 1.2914855480f * c.b;

    float l = l_*l_*l_;
    float m = m_*m_*m_;
    float s = s_*s_*s_;

    return float3(
		+4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
		-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
		-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s
    );
}

void incrementAccum(pData, out uint incremented : SV_Target0) {
	incremented = tex2D(sAccumS, uv) + 1u;
}

void swapAccum(pData, out uint swapped : SV_Target0) {
	swapped = tex2D(sAccum, uv);
	if (tex2D(sExpRejMask, uv).r < 0.6) {
		swapped = 1u; // if it runs after GI, one frame is always correct*
		return;
	}
	swapped = clamp(swapped, 1u, 64u*2u); 
}

float getLerpWeight(float2 uv) {
	float3 mv = zfw::getVelocity(uv);
	
	
	return mv.z * (1.0 - rcp(1.0 + float(tex2D(sAccumS, uv))));
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
			float w = mv.z;
			minW = min(minW, w);
		}
	}
	
	return minW;
}

float3 tex2DoffsetLOD(sampler sam, float2 uv, int2 offset, float LOD) {
	float2 offsetUV = ReShade::PixelSize * ((float2)offset);
	return tex2Dlod(sam, float4(uv + offsetUV, 0., LOD)).rgb;
}

void TAA(pData, out float4 resolved : SV_Target0, out float sumOfSquares : SV_Target1) {
	float3 mv = zfw::getVelocity(uv);
	float weight = getLerpWeight(uv);
	float4 history = tex2D(sGIs, uv + mv.xy);
	
	#ifdef GI_D
		resolved = lerp(tex2D(sGI, uv), history, weight);
		sumOfSquares = lerp(tex2D(sLumaSquared, uv).r, tex2D(sLumaSquaredS, uv + mv.xy).r, weight); // initial estimate, replaced later
	
		float variance = (lin2ok(resolved).r * lin2ok(resolved).r) - (sumOfSquares.r);
		float sigma = sqrt(variance);
		
		const int size_r = 2;
		float3 minimum = 2e16f;
		float3 maximum = -2e16f;
		
		for(int dx = -size_r; dx <= size_r; dx++) {
			for(int dy = -size_r; dy <= size_r; dy++) {
				float3 value = tex2DoffsetLOD(sGI, uv, int2(dx, dy) * 2, 1.0).rgb;
				minimum = min(value, minimum);
				maximum = max(value, maximum);
			}
		}
		
		if (do_clamp) {
			const float allowance = 0.01; // ad-hoc allowed deviation
			history.rgb = clamp(history.rgb, minimum - sigma * allowance, maximum + sigma * allowance);
		}
	#endif
	
	resolved = lerp(tex2D(sGI, uv), history, weight);
	sumOfSquares = lerp(tex2D(sLumaSquared, uv).r, tex2D(sLumaSquaredS, uv + mv.xy).r, weight);
}



fastPS(saveGbuffers) {
	return float4(FrameWork::getRejN(uv), zfw::getDepth(uv));
}