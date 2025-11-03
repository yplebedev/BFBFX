#include "ReShade.fxh"

texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAO { Texture = tAO; };

texture tAOs { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAOs { Texture = tAOs; };

texture tAccum { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccum { Texture = tAccum; };

texture tAccumS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumS { Texture = tAccumS; };

void incrementAccum(pData, out uint incremented : SV_Target0) {
	incremented = tex2D(sAccumS, uv) + 1u;
}

void swapAccum(pData, out uint swapped : SV_Target0) {
	swapped = tex2D(sAccum, uv);
	if (zfw::getVelocity(uv).z < 1.0) {
		swapped = 0u;
		return;
	}
	swapped = clamp(swapped, 1u, 256u); 
}

float getLerpWeight(float2 uv) {
	return 0.9 * rcp(1.0 + float(tex2D(sAccumS, uv)));
}