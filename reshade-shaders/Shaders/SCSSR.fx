#include "ReShade.fxh"
#include "soupcan_includes/FrameworkResources.fxh"
#define PI 3.14159265

texture tHalfBB { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
sampler sHalfBB { Texture = tHalfBB; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tAccumL { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumL { Texture = tAccumL; MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tAccumLswap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumLswap { Texture = tAccumLswap; MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tPrevD { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; };
sampler sPrevD { Texture = tPrevD; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tPrevN { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sPrevN { Texture = tPrevN; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	

texture tSSR { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSR { Texture = tSSR; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture tRadiance { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sRadiance { Texture = tRadiance; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture tSSRswap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sSSRswap { Texture = tSSRswap; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

texture tRes { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sRes { Texture = tRes; AddressU = BORDER; AddressV = BORDER;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };

	

uniform float THICKNESS <ui_type = "slider"; ui_min = 0.1; ui_max = 100.0;> = 2.0;
uniform float radius <ui_type = "slider"; ui_min = 1.0; ui_max = 500.0;> = 30.0;
uniform uint steps <ui_type = "slider"; ui_min = 2; ui_max = 100;> = 10;
uniform float strength <ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;> = 0.3;
uniform float rough <ui_type = "slider"; ui_min = 0.0; ui_max = 0.999;> = 0.1;

uniform bool debug = false;

uniform int framecount < source = "framecount"; >;

// https://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
float r2(uint idx) {
	const float g = 1.6180339887498948482;
	const float a1 = 1.0/g;
	return frac(0.5+a1*float(idx));
}

float hash14(float4 p4) {
	p4 = frac(p4  * float4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return frac((p4.x + p4.y) * (p4.z + p4.w));
}

// https://www.shadertoy.com/view/4djSRW
float2 hash23(float3 p3) {
	p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

// https://gist.github.com/andrewbolster/10274979
// rejection would work, but it would also force everything to wait 
// until one pixel finishes hitting the unit sphere.
// Bad copium past me, very bad.
float3 randomDir(float2 r) {
	float phi = r.x * 2 * PI;
	float cosT = r.y * 2 - .5;
	
	float theta = acos(cosT);
	return float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
}

// high value == safe
float getRejectCond(float3 mv, float depthDiff, float nDiff) {
	return mv.z * pow(nDiff, 3.0) * saturate(rcp(depthDiff + 0.0001));
}

namespace Rays {
	struct Ray {
		float3 origin;
		float3 direction;
	};
	float3 at(Ray r, float t) {
		return r.origin + t * r.direction;
	}
	Ray castReflRay(float3 pos, float3 normal, float2 vpos) {
		Ray r;
		r.origin = pos + normal * 0.00001;
		r.direction = reflect(normalize(pos), normal);
		return r;
	}
	Ray castReflRayNoisy(float3 pos, float3 normal, float2 vpos, float rad) {
		Ray r;
		r.origin = pos + normal * 0.00001;
		r.direction = reflect(normalize(pos), normal) + randomDir(hash23(float3(pos.xy, (framecount % 1024)))) * rad;
		r.direction = normalize(r.direction);
		return r;
	}
}

float3 ssr(float2 uv, float2 vpos, float3 normal, float z) {
	float3 pos = zfw::uvzToView(uv, z);
	
	Rays::Ray ray = Rays::castReflRayNoisy(pos, normal, vpos.xy, zfw::getRoughness(uv));
	
	float3 hitCol = 0.0;
	[loop]
	for (uint i = 1; i <= steps; i++) {
		float fi = float(i);
		float3 stepPos = Rays::at(ray, (fi * fi + hash14(float4(fi, vpos, framecount % 1024))* 15.0) / float(steps) * radius);
		float3 stepUV = zfw::viewToUv(stepPos);
		if (stepUV.z > zfw::getDepth(stepUV.xy) && stepUV.z < zfw::getDepth(stepUV.xy) + THICKNESS / RESHADE_DEPTH_LINEARIZATION_FAR_PLANE) { hitCol = tex2Dlod(sHalfBB, float4(stepUV.xy, 0., 0.)).rgb; }
	}
	return hitCol;
}

float4 prepHalfBB(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float3 mv = zfw::getVelocity(uv);
	return tex2Dfetch(ReShade::BackBuffer, vpos.xy * 2.0) + tex2D(sSSR, uv + mv.xy);
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 mix : SV_Target0, out float4 o_ssr : SV_Target1) {
	float3 mv = zfw::getVelocity(uv);
	
	float3 normal = zfw::getNormal(uv);
	float z = zfw::getDepth(uv);
	float3 pos = zfw::uvzToView(uv, z);

	float3 hdr = zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 20.0);
	float coeff = (0.04 + (1.0 - 0.04)*pow(1.0 - dot(normal, -normalize(pos)), 5.0));
	float3 spec = ssr(uv, vpos.xy, normal, z);
	
	float3 accumSpec = tex2D(sSSRswap, uv + mv.xy).rgb;
	spec = lerp(spec, accumSpec, 0.97 * rcp(1.0 + float(tex2D(sAccumL, uv))));
	
	o_ssr = float4(spec, 1.0);
	hdr = lerp(hdr, spec, coeff * strength);
	mix = debug ? spec.rgb : zfw::toneMap(hdr, 20.0);
}

float4 blend(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target0{
	return tex2Dfetch(sRes, vpos.xy);
}

void updateAccum(float4 vpos : SV_Position, float2 uv : TEXCOORD, out uint curAccum : SV_Target0) {
	float3 mv = zfw::getVelocity(uv);
	
	float depthDelta = zfw::getDepth(uv - mv.xy) - tex2D(sPrevD, uv).x;
	float depthDiff = abs(depthDelta);
	
	float nDiff = saturate(dot(zfw::getNormal(uv - mv.xy), tex2D(sPrevN, uv).xyz));
	float rej = getRejectCond(mv, depthDiff, nDiff);
	
	// :)
	curAccum = uint(ceil(tex2D(sAccumLswap, uv) * rej)) + 1u;
}

void updateAccumSwap(float4 vpos : SV_Position, float2 uv : TEXCOORD, out uint curAccumSwap : SV_Target0) {
	curAccumSwap = tex2D(sAccumL, uv);
}

void swapSSR(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 o_ssr : SV_Target0) {
	o_ssr = tex2Dfetch(sSSR, vpos.xy);
}

float saveForRejectZ(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return zfw::getDepth(uv);
}

float4 saveForRejectN(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return zfw::getNormal(uv).xyzz;
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
	pass swapSSR {
		VertexShader = PostProcessVS;
		PixelShader = swapSSR;
		RenderTarget = tSSRswap;
	}
	pass SaveDepth {
		VertexShader = PostProcessVS;
		PixelShader = saveForRejectZ;
		RenderTarget = tPrevD;
	}
	pass SaveNormal {
		VertexShader = PostProcessVS;
		PixelShader = saveForRejectN;
		RenderTarget = tPrevN;
	}
}