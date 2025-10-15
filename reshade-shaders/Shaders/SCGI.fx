// MIT License...
/* Copyright (c)2025 Yaraslau Lebedzeu.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/

#include "ReShade.fxh"
#include "soupcan_includes/FrameworkResources.fxh"

#ifndef PI
	#define PI 3.14159265358979
#endif

texture bnt <source = "stbn.png";> {Width = 1024; Height = 1024; Format = R8; };
sampler bn { Texture = bnt; };

texture irradiance { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler sIrradiance { Texture = irradiance; AddressU = BORDER; AddressV = BORDER; };

texture GI { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sGI { Texture = GI; AddressU = CLAMP; AddressV = CLAMP; };

texture GI2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sGI2 { Texture = GI2; AddressU = CLAMP; AddressV = CLAMP; };

texture tAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAO { Texture = tAO; AddressU = CLAMP; AddressV = CLAMP; };

texture tAOswap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAOswap { Texture = tAOswap; AddressU = CLAMP; AddressV = CLAMP; };

texture tLuminance2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sLuminance2 { Texture = tLuminance2; };

texture tLuminance2swap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sLuminance2swap { Texture = tLuminance2swap; };

texture tError { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sError { Texture = tError; };

texture tDN1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDN1 { Texture = tDN1; AddressU = BORDER; AddressV = BORDER; };

texture tDN2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDN2 { Texture = tDN2; AddressU = BORDER; AddressV = BORDER; };

// Optimization is fun asf.
texture minZ { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16; };
sampler sminZ { Texture = minZ; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture minZ2 { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = R16; };
sampler sminZ2 { Texture = minZ2; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
texture minZ3 { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16; };
sampler sminZ3 { Texture = minZ3; 
	MagFilter = POINT;
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

texture tAccumL { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumL { Texture = tAccumL; };

texture tAccumLswap { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R32U; };
sampler2D<uint> sAccumLswap { Texture = tAccumLswap; };


uniform int framecount < source = "framecount"; >;

uniform bool debug <ui_label = "Debug view"; hidden = false;> = false;
uniform bool noFilter <ui_label = "Screw denoising!"; hidden = true;> = false;
uniform float reflBoost <ui_type = "slider"; ui_label = "Strength"; ui_tooltip = "An all-in-one strength parameter. Minimal is very cheap, but looks bad. Low is the minimum intended playable experience"; ui_max = 16.0; ui_min = 0.001;> = 1.0;
uniform float THICKNESS <ui_type = "slider"; ui_label = "Thickness"; ui_tooltip = "SCGI uses a thickness heuristic. Don't set this too high or low!"; ui_min = 2.0; ui_max = 16.0;> = 2.0; 
uniform bool displayError<hidden = true;> = false;

uniform float n_phi <hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Normal avoiding";> = 0.1;
uniform float p_phi <hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Depth avoiding";> = 1.0;
uniform float v_phi <hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Variance avoiding";> = 1.0;

uniform int quality <ui_type = "combo"; ui_label = "GI quality"; ui_items = "Minimal\0Low\0Medium\0High\0Oh god\0";> = 0;

uniform bool boostInterrefl = true;

//uniform float fovX <ui_type = "slider"; ui_min = 1.0; ui_max = 100.0; ui_label = "HFOV";> = 90.0;


const static float kernel[25] = {
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    3.0/128.0, 3.0/32.0,  9.0/64.0,  3.0/32.0,  3.0/128.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0
};
const static float2 offset[25] = {
    float2(-2.0, -2.0), float2(-1.0, -2.0), float2(0.0, -2.0), float2(1.0, -2.0), float2(2.0, -2.0),
    float2(-2.0, -1.0), float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0), float2(2.0, -1.0),
    float2(-2.0,  0.0), float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0), float2(2.0,  0.0),
    float2(-2.0,  1.0), float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0), float2(2.0,  1.0),
    float2(-2.0,  2.0), float2(-1.0,  2.0), float2(0.0,  2.0), float2(1.0,  2.0), float2(2.0,  2.0)
};


//uniform int scgi_slices <ui_type = "slider"; ui_label = "Rays"; ui_tooltip = "How many directions per pixel to consider. Lower values are faster, but more noisy. \n\nPerformance impact: EXTREME!"; ui_min = 1; ui_max = 16;> = 1;
//uniform int scgi_steps <ui_type = "slider"; ui_label = "Steps per Ray"; ui_tooltip = "How many times to consider the geometry per ray. Higher values increase precision and quality, but slow down the effect. \n\nPerformance impact: High"; ui_min = 2; ui_max = 32;> = 8;

#define SECTORS 32

#define FAR_CLIP (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE-1)

#define __PXSDECL__ (float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target

// high value == safe
float getRejectCond(float3 mv, float depthDiff, float nDiff) {
	return mv.z * pow(nDiff, 3.0) * saturate(rcp(depthDiff + 0.0001));
}

// NOTES FROM MARTY:
// - Relax normal guide on really small depth delta -- ToDo?
float4 atrous(sampler input, float2 texcoord, float level) {
	uint accumL = tex2D(sAccumL, texcoord);
	bool reject = accumL == 0u;
	
	float4 noisy = tex2D(input, texcoord);
	float variance = tex2Dlod(input, float4(texcoord, 0.0, reject ? 16.0 : 1.0)).w;
	float3 normal = zfw::getNormal(texcoord);
	float3 pos = zfw::uvToView(texcoord);
	
	float4 sum = 0.0;
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);

		float4 ctmp = tex2Dlod(input, float4(uv, 0.0, 0.0));
		float4 t = noisy - ctmp;

		float dist2 = dot(t.rgb, t.rgb); // do NOT guide with variance!
		float c_w = min(exp(-dist2 * sqrt(accumL) / (v_phi * variance + 0.01)), 1.0) + 0.08;
		
		float3 ptmp = zfw::uvToView(uv);
		t = pos - ptmp;
		t *= dot(normal, -normalize(pos));
		dist2 = dot(t, t);
		float p_w = min(exp(-dist2 / p_phi), 1.0);
		
		float3 ntmp = zfw::getNormal(uv);
		t = normal - ntmp;
		dist2 = max(dot(t, t), 0.0);
		float n_w = min(exp(-dist2 / n_phi), 1.0);
		
		float weight = c_w * n_w * p_w;
		sum += ctmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	return sum/cum_w;
}

// Gathers pixels around the sample point
// By Zenteon
float4 GatherLinDepth(float2 texcoord, sampler s) {
    #if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    texcoord.y = 1.0 - texcoord.y;
    #endif
    #if RESHADE_DEPTH_INPUT_IS_MIRRORED
            texcoord.x = 1.0 - texcoord.x;
    #endif
    texcoord.x /= RESHADE_DEPTH_INPUT_X_SCALE;
    texcoord.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
    #if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    texcoord.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
    #else
    texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
    #endif
    #if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
    #else
    texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
    #endif
    float4 depth = tex2DgatherR(s, texcoord) * RESHADE_DEPTH_MULTIPLIER;
    
    #if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    const float C = 0.01;
    depth = (exp(depth * log(C + 1.0)) - 1.0) / C;
    #endif
    #if RESHADE_DEPTH_INPUT_IS_REVERSED
    depth = 1.0 - depth;
    #endif
    const float N = 1.0;
    depth /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - depth * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - N);
    
    return depth;
}

// STBN stuff
float2 getTemporalOffset() {
	return float2(framecount % 8, (framecount >> 3) % 8);
}

// also vpos
float2 stbn(float2 p) {
	#define xyOffset float2(5, 7)
	return float2(tex2Dfetch(bn, (p % 64) + getTemporalOffset() * 64).x,
				  tex2Dfetch(bn, ((p + xyOffset) % 64) + getTemporalOffset() * 64).x);
	
}


namespace stepData {
	struct stepData {
		uint bitfield;
		uint AObitfield;
		float3 lighting;	
	};
	float3 getLighting(stepData sd) {
		return sd.lighting;
	}
	uint getBitfield(stepData sd) {
		return sd.bitfield;
	}
}

// I know I'll (or someone else) will look at this code
// to -steal- learn from, so have some pointers as to why
// each (debias or otherwise) step is there.
// This code assumes lambertian diffuse, but technically it could be extended to specular, or any other lobe. 
// Since this is basically importance-sampling lambert, you'd need a bit of elbow grease to let it do, say, specular.
float3 calculateIL(uint prevBF, uint currBF, float3 positionVS, float3 nF, float3 nS, float3 delta, float2 uv, float2 uvF, float3 samplePosVS) {
	float3 di = tex2Dlod(sIrradiance, float4(uv, 0., 0.)).rgb; // theoretically the light, but BackBuf works fine, and is best we got.
	
	float deltaBF = ((float)countbits(currBF & ~prevBF)) / SECTORS; // difference of bitmasks. Gets us shadows, and is the similar to HBIL's weighting by the angle diff.
	float rxW = saturate(dot(normalize(delta), nF)); // light gets spread over a bigger area when it enters at a lower angle
	float reflW = ceil(dot(-normalize(delta), nS)); // how much light reflects into the shaded pixel.
	
	return deltaBF * rxW * reflW * di; // shadow * step->fragment * fragment->viewer * emmision
}

float2 snapVPOS(float2 vpos) {
	return floor(vpos) + float2(0.5, 0.5);
}

float2 snapVPOS2(float2 vpos) {
	return floor(vpos / 2.0) * 2.0 + float2(1.0, 1.0);
}

float2 snapVPOS3(float2 vpos) {
	return floor(vpos / 4.0) * 4.0 + float2(2.0, 2.0);
}

float2 snapVPOS4(float2 vpos) {
	return floor(vpos / 8.0) * 8.0 + float2(4.0, 4.0);
}

// Fetches lower res depth further away to save on fetch costs.
//                    VPOS (pixcoords), distance
float getAdaptiveZ(inout float2 samplePos, float t) {
	float res = 0;
	const uint drops = 3;
	const float dropLength = sqrt(2.)*0.5;
	
	if (t < dropLength) {
		samplePos = snapVPOS(samplePos);
		res = ReShade::GetLinearizedDepth(samplePos * BUFFER_PIXEL_SIZE);
	}
	else if (t >= dropLength && t < dropLength * 2.0 && drops > 0) {
		samplePos = snapVPOS2(samplePos);
		res = tex2Dfetch(sminZ, samplePos * 0.5).x;
	}
	else if (t >= dropLength * 2.0 && t < dropLength * 4.0 && drops > 1) {
		samplePos = snapVPOS3(samplePos);
		res = tex2Dfetch(sminZ2, samplePos * 0.25).x;
	}
	else if (t >= dropLength * 4.0 && drops > 2) {
		samplePos = snapVPOS4(samplePos);
		res = tex2Dfetch(sminZ3, samplePos * 0.125).x;
	}
	return res;
}

// Fetches lower res normal further away to save on fetch costs.
//                    VPOS (pixcoords), distance
float3 getAdaptiveN(inout float2 samplePos, float t) {
	float3 res = 0;
	const uint drops = 3;
	const float dropLength = 2.0;
	
	if (t < dropLength) {
		res = zfw::getNormal(samplePos * BUFFER_PIXEL_SIZE);
	}
	else if (t >= dropLength && t < dropLength * 2.0 && drops > 0) {
		res = zfw::sampleNormal(samplePos * BUFFER_PIXEL_SIZE, 0.);
	}
	else if (t >= dropLength * 2.0 && t < dropLength * 4.0 && drops > 1) {
		res = zfw::sampleNormal(samplePos * BUFFER_PIXEL_SIZE, 1.);
	}
	else if (t >= dropLength * 4.0 && drops > 2) {
		res = zfw::sampleNormal(samplePos * BUFFER_PIXEL_SIZE, 2.);
	}
	return normalize(res);
}

uint getStepCount() {
	uint res = 1;
	switch (quality) {
		case 0:
			res = 2;
			break;
		case 1:
			res = 4;
			break;
		case 2:
			res = 8;
			break;
		case 3:
			res = 16;
			break;
		case 4:
			res = 20;
			break;
	}
	return res;
}

stepData::stepData sliceSteps(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, float3 normal, uint bitfield) {
	stepData::stepData data;
	data.bitfield = bitfield;
	data.lighting = 0.0;
	
	uint scgi_steps = getStepCount();
    for (uint i = 0; i < scgi_steps; i++) {
    	float sampleLength = (t + i) / scgi_steps;
    	sampleLength *= sampleLength; // sample more closer.
    	float2 sampleUV = rayDir * sampleLength + start / BUFFER_SCREEN_SIZE;
        sampleUV = (floor(sampleUV * BUFFER_SCREEN_SIZE) + 0.5) * BUFFER_PIXEL_SIZE;
        
		float2 range = saturate(sampleUV * sampleUV - sampleUV);
		bool is_outside = range.x != -range.y; //and of course if we are not inside we are outside. 	
    	if (is_outside) break;
    	
    	float screenDist = length((sampleUV - start) * BUFFER_SCREEN_SIZE);
    	
    	float2 sampleVS = sampleUV * BUFFER_SCREEN_SIZE;
        float3 samplePosVS = zfw::uvzToView(sampleUV, getAdaptiveZ(sampleVS, sampleLength));
        float3 delta = samplePosVS - positionVS;
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + THICKNESS * normalize(samplePosVS)), V)));
	    fb = saturate(((samplingDirection * -fb) - N + PI/2) / PI);
	    fb = fb.x > fb.y ? fb.yx : fb;
	    fb = smoothstep(0, 1, fb); // cosine lobe for AO. Trick by Marty (https://www.martysmods.com/)
	    
   	 uint a = round(fb.x * SECTORS);
    	uint b = ceil((fb.y - fb.x) * SECTORS);
    	
    	uint prevBF = data.bitfield;
    	data.bitfield |= ((1 << b) - 1) << a; 
    	
		float3 il = calculateIL(prevBF, data.bitfield, V, normal, getAdaptiveN(sampleVS, sampleLength), delta, sampleUV, start / BUFFER_SCREEN_SIZE, samplePosVS); // and debias by the distance^4
		data.lighting += il;
	 }
    return data;
}

uint getSliceCount() {
	uint res = 1;
	switch (quality) {
		case 0:
			res = 1;
			break;
		case 1:
			res = 1;
			break;
		case 2:
			res = 2;
			break;
		case 3:
			res = 4;
			break;
		case 4:
			res = 8;
			break;
	}
	return res;
}

// RGB - inderect illum, A - ambient occlusion
float4 calcGI(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float2 start = vpos;
	float3 positionVS = zfw::uvToView(uv);

	float ao = 0.0;
	
	float3 V = normalize(-positionVS);
	float3 normalVS = zfw::getNormal(uv);
	positionVS += normalVS * 0.001;

    //float step = max(1.0, R / positionVS.z / (SCVBAO_STEPS + 1.0));
	
	float3 il = 0;
	
	float scgi_slices = getSliceCount();
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / scgi_slices) {
		float phi = PI * frac(slice + random.x) * (quality ? 1.0 : 2.0);
		float2 direction = float2(cos(phi), sin(phi));
		
		float3 directionF3 = float3(direction, 0.0);
		float3 oDirV = directionF3 - dot(directionF3, V) * V;
		float3 sliceN = cross(directionF3, V);
		float3 projN = normalVS - sliceN * dot(normalVS, sliceN);
		float cosN = saturate(dot(projN, V) / length(projN));
		float signN = -sign(dot(projN, oDirV));

		float N = signN * acos(cosN);
		
		uint aoBF = 0;
		float offset = random.y;
		
		
		stepData::stepData dir1 = sliceSteps(positionVS, V, start, direction, offset, 0.0, 1, N, normalVS, aoBF);
		aoBF = stepData::getBitfield(dir1);
		il += stepData::getLighting(dir1);
		
		if (quality != 0) {
			stepData::stepData dir2 = sliceSteps(positionVS, V, start, -direction, offset, 0.0, -1, N, normalVS, aoBF);
			aoBF = stepData::getBitfield(dir2);
			il += stepData::getLighting(dir2); // wrong but fast
		}
		
		ao += float(countbits(aoBF)) * (quality ? 0.5 : 1.0); // todo: ass
	}
	ao = 1.0 - ao / (float(SECTORS) * scgi_slices);
	ao = positionVS.z > FAR_CLIP || ao < -0.001 ? 1.0 : ao;
	
	il /= scgi_slices;
	il = positionVS.z > FAR_CLIP ? 0.0 : il;
	return float4(il, ao);
}

// Gathers & linearizes source depth, writes to lower res tex
float prepMinZ __PXSDECL__ {
	float4 z4 = GatherLinDepth(uv, ReShade::DepthBuffer);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

// -||-
float prepMinZ2 __PXSDECL__ {
	float4 z4 = tex2DgatherR(sminZ, uv);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

// -||-
float prepMinZ3 __PXSDECL__ {
	float4 z4 = tex2DgatherR(sminZ2, uv);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

float4 save(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float3 mv = zfw::getVelocity(uv);
	return float4(
		zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 20.) 
		+ zfw::getAlbedo(uv) * (boostInterrefl ? reflBoost : 1.0) * tex2D(sGI, uv + mv.xy).rgb,
	1.);
}


float getHistorySize(float2 uv) {
	return 0.96 * rcp(1.0 + float(tex2D(sAccumL, uv)));
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 GI : SV_Target0, out float AO : SV_Target1, out float luminanceSquared : SV_Target2, out float sigma2 : SV_Target3) {
	GI = calcGI(uv, vpos.xy);
	float3 mv = zfw::getVelocity(uv);
	
	float historySize = getHistorySize(uv); 
	float accumulatedAO = tex2D(sAOswap, uv + mv.xy).r;
	AO = lerp(accumulatedAO, GI.a, historySize);
	
	float4 accumulatedGI = tex2D(sGI2, uv + mv.xy);
	GI = lerp(accumulatedGI, GI, historySize);
	
	float luminance = dot(GI.rgb, float3(0.2126, 0.7152, 0.0722));
	luminanceSquared = luminance * luminance;
	float accumulatedLuminanceSquared = tex2D(sLuminance2swap, uv + mv.xy).r;
	luminanceSquared = lerp(luminanceSquared, accumulatedLuminanceSquared, historySize);
	
	sigma2 = luminanceSquared - (luminance * luminance);
	GI.a = sigma2;
}

float4 DN1(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(sGI, uv, 0);
}

float4 DN2(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(sDN1, uv, 1);
}

float4 DN3(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(sDN2, uv, 2);
}

float4 DN4(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(sDN1, uv, 3);
}

float4 DN5(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(sDN2, uv, 2); // lower artifacts?
}

float3 blend(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float4 gi = !noFilter ? tex2D(sDN1, uv) : tex2D(sGI, uv);
	if (debug) return zfw::toneMap(gi.rgb * reflBoost + tex2D(sAO, uv).xxx * 0.1, 20.0);
	return zfw::toneMap(gi.rgb * reflBoost * zfw::getAlbedo(uv) + tex2D(sAO, uv).r * zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 20.0), 20.0);
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
	curAccumSwap = clamp(tex2D(sAccumL, uv), 0u, 64u);
}

void saveForAccum(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 GI : SV_Target0, out float luma2 : SV_Target1, out float AO : SV_Target2) {
	GI = tex2Dfetch(sGI, vpos.xy);
	luma2 = tex2Dfetch(sLuminance2, vpos.xy).r;
	AO = tex2Dfetch(sAO, vpos.xy).r;
}

float saveForRejectZ(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return zfw::getDepth(uv);
}

float4 saveForRejectN(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return zfw::getNormal(uv).xyzz;
}

technique SCGI {
	pass PrepZ {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ;
		RenderTarget = minZ;
	}
	pass Prepz2 {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ2;
		RenderTarget = minZ2;
	}
	pass Prepz3 {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ3;
		RenderTarget = minZ3;
	}
	pass Save {
		VertexShader = PostProcessVS;
		PixelShader = save;
		RenderTarget = irradiance;
	}
	pass GI { 
		VertexShader = PostProcessVS;
		PixelShader = main;
		RenderTarget0 = GI;
		RenderTarget1 = tAO;
		RenderTarget2 = tLuminance2; 
		RenderTarget3 = tError;
	}
	pass Denoise {
		VertexShader = PostProcessVS;
		PixelShader = DN1;
		RenderTarget = tDN1;
	}
	pass Denoise2 {
		VertexShader = PostProcessVS;
		PixelShader = DN2;
		RenderTarget = tDN2;
	}
	pass Denoise3 {
		VertexShader = PostProcessVS;
		PixelShader = DN3;
		RenderTarget = tDN1;
	}
	pass Denoise4 {
		VertexShader = PostProcessVS;
		PixelShader = DN4;
		RenderTarget = tDN2;
	}
	pass Denoise5 {
		VertexShader = PostProcessVS;
		PixelShader = DN5;
		RenderTarget = tDN1;
	}
	pass Blend {
		VertexShader = PostProcessVS;
		PixelShader = blend;
	}
	pass updateAccum {
		VertexShader = PostProcessVS;
		PixelShader = updateAccum;
		RenderTarget0 = tAccumL;
	}
	pass updateAccumSwap {
		VertexShader = PostProcessVS;
		PixelShader = updateAccumSwap;
		RenderTarget0 = tAccumLswap;
	}
	pass SaveForAccum {
		VertexShader = PostProcessVS;
		PixelShader = saveForAccum;
		RenderTarget0 = GI2;
		RenderTarget1 = tLuminance2swap;
		RenderTarget2 = tAOswap;
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
