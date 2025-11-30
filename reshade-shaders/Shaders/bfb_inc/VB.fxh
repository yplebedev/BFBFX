#include "stbn.fxh"
#include "settings.fxh"
#include "multibounce.fxh"

// no point in mutation
#define SECTORS 32
#define PI 3.14159265359

float getFastDepth(float2 uv, float t) {
	if (t < 2.0) {
		return zfw::getDepth(uv);
	} else if (t < 4.0) {
		return zfw::sampleDepth(uv, 0.);
	} else {
		float4 values = tex2DgatherR(zfw::sLowDepth, uv);
		return min(min(values.x, values.y), min(values.z, values.w));
	}
}

float getFastDepthPlusPlus(float2 uv, float LOD) {
	if (LOD < 1.) {
		return zfw::getDepth(uv);
	} else {
		return zfw::sampleDepth(uv, (LOD * 0.1) - 1.0);
	}
}


uint sliceStepsAO(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, inout uint bitfield, float3 n) {
	[loop]
    for (uint i = 0; i < steps; i++, t += step) {
        float2 samplePos = start + t * t * rayDir;
        samplePos = floor(samplePos) + 0.5;
        float2 samplePosUV = (samplePos.xy) / BUFFER_SCREEN_SIZE;
        
        if (!any(abs(samplePosUV - 0.5) <= 0.5)) { break; };
        
        
        float depth = getFastDepth(samplePosUV, t);
        float3 samplePosVS = zfw::uvzToView(samplePosUV, depth);
        float3 delta = samplePosVS - positionVS;
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + thickness * normalize(samplePosVS)), V)));
	    fb = saturate(((samplingDirection * -fb) - N + PI/2) / PI);
	    fb = fb.x > fb.y ? fb.yx : fb;
	    fb = smoothstep(0., 1., fb); // cosine lobe for AO. Trick by Marty (https://www.martysmods.com/)
	    
   	 uint a = ceil(fb.x * SECTORS);
    	uint b = floor((fb.y - fb.x) * SECTORS);
    	bitfield |= ((1 << b) - 1) << a;
    }
    return bitfield;
}

float calcAO(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float z = zfw::getDepth(uv);
	float3 positionVS = zfw::uvzToView(uv, z);
	float dist = length(positionVS);
	

	float ao = 0.0;
	float3 V = -positionVS/dist;
	float3 normalVS = zfw::getNormal(uv);
	positionVS *= 0.99; // something like intel XeGTAO line 283, why the fuck would it work better then the normal-based one? fuck if i know.

    float step = max(1.0, random.y + clamp(radius / dist, steps, radius * 4) / (steps + 1.0));
		
	[loop]	
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / slices) {
		float phi = 2.0 * 3.14159265359 * (slice + random.x);
		float2 direction = float2(cos(phi), sin(phi));
		
		float3 directionF3 = float3(direction, 0.0);
		float3 oDirV = directionF3 - dot(directionF3, V) * V;
		float3 sliceN = cross(directionF3, V);
		float3 projN = normalVS - sliceN * dot(normalVS, sliceN);
		float projNlength = length(projN);
		float cosN = saturate(dot(projN, V) / projNlength);
		float signN = -sign(dot(projN, oDirV));

		float N = signN * acos(cosN);
		
		uint aoBF = 0;
		float offset = max(step, length(BUFFER_PIXEL_SIZE)) / steps;
		sliceStepsAO(positionVS, V, vpos, direction, offset, step, 1, N, aoBF, normalVS);
		sliceStepsAO(positionVS, V, vpos, -direction, offset, step, -1, N, aoBF, normalVS);

		ao += float(countbits(aoBF)) * projNlength;
	}
	ao = 1.0 - ao / (float(SECTORS) * slices);
	return z == 1.0 || ao < -0.001 ? 1.0 : ao;
}

