#pragma once
#include "bfb_inc\TAA.fxh"
#include "bfb_inc\denoise.fxh"

texture tRadiance { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; MipLevels = 4; };
sampler sRadiance { Texture = tRadiance; MinLOD = 0.0f; MaxLOD = 7.0f; };

fastPS(preCalcRadiance) {
	float3 mv = zfw::getVelocity(uv);
	float rej = tex2D(sExpRejMask, uv).r;
	return float4(zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 10.0) + rej * (zfw::getAlbedo(uv) * tex2D(sDNGIs, uv + mv.xy).rgb), 1.0);
}