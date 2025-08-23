#include "ReShade.fxh"
#define BUFFER_SIZE3 int3(BUFFER_WIDTH,BUFFER_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE)
#define GetDepth ReShade::GetLinearizedDepth

float getVposDepth(float2 vpos) {
	float2 texcoord = vpos * BUFFER_PIXEL_SIZE;
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
	#else // Do not check RESHADE_DEPTH_INPUT_X_OFFSET, since it may be a decimal number, which the preprocessor cannot handle
			texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
	#endif
	#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
			texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
	#else
			texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
	#endif
			float depth = tex2Dfetch(ReShade::DepthBuffer, texcoord * BUFFER_SCREEN_SIZE).x * RESHADE_DEPTH_MULTIPLIER;
	
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

float3 getWorldPosition(float2 coords, float depth) {
        float3 result = float3((2.0 * coords - 1.0) * depth, depth);

        result *= int3(BUFFER_WIDTH,BUFFER_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
        return result;
}

float3 getWorldPositionVpos(float2 vpos, float depth) {
        float3 result = float3((2.0 * vpos - 1.0) * depth, depth);

        result *= float3(1.0, 1.0, RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
        return result;
}

float3 getWorldPosition(float2 texcoord) {
	float depth = ReShade::GetLinearizedDepth(texcoord);
	float3 result = float3((texcoord * 2.0 - 1.0) * depth, depth);
	result *= float3(BUFFER_WIDTH, BUFFER_HEIGHT, RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	return result;
}

float3 getScreenPosition(float3 world) {
	float3 result = world / int3(BUFFER_WIDTH,BUFFER_HEIGHT,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	return float3(result.xy/result.z + 0.5, result.z);
}


float3 getScreenSpaceNormal(float2 texcoord) {
    float3 offset = float3(BUFFER_PIXEL_SIZE, 0.0);
    float2 posCenter = texcoord.xy;
    float2 posNorth  = posCenter - offset.zy;
    float2 posEast   = posCenter + offset.xz;

    float3 vertCenter = float3(posCenter - 0.5, 1) * ReShade::GetLinearizedDepth(posCenter);
    float3 vertNorth  = float3(posNorth - 0.5,  1) * ReShade::GetLinearizedDepth(posNorth);
    float3 vertEast   = float3(posEast - 0.5,   1) * ReShade::GetLinearizedDepth(posEast);

    return normalize(cross(vertNorth - vertCenter, vertCenter - vertEast));
}

float3 getWorldSpaceNormal(float2 texcoord) {
    float3 offset = float3(BUFFER_PIXEL_SIZE, 0);
    float2 posCenter = texcoord.xy;
    float2 posNorth  = posCenter - offset.zy;
    float2 posEast   = posCenter + offset.xz;
	float2 posSouth  = posCenter + offset.zy;
	float2 posWest   = posCenter - offset.xz;
	float  depthCenter = GetDepth(posCenter);
	float  depthNorth = GetDepth(posNorth);
	float  depthEast = GetDepth(posEast);
	float  depthSouth = GetDepth(posSouth);
	float  depthWest = GetDepth(posWest);
	bool2 dir = bool2(abs(depthCenter - depthNorth) < abs(depthCenter - depthSouth), abs(depthCenter - depthEast) < abs(depthCenter - depthWest));
	
	float3 vertCenter = getWorldPosition(posCenter,       depthCenter);
	/*
float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
    	float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
    	if (true) return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast));
*/
if (dir.x && dir.y) {
		float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
    	float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
    	return -normalize(cross(vertCenter - vertNorth, vertCenter - vertEast));
	} else if (!dir.x && !dir.y) {
		float3 vertSouth  = getWorldPosition(posSouth,  GetDepth(posSouth));
    	float3 vertWest   = getWorldPosition(posWest,   GetDepth(posWest));
    	return -normalize(cross(vertCenter - vertSouth, vertCenter - vertWest));		
	} else if (dir.x) {
		float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
		float3 vertWest   = getWorldPosition(posWest,   GetDepth(posWest));
		return -normalize(-cross(vertCenter - vertNorth, vertCenter - vertWest));
	} else {
		float3 vertSouth  = getWorldPosition(posSouth,  GetDepth(posSouth));
		float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
		return -normalize(-cross(vertCenter - vertSouth, vertCenter - vertEast));
	}
}

float4 getPackedWorldSpaceNormal(float2 texcoord) {
    float3 offset = float3(BUFFER_PIXEL_SIZE, 0);
    float2 posCenter = texcoord.xy;
    float2 posNorth  = posCenter - offset.zy;
    float2 posEast   = posCenter + offset.xz;
	float2 posSouth  = posCenter + offset.zy;
	float2 posWest   = posCenter - offset.xz;
	float  depthCenter = GetDepth(posCenter);
	float  depthNorth = GetDepth(posNorth);
	float  depthEast = GetDepth(posEast);
	float  depthSouth = GetDepth(posSouth);
	float  depthWest = GetDepth(posWest);
	bool2 dir = bool2(abs(depthCenter - depthNorth) < abs(depthCenter - depthSouth), abs(depthCenter - depthEast) < abs(depthCenter - depthWest));
	
	float3 vertCenter = getWorldPosition(posCenter,       depthCenter);
	/*
float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
    	float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
    	if (true) return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast));
*/
if (dir.x && dir.y) {
		float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
    	float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
    	return float4(-normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)), depthCenter);
	} else if (!dir.x && !dir.y) {
		float3 vertSouth  = getWorldPosition(posSouth,  GetDepth(posSouth));
    	float3 vertWest   = getWorldPosition(posWest,   GetDepth(posWest));
    	return float4(-normalize(cross(vertCenter - vertSouth, vertCenter - vertWest)), depthCenter);		
	} else if (dir.x) {
		float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
		float3 vertWest   = getWorldPosition(posWest,   GetDepth(posWest));
		return float4(-normalize(-cross(vertCenter - vertNorth, vertCenter - vertWest)), depthCenter);
	} else {
		float3 vertSouth  = getWorldPosition(posSouth,  GetDepth(posSouth));
		float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
		return float4(-normalize(-cross(vertCenter - vertSouth, vertCenter - vertEast)), depthCenter);
	}
}

float3 getWorldSpaceNormal2(float2 texcoord) {
    float3 offset = float3(BUFFER_PIXEL_SIZE, 0.0);
    float2 posCenter = texcoord.xy;
    float2 posNorth  = posCenter + offset.zy;
    float2 posEast   = posCenter - offset.xz;
	float3 vertCenter = getWorldPosition(posCenter,       GetDepth(posCenter));
    float3 vertNorth  = getWorldPosition(posNorth,  GetDepth(posNorth));
    float3 vertEast   = getWorldPosition(posEast,   GetDepth(posEast));
    
    return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast));
}