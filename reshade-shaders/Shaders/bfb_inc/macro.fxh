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