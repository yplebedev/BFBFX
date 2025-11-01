uniform int framecount < source = "framecount"; >;

texture tBN <source = "stbn.png";> {Width = 1024; Height = 1024; Format = R8; };
sampler sBN { Texture = tBN; };

float2 getTemporalOffset() {
	return float2(framecount % 8, (framecount >> 3) % 8);
}

// also vpos
float2 stbn(float2 p) {
	#define xyOffset float2(5, 7)
	return float2(tex2Dfetch(sBN, (p % 64) + getTemporalOffset() * 64).x,
				  tex2Dfetch(sBN, ((p + xyOffset) % 64) + getTemporalOffset() * 64).x);
	
}