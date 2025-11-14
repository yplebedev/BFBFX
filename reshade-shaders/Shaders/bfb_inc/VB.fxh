#include "stbn.fxh"
#include "settings.fxh"

float getFastAsfDepth(float2 uv, float t) {
	float res = 1.0; //default
	
	if (t < 32.0) {
		res = zfw::getDepth(uv);
	} else {
		res = zfw::sampleDepth(uv, 1.);
	}
	
	return res;
}

// no point in mutation
#define SECTORS 32
#define power 1.4
uint sliceStepsAO(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, inout uint bitfield) {
	[loop]
    for (uint i = 0; i < steps; i++, t += step) {
        float2 samplePos = start + t * rayDir;
        samplePos = floor(samplePos) + 0.5;
        float2 samplePosUV = (samplePos.xy) / BUFFER_SCREEN_SIZE;
        
        float2 range = saturate(samplePosUV * samplePosUV - samplePosUV);
		bool is_outside = range.x != -range.y; //and of course if we are not inside we are outside. 	
    	if (is_outside) break;
        
        float depth = getFastAsfDepth(samplePosUV, t);
        float3 samplePosVS = zfw::uvzToView(samplePosUV, depth);
        float3 delta = samplePosVS - positionVS;
        float thicknessModifier = clamp(samplePosVS.z * 0.1, 0.5, 1.2);
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + thickness * normalize(samplePosVS)), V)));
	    fb = saturate(((samplingDirection * -fb) - N + acos(-1.0)/2) / acos(-1.0));
	    fb = fb.x > fb.y ? fb.yx : fb;
	    fb = smoothstep(0., 1., fb); // cosine lobe for AO. Trick by Marty (https://www.martysmods.com/)
	    
   	 uint a = ceil(fb.x * SECTORS);
    	uint b = floor((fb.y - fb.x) * SECTORS);
    	bitfield |= ((1 << b) - 1) << a;
    	t *= power;
    }
    return bitfield;
}

float calcAO(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float z = zfw::getDepth(uv);
	float3 positionVS = zfw::uvzToView(uv, z);
	

	float ao = 0.0;
	
	float3 V = normalize(-positionVS);
	float3 normalVS = zfw::getNormal(uv);
	positionVS += 0.01 * normalVS;
	
    float step = max(1.0, random.y *  clamp(radius / positionVS.z, steps, radius * 4) / (steps + 1.0));
		
	[loop]	
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / slices) {
		//          ?????????
		float phi = 2.0 * acos(-1.0) * (slice + random.x);
		float2 direction = float2(cos(phi), sin(phi));
		
		float3 directionF3 = float3(direction, 0.0);
		float3 oDirV = directionF3 - dot(directionF3, V) * V;
		float3 sliceN = cross(directionF3, V);
		float3 projN = normalVS - sliceN * dot(normalVS, sliceN);
		float cosN = saturate(dot(projN, V) / length(projN));
		float signN = -sign(dot(projN, oDirV));

		float N = signN * acos(cosN);
		
		uint aoBF = 0;
		float offset = max(step, length(BUFFER_PIXEL_SIZE)) / steps;
		sliceStepsAO(positionVS, V, vpos, direction, offset, step, 1, N, aoBF);
		sliceStepsAO(positionVS, V, vpos, -direction, offset, step, -1, N, aoBF);

		ao += float(countbits(aoBF)) * length(projN);
	}
	ao = 1.0 - ao / (float(SECTORS) * slices);
	return z < 0.001|| z == 1.0 || ao < -0.001 ? 1.0 : ao;
}