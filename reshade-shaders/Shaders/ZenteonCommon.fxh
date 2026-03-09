#pragma once

// Should I even distribute it? A hard dep to your shaders might be "ideal" but it will be PITA to deal with on scale.

#define HDR 1.05, 0, 0
#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
//#define iRES rcp(float2(BUFFER_WIDTH, BUFFER_HEIGHT))
#define FARPLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define ASPECT_RATIO (RES.x/RES.y)
#define IASPECT_RATIO float2(1.0, RES.x / RES.y)
#define PASPECT_RATIO float2(1.0, RES.y / RES.x)

#define WRAPMODE(WTYPE) AddressU = WTYPE; AddressV = WTYPE; AddressW = WTYPE
#define FILTER(FTYPE) MagFilter = FTYPE; MinFilter = FTYPE; MipFilter = FTYPE

#define CS_INPUTS uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID
#define DIV_RND_UP(a, b) ((int(a)+int(b)-1)/int(b))
#define DISPATCH_RES(X, Y, DIS_RES_DIV) DispatchSizeX = DIV_RND_UP(RES.x, X * DIS_RES_DIV); DispatchSizeY = DIV_RND_UP(RES.y, Y * DIS_RES_DIV)


#define DIVRES_DEP(DIVRES_RIV, DEP) Width = DIV_RND_UP(RES.x, DIVRES_RIV); Height = DIV_RND_UP(RES.y, DIVRES_RIV); Depth = DEP
#define DIVRES(DIVRES_RIV) Width = DIV_RND_UP(RES.x, DIVRES_RIV); Height = DIV_RND_UP(RES.y, DIVRES_RIV)
#define DIVRES_N(DIVRES_RIV, NRES) Width = DIV_RND_UP(NRES.x, DIVRES_RIV); Height = DIV_RND_UP(NRES.y, DIVRES_RIV)


#define PS_INPUTS float4 vpos : SV_Position, float2 xy : TEXCOORD0

//Pass helpers

#define PASS0(iPS) VertexShader = PostProcessVS; PixelShader = iPS
#define PASS1(iPS, oRT) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget = oRT
#define PASS2(iPS, oRT0, oRT1) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1
#define PASS3(iPS, oRT0, oRT1, oRT2) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1; RenderTarget2 = oRT2
#define PASS4(iPS, oRT0, oRT1, oRT2, oRT3) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1; RenderTarget2 = oRT2; RenderTarget3 = oRT3


#define IGNSCROLL 5.588238

//===================================================================================
//Projections
//===================================================================================

float GetDepth(float2 xy)
{
	return ReShade::GetLinearizedDepth(xy);
}


#define FOV (1.0 * 0.0174533 * 70.0)
#define fl rcp(tan(0.5 * FOV))

