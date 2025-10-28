#include "ReShade.fxh"
#include "soupcan_includes/FrameworkResources.fxh"
#define PI 3.14159265

texture tHalfBB { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler sHalfBB { Texture = tHalfBB; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };


texture tSSR { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSR { Texture = tSSR; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tRes { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sRes { Texture = tRes; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

	

//uniform float THICKNESS <ui_type = "slider"; ui_min = 0.1; ui_max = 100.0;> = 2.0;
uniform float radius <ui_type = "slider"; ui_min = 1.0; ui_max = 500.0;> = 30.0;
uniform uint steps <ui_type = "slider"; ui_min = 2; ui_max = 100;> = 10;
uniform float strength <ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;> = 0.3;

uniform bool debug = false;

namespace Rays {
	struct Ray {
		float3 origin;
		float3 direction;
	};
	float3 at(Ray r, float t) {
		return r.origin + t * r.direction;
	}
	Ray castReflRay(float3 pos, float3 normal) {
		float3 v = -normalize(pos);
		Ray r;
		r.origin = pos + normal * 0.0002;
		r.direction = reflect(v, normal);
		return r;
	}
}

float3 ssr(float3 normal, float3 pos) {
	Rays::Ray ray = Rays::castReflRay(pos, normal);
	
	float3 hitCol = 0.0;
	[loop]
	for (uint i = 0; i < steps; i++) {
		float fi = float(i);
		float3 stepPos = Rays::at(ray, (fi * radius));
		float3 stepUV = zfw::viewToUv(stepPos);
		
		if (stepUV.y < 0.0 || stepUV.y > 1.0 || stepUV.x < 0.0 || stepUV.x > 1.0) break;
		if (stepUV.z > zfw::getDepth(stepUV.xy) /*&& stepUV.z < zfw::getDepth(stepUV.xy) + THICKNESS / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE*/) { hitCol = tex2Dlod(sHalfBB, float4(stepUV.xy, 0., 0.)).rgb; }
	}
	return hitCol;
}

float4 prepHalfBB(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float3 mv = zfw::getVelocity(uv);
	return float4(zfw::toneMapInverse(tex2Dfetch(ReShade::BackBuffer, vpos.xy * 2.0).rgb, 4.0), 1.0);
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 mix : SV_Target0, out float4 o_ssr : SV_Target1) {
	float3 normal = zfw::getNormal(uv);
	float z = zfw::getDepth(uv);
	float3 pos = zfw::uvzToView(uv, z);

	float3 hdr = zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 4.0);
	float coeff = 0.04 + ((1.0 - 0.04)*pow(1.0 - dot(normal, -normalize(pos)), 5.0));
	float3 spec = ssr(normal, pos);
	
	//float3 accumSpec = tex2D(sSSRswap, uv + mv.xy).rgb;
	//spec = lerp(spec, accumSpec, rcp(1.0 + float(tex2D(sAccumL, uv))));
	
	o_ssr = float4(spec, 1.0);
	hdr = lerp(hdr, spec, coeff * strength);
	mix = debug ? spec.rgb : hdr;
}

float4 blend(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target0{
	return zfw::toneMap(tex2Dfetch(sRes, vpos.xy).rgb, 4.0).rgbg;
}



technique SCSSR {
	pass prepHalfBB {
		VertexShader = PostProcessVS;
		PixelShader = prepHalfBB;
		RenderTarget = tHalfBB;
	}
	pass main {
		VertexShader = PostProcessVS;
		PixelShader = main;
		RenderTarget0 = tRes;
		RenderTarget1 = tSSR;
	}
	pass blend {
		VertexShader = PostProcessVS;
		PixelShader = blend;
	}
}