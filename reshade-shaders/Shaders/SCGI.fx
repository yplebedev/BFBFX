#include "bfb_inc\GI.fxh"
#include "ReShade.fxh"
#include "bfb_inc\FrameworkResources.fxh"
#include "bfb_inc\macro.fxh"
#include "bfb_inc\meta.fxh"
#include "bfb_inc\VB.fxh"
#include "bfb_inc\denoise.fxh"
#include "bfb_inc\TAA.fxh"
#include "bfb_inc\multibounce.fxh"
#include "bfb_inc\settings.fxh"

void main(pData, out float4 GI : SV_Target0, out float lumaSquared : SV_Target1) {
	GI = calcGI(uv, vpos.xy);
	float luma = dot(GI.rgb, float3(0.2126, 0.7152, 0.0722));
	lumaSquared = luma * luma;
}

void swapGI(pData, out float4 GI : SV_Target0, out float lumaSquared : SV_Target1) {
	GI = tex2Dfetch(sTAA, vpos.xy);
	lumaSquared = tex2Dfetch(sLumaSquaredTAA, vpos.xy).r;
}

SVGFDenoisePassInitial(denoise0, 0, sTAA, sVariance)
SVGFDenoisePass(denoise1, 1, sDNGI, sVarianceS)
SVGFDenoisePass(denoise2, 2, sDNGIs, sVariance)
SVGFDenoisePass(denoise3, 3, sDNGI, sVarianceS)


fastPS(blend) {
	float tonemapWhite = exp(tonemapWhite);
	
	float4 light = tex2D(sDNGIs, uv);

	float3 BackBuf = tex2Dfetch(ReShade::BackBuffer, vpos.xy).rgb;	
	float3 HDR = zfw::toneMapInverse(BackBuf, tonemapWhite);
	
	float error = tex2D(sVariance, uv).x;
	
	float3 albedo = lerp(zfw::getAlbedo(uv), pow(BackBuf, 2.2), protect);
	return float4(zfw::toneMap(debug ? light.rgb + light.a * 0.01 : light.rgb * albedo * strength + HDR * pow(light.a, ao_strength), tonemapWhite), 1.0);
}

// note to UKN:
// 	this is not "for poking" per se, but a small bit of shader code that should be !!excluded!! from public "compiled binaries",
// 	and as such is all covered with preprocs. You may define it globaly, but tbch I have no clue what you'd get from that.
#ifdef DEBUG_ADDON
	texture tGIdbg { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA32F; };

	fastPS(extraHighQuality) {
		return calcGI(uv, vpos.xy, 1, 12);
	}

	texture tTestDBG { Width = 240; Height = 150; Format = RGBA8; };

	fastPS(writeTest) {
		return uv.xyxy;
	}
#endif



technique SCGI techniqueGIDesc {
	pass Expand {
		STDVS;
		PSBind(expand);
		RT(tExpRejMask);
	}
	pass Radiance {
		STDVS;
		PSBind(preCalcRadiance);
		RT(tRadiance);
	}
	pass IncrementAccumulation {
		STDVS;
		PSBind(incrementAccum);
		RenderTarget0 = tAccum;
	}
	pass SwapAccumulation {
		STDVS;
		PSBind(swapAccum);
		RT(tAccumS);
	}
	pass Main {
		STDVS;
		PSBind(main);
		RenderTarget0 = tGI;
		RenderTarget1 = tLumaSquared;
	}
	pass swapGI {
		STDVS;
		PSBind(swapGI);
		RenderTarget0 = tGIs;
		RenderTarget1 = tLumaSquaredS;
	}
	#ifdef DEBUG_ADDON
		pass UltraHigh {
			STDVS;
			PSBind(extraHighQuality);
			RT(tGIdbg);
		}
		pass WriteTest {
			STDVS;
			PSBind(writeTest);
			RT(tTestDBG);
		}
	#endif
	pass TAA {
		STDVS;
		PSBind(TAA);
		RenderTarget0 = tTAA;
		RenderTarget1 = tLumaSquaredTAA;
	}
	pass ComputeVariance {
		STDVS;
		PSBind(computeVariance);
		RT(tVariance);
	}
	pass Denoise0 {
		STDVS;
		PSBind(denoise0);
		RenderTarget0 = tDNGI;
		RenderTarget1 = tVarianceS;
	}
	pass Denoise1 {
		STDVS;
		PSBind(denoise1);
		RenderTarget0 = tDNGIs;
		RenderTarget1 = tVariance;
	}
	pass Denoise2 {
		STDVS;
		PSBind(denoise2);
		RenderTarget0 = tDNGI;
		RenderTarget1 = tVarianceS;
	}
	pass Denoise3 {
		STDVS;
		PSBind(denoise3);
		RenderTarget0 = tDNGIs;
		RenderTarget1 = tVariance;
	}
	pass Blend {
		STDVS;
		PSBind(blend);
	}
}