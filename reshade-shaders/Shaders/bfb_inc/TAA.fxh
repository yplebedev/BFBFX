#include "ReShade.fxh"

texture tExpRejMask { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sExpRejMask { Texture = tExpRejMask; };

texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; MipLevels = 4; };
sampler sAO { Texture = tAO; MinLOD = 0.0f; MaxLOD = 3.0f;  };

texture tAOs { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; };
sampler sAOs { Texture = tAOs; };

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
	if (zfw::getVelocity(uv).z < 1.0) {
		swapped = 0u;
		return;
	}
	swapped = clamp(swapped, 0u, 256u); 
}

float getLerpWeight(float2 uv) {
	return rcp(1.0 + float(tex2D(sAccumS, uv)));
}

float getNormalRejection(float2 uv, float2 mv) {
	return pow(dot(zfw::getNormal(uv), tex2D(sPrevG, uv + mv).xyz), 3.0);
}

float getZRejection(float2 uv, float2 mv) {
	float CD = zfw::getDepth(uv);
	float PD = tex2D(sPrevG, uv + mv).w;
	return min(saturate(pow(PD / CD, 10.0)), saturate(pow(CD / PD, 5.0)));
}