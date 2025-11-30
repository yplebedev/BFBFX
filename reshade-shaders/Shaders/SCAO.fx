#include "ReShade.fxh"
#include "bfb_inc\FrameworkResources.fxh"
#include "bfb_inc\macro.fxh"
#include "bfb_inc\meta.fxh"
#include "bfb_inc\VB.fxh"
#include "bfb_inc\denoise.fxh"
#include "bfb_inc\TAA.fxh"
#include "bfb_inc\settings.fxh"


fastPS(main) {
	float3 mv = zfw::getVelocity(uv);
	float weight = (getLerpWeight(uv)) * tex2D(sExpRejMask, uv).r;
	return lerp(calcAO(uv, vpos.xy), tex2D(sAOs, uv + mv.xy), weight);
}

fastPS(swapAO) {
	return tex2Dfetch(sAO, vpos.xy);
}

fastPS(denoise) {
	return atrous(sAOs, uv, 0.);
}

fastPS(blend) {
	bool useMip = tex2Dfetch(sAccumS, vpos.xy) < 4u;
	float tonemapWhite = exp(tonemapWhite);
	float AO = tex2Dlod(sDNAO, float4(uv.xy, 0., useMip)).x;
	AO = pow(AO, strength);
	float3 BackBuf = zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, tonemapWhite);
	
	float3 mix = BackBuf * AO;
	return float4(debug ? AO : zfw::toneMap(mix, tonemapWhite), 1.0);
}

technique SCAO techniqueDesc {
	pass Expand {
		STDVS;
		PSBind(expand);
		RT(tExpRejMask);
	}
	pass Main {
		STDVS;
		PSBind(main);
		RT(tAO);
	}
	pass SwapAO {
		STDVS;
		PSBind(swapAO);
		RT(tAOs);
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
	pass Denoise {
		STDVS;
		PSBind(denoise);
		RT(tDNAO);
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