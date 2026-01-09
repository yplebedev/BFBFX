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

static const float GAUSS_3[9] = {
    1/16f, 1/8f, 1/16f, 
    1/8f, 1/4f, 1/8f, 
    1/16f, 1/8f, 1/16f, 
}; 

float blur3x3_1(sampler input, float2 uv, float scale) {
	float accum = 0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).r * GAUSS_3[(deltaX + 1) + 3*(deltaY + 1)];
		}
	}
	return accum;
}

#define SVGFDenoisePassInitial(name, level, GIsam, varSam) void name(pData, out float4 result : SV_Target0, out float updatedVariance : SV_Target1, out float4 recurrent_history : SV_Target2) {\
	float variance = blur3x3_1(varSam, uv, 1.0);\
	float4 denoised = atrous_advanced(GIsam, varSam, uv, level, variance);\
	result = denoised;\
	recurrent_history = denoised;\
	updatedVariance = variance;\
}


#define SVGFBindDenoisePass(name, func, GItex, VarTex) pass name {\
		STDVS;\
		PSBind(func);\
		RenderTarget0 = GItex;\
		RenderTarget1 = VarTex;\
	}
	
// hilariously borked, do not use,	
/*#define KERNEL_FIND_MIN(size_r, type, type_swizzle, sam, uv) 
		type minimum = 2e16;\
		for(int dx = -size_r; dx <= size_r; dx++) {\
			for(int dy = -size_r; dy <= size_r; dy++) {\
				minimum = min(tex2Doffset(sam, uv, int2(dx, dy)).type_swizzle, minimum);\
			}\
		}\*/
		