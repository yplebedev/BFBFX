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
	float luma = lin2ok(GI.rgb).r;
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
	float3 HDR = zfw::toneMapInverse(BackBuf, 10.0);
	
	float error = tex2D(sVariance, uv).x;
	
	float3 albedo = lerp(zfw::getAlbedo(uv), pow(BackBuf, 2.2), 0.5);
	return float4(zfw::toneMap(debug ? light.rgb + light.a * 0.01 : light.rgb * albedo * strength + HDR * light.a, 10.0), 1.0);
}

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
	pass Main {
		STDVS;
		PSBind(main);
		RenderTarget0 = tGI;
		RenderTarget1 = tLumaSquared;
	}
	pass ComputeVariance {
		STDVS;
		PSBind(computeVariance);
		RT(tVariance);
	}
	pass TAA {
		STDVS;
		PSBind(TAA);
		RenderTarget0 = tTAA;
		RenderTarget1 = tLumaSquaredTAA;
	}
	pass swapGI {
		STDVS;
		PSBind(swapGI);
		RenderTarget0 = tGIs;
		RenderTarget1 = tLumaSquaredS;
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
	pass Blend {
		STDVS;
		PSBind(blend);
	}
	pass SaveGBuffers {
		STDVS;
		PSBind(saveGbuffers);
		RT(tPrevG);
	}
}