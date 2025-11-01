#include "ReShade.fxh"
#include "bfb_inc\FrameworkResources.fxh"
#include "bfb_inc\macro.fxh"
#include "bfb_inc\meta.fxh"
#include "bfb_inc\VB.fxh"
#include "bfb_inc\TAA.fxh"
#include "bfb_inc\settings.fxh"

fastPS(main) {
	float3 mv = zfw::getVelocity(uv);
	float weight = (1.0-getLerpWeight(uv)) * mv.z;
	return lerp(calcAO(uv, vpos.xy), tex2D(sAOs, uv + mv.xy), weight);
}

fastPS(swapAO) {
	return tex2Dfetch(sAO, vpos.xy);
}

fastPS(blend) {
	float AO = tex2Dfetch(sAO, vpos.xy).x;
	AO = pow(AO, strength);
	float3 BackBuf = zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, tonemapWhite);
	
	float3 mix = BackBuf * AO;
	return float4(zfw::toneMap(mix, tonemapWhite), 1.0);
}

technique SCAO techniqueDesc {
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
		RenderTarget0 = tAccumS;
	}
	pass Blend {
		STDVS;
		PSBind(blend);
	}
}