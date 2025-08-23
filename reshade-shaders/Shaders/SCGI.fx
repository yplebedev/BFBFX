// VBGTAO
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
sampler sGI { Texture = GI; AddressU = BORDER; AddressV = BORDER; };

uniform int framecount < source = "framecount"; >;

uniform float historySize <ui_type = "slider"; ui_label = "Frame Blending"; ui_tooltip = "Affects the noise over update speed and ghosting ratios. This can be higher on higher FPS. 0 is no accumulation, and the closer to 1 the more previous results affect the image."; ui_min = 0.0; ui_max = 0.999;> = 0.8; 
uniform bool debug <ui_label = "Debug view";> = false;
uniform float strength <ui_type = "slider"; ui_label = "Strength"; ui_tooltip = "How much GI affects the input colors. Use conservativly."; ui_min = 0.0; ui_max = 100.0;> = 1.0; 
uniform float power <ui_type = "slider"; ui_label = "Sampling bias power"; ui_tooltip = "A bias to sample closer-by stuff more. Increasing increases effective radius and occlusion from small objects."; ui_min = 1.0; ui_max = 3.0;> = 1.0; 
//uniform float R <ui_type = "slider"; ui_label = "Radius"; ui_tooltip = "Increases the effect scale, but lowers effective quality and lowers cache coherency."; ui_min = 50.0; ui_max = 50000.0;> = 3000.0; 
uniform float THICKNESS <ui_type = "slider"; ui_label = "Thickness"; ui_tooltip = "SCVBAO uses... you guessed it, VBAO. It allows for a thickness heuristic. Don't set this too high or low!"; ui_min = 0.0; ui_max = 4.0;> = 2.0; 

uniform float c_phi <ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Color avoiding";> = 1.0;
uniform float n_phi <ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Normal avoiding";> = 1.0;
uniform float p_phi <ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_label = "Depth avoiding";> = 1.0;

uniform float kernel[25] <hidden = true;> = {
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    3.0/128.0, 3.0/32.0,  9.0/64.0,  3.0/32.0,  3.0/128.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0
};
uniform float2 offset[25] <hidden = true;> = {
    float2(-2.0, -2.0), float2(-1.0, -2.0), float2(0.0, -2.0), float2(1.0, -2.0), float2(2.0, -2.0),
    float2(-2.0, -1.0), float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0), float2(2.0, -1.0),
    float2(-2.0,  0.0), float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0), float2(2.0,  0.0),
    float2(-2.0,  1.0), float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0), float2(2.0,  1.0),
    float2(-2.0,  2.0), float2(-1.0,  2.0), float2(0.0,  2.0), float2(1.0,  2.0), float2(2.0,  2.0)
};

#ifndef SCVBAO_SLICES
	#define SCVBAO_SLICES 1
#endif

#ifndef SCVBAO_STEPS
		#define SCVBAO_STEPS 8
#endif

#define SECTORS 32

//#define R_MAX_CLAMP 5000000000

#define FAR_CLIP (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE-1)

float4 atrous(sampler input, float2 texcoord, float level) {
	float4 noisy = tex2D(input, texcoord);
	float3 normal = zfw::getNormal(texcoord);
	float depth = ReShade::GetLinearizedDepth(texcoord);
	float3 pos = zfw::uvToView(texcoord);
	
	float4 sum = 0.0;
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);

		float4 ctmp = tex2Dlod(input, float4(uv, 0.0, 0.0));
		float4 t = noisy - ctmp;
		
		float dist2 = dot(t, t);
		float c_w = min(exp(-(dist2)/c_phi), 1.0);
		
		float3 ntmp = zfw::getNormal(uv);
		t = normal - ntmp;
		dist2 = max(dot(t, t), 0.0);
		float n_w = min(exp(-dist2 / n_phi), 1.0);
		
		float3 ptmp = zfw::uvToView(uv);
		t = pos - ptmp;
		dist2 = dot(t, t);
		float p_w = min(exp(-dist2 / p_phi), 1.0);
		
		float weight = c_w * n_w * p_w;
		sum += ctmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	return sum/cum_w;
}

// Modified from https://www.shadertoy.com/view/4djSRW
// It's called once per pixel.
float2 fastHash(float2 p) {
	float3 p3 = float3(p * BUFFER_SCREEN_SIZE, framecount & 0xFFFF);
	p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xy + p3.yz) * p3.zx);
}

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
// This code assumes lambertian diffuse, but technically it could be extended to specular, or any other lobe. At the cost of nosie,
// since IS is hard for bitmasks, you'll get horrible nosie for tight lobes.
float3 calculateIL(uint prevBF, uint currBF, float3 positionVS, float3 nF, float3 nS, float3 delta, float2 uv, float2 uvF, float3 samplePosVS) {
	float lengthS = dot(delta, delta) + exp2(-32); // this +2e-32 step might not make sense, but since we correct by 2D dist, this is actually more correct
	float dist = dot(samplePosVS, samplePosVS);
	float3 di = tex2Dlod(sIrradiance, float4(uv, 0., 0.)).rgb; // theoretically the light, but BackBuf works fine, and is best we got.
	
	float deltaBF = ((float)countbits(currBF & ~prevBF)) / SECTORS; // difference of bitmasks. Gets us shadows, and is the similar to HBIL's weighting by the angle diff.
	float rxW = saturate(dot(normalize(delta), nF)); // light comes in, this weights how much of that incoming light would bounce the the viewer.
	float reflW = saturate(dot(-normalize(delta), nS)); // how much light reflects into the shaded pixel.
	
	return deltaBF * rxW * reflW * di * dist / lengthS; // shadow * step->fragment * fragment->viewer * emmision * probability correction, adds noise far away * inverse-square
}

