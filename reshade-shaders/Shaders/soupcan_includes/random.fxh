#ifndef PHI
	#define PHI 1.6180339887
#endif

#ifndef PI
	#define PI 3.1415
#endif


#ifndef g_lds
	#define g_lds 1.32471795724474602596
#endif

#ifndef a1_lds
	#define a1_lds 1.0 / g_lds
#endif

#ifndef a2_lds
	#define a2_lds 1.0 / (g_lds * g_lds)
#endif

uniform int random_value < source = "random"; min = 0; max = 4000; >;

bool insideCircle(float2 o) {
	return length(o) <= 1.0;
}

// A BUNCH of code from UberRT, thanks yet again <3
int getPixelIndex(float2 coords, int2 size) {
    int2 pxCoords = coords*size;
    return pxCoords.x+pxCoords.y*size.x+random_value;
}

int getPixelID(float2 intPos) {
	return intPos.x + (intPos.y * BUFFER_WIDTH);
}

float randomValue(uint seed) {
    seed = seed * 747796405 + 2891336453;
    uint result = ((seed>>((seed>>28)+4))^seed)*277803737;
    result = (result>>22)^result;
    return result/4294967295.0;
}

float3 randomTriple(in out uint seed) {
	float3 v = 0;
	v.x = randomValue(seed);
	v.y = randomValue(seed);
	v.z = randomValue(seed);
	return v;
}

float boxmuller(float r0, float r1) {
	return 0.25 * sqrt(-log(r0 + 0.00001))*cos(PI * 2.0 * r1) + 0.5;
}

float3 randomGauss3(float2 coords, in out uint seed) {
	float3 r = randomTriple(seed);
	float ox = boxmuller(r.x, r.y);
	float oy = boxmuller(r.x, r.z);
	float oz = boxmuller(r.z, r.y);
	return 0.5 - 2 * float3(ox, oy, oz);
}

float3 randomVec3(float2 coords, in out uint seed) {
	while (true) {
		float3 rng = randomGauss3(coords, seed);
		if (length(rng) <= 1.0) return normalize(rng);
	}
}

float2 goldenRatio(int n) {
	while (true) {
		float2 candidate = ((0.5 + a1_lds * n) % 1.0, (0.5 + a2_lds * n) % 1.0);
		return candidate;
	}
}

// modified/ported from marty's shadertoy
float2 r2_modified(in int idx, in float2 seed) {
    return frac(seed + float(idx) * float2(0.245122333753, 0.430159709002));
}

float2 randomInsideCircle(float2 center, float radius, float2 seed) {
	while (true) {
		int n = 0;
		float2 insideSquare = r2_modified(n, seed);
		if (insideCircle(insideSquare)) return insideSquare * radius + center;
		else n++;
	}
}

float2 randomOnCircle(float2 center, float radius, float2 seed) {
	// prolly inefficient but who cares.
	return normalize(randomInsideCircle(center, radius, seed));
}