#pragma once
// Don't you hate the atrocious C syntax? You do? Too bad, this doesn't fix it.


// void name(pdata, out typen outName) { ... }
#define pData float4 vpos : SV_Position, float2 uv : TEXCOORD

// fastPS(name)
#define fastPS(x) float4 x(pData) : SV_Target

// bindFastPS(passName, functionName)
#define bindFastPS(x, y) pass x {\
							VertexShader = PostProcessVS;\
							PixelShader = y;\
						 }

// pass xyz { STDVS; PSBind = functionName; RT(n) = texName; }
#define STDVS VertexShader = PostProcessVS
#define PSBind(name) PixelShader = name
#define RT(name) RenderTarget = name

// c++ bs
#define cbrtf(x) pow(x, 0.3333) 


/*void denoise3(pData, out float4 result : SV_Target0, out float AO : SV_Target1) {
	float variance = tex2D(sDNGI, uv).a;
	float4 denoised = atrous_advanced(sDNGI, sDNAO, uv, 1, variance);
	result = float4(denoised.rgb, variance);
	AO = denoised.a;
}*/
#define SVGFDenoisePass(name, level, GIsam, varSam) void name(pData, out float4 result : SV_Target0, out float updatedVariance : SV_Target1) {\
	float variance = tex2D(varSam, uv).r;\
	float4 denoised = atrous_advanced(GIsam, varSam, uv, level, variance);\
	result = denoised;\
	updatedVariance = variance;\
}

#define SVGFDenoisePassInitial(name, level, GIsam, varSam) void name(pData, out float4 result : SV_Target0, out float updatedVariance : SV_Target1) {\
	float variance = tex2Dlod(varSam, float4(uv, 0., 0.0)).r;\
	float4 denoised = atrous_advanced(GIsam, varSam, uv, level, variance);\
	result = denoised;\
	updatedVariance = variance;\
}


#define SVGFBindDenoisePass(name, func, GItex, VarTex) pass name {\
		STDVS;\
		PSBind(func);\
		RenderTarget0 = GItex;\
		RenderTarget1 = VarTex;\
	}