float3 GetEyePos(float2 xy, float z)
{
	float3 m = float3(fl / IASPECT_RATIO, (FARPLANE / (FARPLANE - 1.0)) );
	float3 xyz = float3(2*xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 GetEyePos(float3 xyz)
{
	float3 m = float3(fl / IASPECT_RATIO, (FARPLANE / (FARPLANE - 1.0)));
	float z = xyz.z;
	xyz = float3(2*xyz.xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 NorEyePos(float2 xy)
{
	float z = GetDepth(xy);
	float3 m = float3(fl / IASPECT_RATIO, (FARPLANE / (FARPLANE - 1.0)));
	float3 xyz = float3(2*xy-1,1.0);
	return (z * FARPLANE + 1.0) * xyz*m;
}

float3 GetScreenPos(float3 xyz)
{
	float3 m = float3(fl / IASPECT_RATIO, (FARPLANE / (FARPLANE - 1.0)));
	xyz.xy /= m.xy * xyz.z;
	return float3(0.5 + 0.5 * xyz.xy, (xyz.z - 1.0) / FARPLANE);
}


//===================================================================================
//Sampling
//===================================================================================


float3 GetBackBuffer(float2 xy)
{
	return tex2D(ReShade::BackBuffer, xy).rgb;
	//return tex2D(Zenteon::sTest, xy).rgb;
}


//===================================================================================
//Functions
//===================================================================================

float GetLuminance( float3 x)
{
	return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b;
}	

float nll(float3 x)
{
	x = exp(x + 1.0);
	//x.x = max(dot(x.x, rcp(3)),1.0);
	return saturate(log(x.z));
}

float3 ReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 / (1.0 + 1.2 * forceLinear) ), 0.001);
	
	float wp = log2(rcp(HDR_RED - 1.0) + 1.0);//rcp(HDR_RED - 1.0);
	x = log2(x + 1.0) / wp;
	/*
	float l = dot(x,0.33334);// max(x.r, max(x.g,x.b));//dot(x, float3(0.2126, 0.7152,0.0722));
	x /= l + 0.0001;
	return pow(x * HDR_RED * l / (l + 1.0), rcp(2.2));
	*/
	return pow(saturate(x), rcp(2.2));
}

float3 IReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 + 1.2 * forceLinear), 0.001);
	x = pow(x, 2.2);
	float wp = log2(rcp(HDR_RED - 1.0) + 1.0);
	
	return exp2(x * wp) - 1.0;
	
	/*
	float l = dot(x,0.33334);//max(x.r, max(x.g,x.b));
	//float l = dot(x, float3(0.2126, 0.7152,0.0722));
	x /= l + 0.0001;
	return  max(x * -l / (l - HDR_RED), 0.0000001);
	*/
}

//

float CalcDiffuse(float3 pos0, float3 nor0, float3 pos1, float3 nor1, float backface)
{
	float diff0 = saturate(dot(nor0, normalize(pos1 - pos0)) + 0.0312);
	
	//Option for backface lighting, looks bad
	float diff1 = saturate(dot(nor1, normalize(pos0 - pos1)) + 0.0312);
	return diff0 * diff1;//pow(diff1, 1.0);
}

float CalcTransfer(float3 pos0, float3 nor0, float3 pos1, float3 nor1, float disDiv, float att, float backface)
{
	float lumMult = dot(pos1, pos1) + 0.001;//length(pos1) / (1.0 + disDiv) + 1.0; lumMult *= lumMult;
	float dist = rcp(att + dot(pos1-pos0,pos1-pos0));//distance(pos0, pos1) / (1.0 + disDiv) + 1.0; dist = rcp(dist*dist);
	//float lamb = CalcDiffuse(pos0, nor0, pos1, nor1, backface);
	float3 nv = normalize(pos1 - pos0);
	float lamb = saturate(dot(nor0, nv)) * (saturate(dot(nor1, -nv)) );
	
	return max(lamb * lumMult * dist, 0.000);
}	


float CalcSpecular(float3 pos0, float3 refl0, float3 pos1, float3 nor1, float disDiv, float att, float power)
{
	float diff0 = pow(saturate(dot(refl0, normalize(pos1 - pos0)) - 0.1), power);
	float diff1 = saturate((dot(nor1, normalize(pos0 - pos1)) - 0.1));
	
	float lumMult = dot(pos1,pos1);//pow(length(pos1) / (1.0 + disDiv) , 2.0);
	float eyeMult = rcp(dot(pos0,pos0)+1.0);//rcp( pow(length(pos0) / (1.0 + disDiv) , 2.0 ));
	float dist = rcp(dot(pos0-pos1,pos0-pos1)+0.00001);//rcp( pow(att + distance(pos0, pos1) / disDiv, 2.0) );
	float trns = diff0 * diff1;
	return max(power * trns * eyeMult * lumMult * dist, 0.00);
}

float CalcSSS(float thk, float3 viewV, float3 surfN, float3 lightV)
{
	#define DISTORT  1.0
	#define POWER	1.0
	#define SCALE	1.0
	#define AMBIENT  0.2
	
	float3 thvLum = lightV + surfN * DISTORT;
	float  thkDot = pow( saturate(dot(viewV, - thvLum)), POWER) * SCALE;
	float sss = (thkDot + AMBIENT) * thk;
	return sss;
}