// GI!
uint sliceStepsGI(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, inout uint bitfield, float3 n, inout float3 GI) {
	[loop]
    for (uint i = 0; i < steps; i++, t += step) {
        float2 samplePos = start + t * t * rayDir;
        samplePos = floor(samplePos) + 0.5;
        float2 samplePosUV = (samplePos.xy) / BUFFER_SCREEN_SIZE;
        
        if (any(abs(samplePosUV - 0.5) >= 0.5)) { break; };
        
        
    	float LOD = floor(clamp(t * 0.4 - 0.8, 0., 10.));
        float depth = getFastDepthPlusPlus(samplePosUV, LOD) + 0.0001;
        float3 samplePosVS = zfw::uvzToView(samplePosUV, depth);
        float3 view = -normalize(samplePosVS);
        float3 delta = samplePosVS - positionVS;
        float thicknessModifier = clamp(samplePosVS.z * 0.1, 0.5, 1.2);
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + thickness * normalize(samplePosVS)), V)));
	    fb = saturate(((samplingDirection * -fb) - N + PI/2) / PI);
	    fb = fb.x > fb.y ? fb.yx : fb;
	    fb = smoothstep(0., 1., fb); // cosine lobe for AO & importance sampling lambertian for GI. Trick by Marty (https://www.martysmods.com/)
	    
   	 uint a = round(fb.x * SECTORS);
    	uint b = ceil((fb.y - fb.x) * SECTORS);
    	uint prevBF = bitfield;
    	bitfield |= ((1 << b) - 1) << a;
    	
    	
    	float3 stepNormal = zfw::sampleNormal(samplePosUV, LOD * 0.5);
    	if (depth > 0.99) { stepNormal = view; }; //sky case
    	uint bitfieldDelta = bitfield & ~prevBF;
    	float3 DI = tex2Dlod(sRadiance, float4(samplePosUV, 0., clamp(LOD, 0., 4.0))).rgb;
    	float spreadWeight = saturate(dot(normalize(delta), n));
    	float visibility = dot(-normalize(delta), stepNormal) > 0.0; // do not do backface light...
    	
    	GI += visibility * spreadWeight * DI * countbits(bitfieldDelta) / (steps * slices);
    	
    	//t *= power;
    }
    return bitfield;
}

float4 calcGI(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float z = zfw::getDepth(uv);
	float3 positionVS = zfw::uvzToView(uv, z);
	float dist = length(positionVS);
	

	float ao = 0.0;
	float3 GI = 0.0;
	
	float3 V = -positionVS/dist;
	float3 normalVS = zfw::getNormal(uv);
	positionVS *= 0.999; // something like intel XeGTAO line 283, why the fuck would it work better then the normal-based one? fuck if i know.
	
	
	
    float step = max(1.0, random.y * clamp(sqrt(length(BUFFER_SCREEN_SIZE)), steps, radius * 4) / (steps + 1.0));
		
	[loop]	
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / slices) {
		float phi = 2.0 * 3.14159265359 * (slice + random.x);
		float2 direction = float2(cos(phi), sin(phi));
		
		float3 directionF3 = float3(direction, 0.0);
		float3 oDirV = directionF3 - dot(directionF3, V) * V;
		float3 sliceN = cross(directionF3, V);
		float3 projN = normalVS - sliceN * dot(normalVS, sliceN);
		float projNlength = length(projN);
		float cosN = saturate(dot(projN, V) / projNlength);
		float signN = -sign(dot(projN, oDirV));

		float N = signN * acos(cosN);
		
		uint aoBF = 0;
		float offset = max(step, length(BUFFER_PIXEL_SIZE)) / steps;
		sliceStepsGI(positionVS, V, vpos, direction, offset, step, 1, N, aoBF, normalVS, GI);
		sliceStepsGI(positionVS, V, vpos, -direction, offset, step, -1, N, aoBF, normalVS, GI);

		ao += float(countbits(aoBF)) * projNlength;
	}
	ao = 1.0 - ao / (float(SECTORS) * slices);
	ao = z == 1.0 || ao < -0.001 ? 1.0 : ao;
	return float4(GI, ao);
}