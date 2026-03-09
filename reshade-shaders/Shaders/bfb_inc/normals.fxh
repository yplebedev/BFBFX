#pragma once

#include "OpenRSF.fxh"

#define texture_int 0.8
#define texture_rad 1.3

texture2D tTempN0 { DIVRES(1); Format = RGBA16F; };
sampler2D sTempN0 { Texture = tTempN0; };
texture2D tHN0 { DIVRES(2); Format = RGBA16F; };
sampler2D sHN0 { Texture = tHN0; };
texture2D tHN1 { DIVRES(2); Format = RGBA16F; };
sampler2D sHN1 { Texture = tHN1; };

float3 AtrousN(sampler2D tex, float2 xy, float level, int rad)
{
	float3 cenN = tex2D(tex, xy).xyz;
	float cenD = GetDepth(xy);
	float2 mult = exp2(level) / tex2Dsize(tex);
	
	float4 acc;
	for(int i = -rad; i <= rad; i++) for(int ii = -rad; ii <= rad; ii++)
	{
		float2 nxy = xy + mult * float2(i,ii);
		float samD = GetDepth(nxy);
		float3 samN = tex2Dlod(tex, float4(nxy,0,0)).xyz;
		
		float w = dot(cenN, samN) > 0.8 + 0.19 * (level / (level + 1.0));
		//w *= dot(cenN, samN) < 0.9999;
		w *= exp(-10.0 * abs(cenD - samD) / (cenD + 0.01));
		acc += w * float4(samN, 1.0);
	}
	return acc.w > 0.01 ? normalize(acc.xyz) : cenN;
}

float4 GenNormalsPS(PS_INPUTS) : SV_Target 
{
	float3 vc	  = NorEyePos(xy);
	float3 vx0	  = vc - NorEyePos(xy + float2(1, 0) / RES);
	float3 vy0 	 = vc - NorEyePos(xy + float2(0, 1) / RES);
	
	float3 vx1	  = -vc + NorEyePos(xy - float2(1, 0) / RES);
	float3 vy1 	 = -vc + NorEyePos(xy - float2(0, 1) / RES);
	float3 vx01	  = vc - NorEyePos(xy + float2(2, 0) / RES);
	float3 vy01 	 = vc - NorEyePos(xy + float2(0, 2) / RES);	
	float3 vx11	  = -vc + NorEyePos(xy - float2(2, 0) / RES);
	float3 vy11 	 = -vc + NorEyePos(xy - float2(0, 2) / RES);
	
	float dx0 = abs(vx0.z + (vx0.z - vx01.z));
	float dx1 = abs(vx1.z + (vx1.z - vx11.z));
	float dy0 = abs(vy0.z + (vy0.z - vy01.z));
	float dy1 = abs(vy1.z + (vy1.z - vy11.z));
	
	float3 vx = dx0 < dx1 ? vx0 : vx1;
	float3 vy = dy0 < dy1 ? vy0 : vy1;
	
	return float4(normalize(cross(vy, vx)), 1.0);
}

float4 SmoothNormals0PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sTempN0, xy, 3.0, 1), 1.0); }
float4 SmoothNormals1PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN0, xy, 2.0, 2), 1.0); }
float4 SmoothNormals2PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN1, xy, 0.0, 1), 1.0); }
float4 SmoothNormals3PS(PS_INPUTS) : SV_Target { return float4(AtrousN(sHN0, xy, 1.0, 1), 1.0); }

float2 TexNormalsPS(PS_INPUTS) : SV_Target
{
	float3 rawN = tex2D(sTempN0, xy).xyz;
	
	float3 smoothN = tex2D(ORSFShared::sSmoothN, xy).xyz;
	float3 finalN = dot(smoothN, rawN) > 0.83 ? smoothN : rawN;
	
	
	float3 cenP = NorEyePos(xy);
	float cenpL2 = dot(cenP, cenP);
	//float cenD = GetDepth(xy);
	float3 texN; float tacc;
	for(int i = -1; i <= 1; i++) for(int ii = -1; ii <= 1; ii++)
	{
		float2 nxy = xy + float2(i,ii) * texture_rad / RES;
		float4 samL = tex2D(ReShade::BackBuffer, nxy);
		float sLum = GetLuminance(samL.rgb);
		float3 samP = NorEyePos(nxy);
		//float samD = GetDepth(nxy);
		float w = exp(-FARPLANE * distance(cenP, samP) / (cenpL2 + exp(-32) ));
		texN += float3(-i,-ii, 1.0 / w) * lerp(sLum.x, samL.w, 0.8);
		tacc += samL.w;
	}
	texN.xy /= texN.z + 1.0;
	texN = normalize(float3(texN.xy, 2.5 * pow(1.0 - 0.75 * texture_int, 4.0) ) );
	
	//finalN = (0.5 + 0.5 * finalN) * 2.0 + float3(-1,-1,0);
	//texN = (0.5 - 0.5 * texN) * float3(-2,-2,2) + float3(1,1,-1);
	//finalN = finalN * dot(finalN, texN) / finalN.z - texN;
	//finalN = -normalize(finalN);
	finalN = normalize(float3(finalN.xy + texN.xy, finalN.z*texN.z));
	
	
	return OCTtoUV(finalN);
}