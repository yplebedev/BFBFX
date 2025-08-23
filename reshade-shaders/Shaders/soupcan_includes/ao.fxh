#include "ReShade.fxh"
#include "soupcan_includes/pos.fxh"
#include "soupcan_includes/random.fxh"

#define getDepth ReShade::GetLinearizedDepth

#ifndef SLICES
	#define SLICES 10
#endif
#ifndef STEPS
	#define STEPS 8
#endif
#ifndef R
	#define R 1
#endif

#ifndef PI
	#define PI 3.1415926538
#endif

uniform int framecount < source = "framecount"; >;

// Modified from https://www.shadertoy.com/view/4djSRW
// It's called once per pixel.
float2 fastHash(float2 p) {
	float3 p3 = float3(p * BUFFER_SCREEN_SIZE, framecount & 0xFFFF);
	p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xy + p3.yz) * p3.zx);
}

float gtao(float2 texcoord, float2 vpos) {
	float4 normalAndDepth = getPackedWorldSpaceNormal(texcoord); // saves one depth fetch per pixel.
	float depth = normalAndDepth.z;
	float3 normalV = normalAndDepth.xyz;
	
	float3 cPosV = getWorldPosition(texcoord, depth);
	cPosV.z *= 0.99999;
	
	float3 viewV = -normalize(cPosV);
	
	float visibility = 0;
	
	float2 randomSource = fastHash(texcoord); //ToDo: test other methods. 
	float randomAngle = randomSource.x * PI; // Is this stupid to do?
	for (float slice = 0; slice < SLICES; slice++) {
		float phi = slice / SLICES * PI + randomAngle;
		float2 omega = float2(cos(phi), sin(phi));
		
		float3 dirV = float3(omega, 0.0);
		float3 orthoDirV = dirV - dot(dirV, viewV) * viewV;
		float3 axisV = cross(dirV, viewV);
		float3 projN = normalV - axisV * dot(normalV, axisV);
		float projNlength = length(projN);
		
		int sgnN = sign(dot(orthoDirV, projN));
		float cosN = saturate(dot(projN, viewV) / projNlength);
		
		float n = sgnN * acos(cosN);
		
		// float cHorizonCos = -1; xegtao says this is stupid. quote:
		// this is a lower weight target; not using -1 as in the original paper because it is under horizon, so a 'weight' has different meaning based on the normal
		float horizonCos0 = cos(n + PI/2);
		float horizonCos1 = cos(n - PI/2);
		
		[unroll]
		for(float step = 0; step < STEPS; step++) {
			// no noise :(
			// btw, this is gonna hurt without r2. the noise needs to vary per step
			float s = step / STEPS * R * length(cPosV);
			s += sqrt(2) / 2; // in int coords this is much simpler. faster, too!
			float2 sampleOffset = s * omega;
			
			// manual unroll
			float2 sampleScreenPos0 = vpos + sampleOffset;
			float sampleDepth0 = getVposDepth(sampleScreenPos0);
			float3 sPosV0 = getWorldPositionVpos(sampleScreenPos0, sampleDepth0);
			
			float2 sampleScreenPos1 = vpos - sampleOffset;
			float sampleDepth1 = getVposDepth(sampleScreenPos1);
			float3 sPosV1 = getWorldPositionVpos(sampleScreenPos1, sampleDepth0);
			
			float3 delta0 = sPosV0 - cPosV; 
			float3 delta1 = sPosV1 - cPosV;
			float sampleDist0 = length(delta0);
			float sampleDist1 = length(delta1);
			
			float3 horizonVec0 = delta0 / sampleDist0;
			float3 horizonVec1 = delta1 / sampleDist1;
			
			float horizon0cos = dot(horizonVec0, viewV); // current cos
			float horizon1cos = dot(horizonVec1, viewV);
			//weight here by sampleDist
			
			
			horizonCos0 = max(horizonCos0, horizon0cos);
			horizonCos1 = max(horizonCos1, horizon1cos);
		}
		
		float h0 = -acos(horizonCos1);
		float h1 = acos(horizonCos0);
			
		float iarc0 = (cosN + 2.0 * h0 * sin(n) - cos(2.0 * h0-n))/4.0;
		float iarc1 = (cosN + 2.0 * h1 * sin(n) - cos(2.0 * h1-n))/4.0;
		
		visibility += projNlength * (iarc0 + iarc1);
	}
	
	return visibility / SLICES;
}


/*
float gtao(float2 uv, float2 vpos) {
	float depth = GetDepth(uv);
	float3 cPosV = getWorldPosition(uv, depth);
	cPosV.z *= 0.99999;  // Move center pixel slightly towards camera
	// to avoid imprecision artifacts due to depth buffer imprecision.
	float3 viewV = normalize(-cPosV);
	float3 normalV = getWorldSpaceNormal(uv);
	float visibility = 0;
	
	//float randomAngle = tex2Dfetch(bn_sampler, vpos % 64).x;
	float randomAngle = IGN(vpos);
	//float randomAngle = fastHash(uv).x;
	for (float slice = 0; slice < SLICES; slice++) {
		float phi = PI * (slice / SLICES + randomAngle);

		float2 omega = float2(cos(phi), sin(phi));
		omega.y = omega.y * BUFFER_ASPECT_RATIO;
		
		float3 dirV = float3(omega, 0);
		float3 orthoDirV = dirV - dot(dirV, viewV) * viewV;
		float3 axisV = cross(dirV, viewV);
		float3 projN = normalV - axisV * dot(normalV, axisV);
		
		int sgnN = sign(dot(orthoDirV, projN));
		float cosN = saturate(dot(projN, viewV) / length(projN));
		float n = sgnN * acos(cosN);
		
		[unroll]
		for (int side = 0; side < 2; side++) {
			float cHorizonCos = -1;
			for (float step = 0; step < STEPS; step++) {
				float stepBaseNoise = (slice + step * STEPS) * 0.6180339887498948482; 	
				float stepNoise = 2 * frac(tex2Dfetch(bn_sampler, vpos % 64).y + stepBaseNoise);
				float s = (step + stepNoise) / STEPS;
				s = pow(s, 2.0) + length(BUFFER_PIXEL_SIZE);
				float scaling = R / length(cPosV);
				scaling = clamp(scaling, 0, R);
				float2 sTexCoord = uv + (-1.0 + 2.0 * side) * s * scaling * omega;
				float3 sPosV = getWorldPosition(sTexCoord, GetDepth(sTexCoord));
				float3 sDelta = sPosV - cPosV;
				float3 sHorizonV = normalize(sDelta);
				float currentCos = dot(sHorizonV, viewV);
				
				currentCos = lerp(currentCos, 0, saturate((distance(sPosV, cPosV) - 2.0) / 10));
				
				cHorizonCos = max(cHorizonCos, currentCos);
			}
			
			float h = n + clamp((-1.0 + 2.0 * side) * acos(cHorizonCos) - n, -PI/2, PI/2);
			visibility += length(projN) * (cosN + 2.0 * h * sin(n) - cos(2.0 * h - n)) / 4.0;
		}
	}
	return visibility / SLICES;
} */