stepData::stepData sliceSteps(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, float3 normal, uint bitfield) {
	stepData::stepData data;
	data.bitfield = bitfield;
	data.lighting = 0.0;
	
	[loop]
    for (uint i = 0; i < SCVBAO_STEPS; i++) {
    	float sampleLength = (t + i) / SCVBAO_STEPS;
    	sampleLength *= sampleLength; // sample more closer.
    	float2 sampleUV = rayDir * sampleLength + start / BUFFER_SCREEN_SIZE;
        //float2 samplePos = clamp(start + t * rayDir, 1, BUFFER_SCREEN_SIZE - 2);
        //samplePos = floor(samplePos) + 0.5;
    	
		float2 range = saturate(sampleUV * sampleUV - sampleUV);
		bool is_outside = range.x != -range.y; //and of course if we are not inside we are outside. 	
    	if (is_outside) break;
    	
        float3 samplePosVS = zfw::uvToView(sampleUV);
        float3 delta = samplePosVS - positionVS;
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + THICKNESS * normalize(samplePosVS)), V)));
	    fb = saturate(((samplingDirection * -fb) - N + PI/2) / PI);
	    fb = fb.x > fb.y ? fb.yx : fb;
	    //fb = smoothstep(0., 1., fb); // cosine lobe for AO. look: cdf.
	    
   	 uint a = round(fb.x * SECTORS);
    	uint b = round((fb.y - fb.x) * SECTORS);
    	
    	uint prevBF = data.bitfield;
    	data.bitfield |= ((1 << b) - 1) << a; 
    	
    	data.lighting += calculateIL(prevBF, data.bitfield, V, normal, zfw::getNormal(sampleUV), delta, sampleUV, start / BUFFER_SCREEN_SIZE, samplePosVS) * sampleLength * sampleLength; // and debias by the distance^4
    }
    return data;
}

// RGB - inderect illum, A - ambient occlusion
float4 gtao(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float2 start = vpos;
	float3 positionVS = zfw::uvToView(uv);

	float ao = 0.0;
	
	float3 V = normalize(-positionVS);
	float3 normalVS = zfw::getNormal(uv);
	positionVS += normalVS * 0.001;

    //float step = max(1.0, R / positionVS.z / (SCVBAO_STEPS + 1.0));
	
	float3 il = 0;
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / SCVBAO_SLICES) {
		float phi = PI * frac(slice + random.x);
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
		
		stepData::stepData dir1 = sliceSteps(positionVS, V, start, direction, offset, random.y, 1, N, normalVS, aoBF);
		aoBF = stepData::getBitfield(dir1);
		il += stepData::getLighting(dir1);
		
		stepData::stepData dir2 = sliceSteps(positionVS, V, start, -direction, offset, random.y, -1, N, normalVS, aoBF);
		aoBF = stepData::getBitfield(dir2);
		il += stepData::getLighting(dir2);

		ao += float(countbits(aoBF));
	}
	ao = 1.0 - ao / (float(SECTORS) * SCVBAO_SLICES);
	ao = positionVS.z > FAR_CLIP || ao < -0.001 ? 1.0 : ao;
	
	il /= SCVBAO_SLICES;
	return float4(il, ao);
}

float4 save(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return float4(zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 20.) + zfw::getAlbedo(uv) * tex2D(sGI, uv).rgb / (exp2(-32) + abs(dot(zfw::sampleNormal(uv, 0), -normalize(zfw::uvzToView(float3(uv, 0)))))), 1.);
}

float4 main(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	const float4 ao = gtao(uv, vpos.xy);
	return ao;
}

float4 denoise(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(ReShade::BackBuffer, uv, 0);
}

float4 denoise1(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	return atrous(ReShade::BackBuffer, uv, 1);
}

float3 blend(float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
	float4 gi = tex2D(sGI, uv);
	if (debug) return zfw::toneMap((gi.rgb + gi.a * 0.001) * strength, 20.0);
	return zfw::toneMap((gi.rgb + gi.a * 0.001) * strength * zfw::getAlbedo(uv) + zfw::toneMapInverse(tex2D(ReShade::BackBuffer, uv).rgb, 20.0), 20.0);
}

technique SCGI {
	pass Save {
		VertexShader = PostProcessVS;
		PixelShader = save;
		RenderTarget = irradiance;
	}
	pass GI { 
		VertexShader = PostProcessVS;
		PixelShader = main;
		RenderTarget = GI;
	}
	pass Blend {
		VertexShader = PostProcessVS;
		PixelShader = blend;
	}
	/*
	pass Denoise1 {
		VertexShader = PostProcessVS;
		PixelShader = denoise1;
	}*/
}
