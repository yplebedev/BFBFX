#pragma once

uniform int framecount < source = "framecount"; >;

texture tBN<source = "stbn.png";> { Format = R8; Width = 1024; Height = 1024; };
sampler sBN { Texture = tBN; AddressU = WRAP; AddressV = WRAP; };

float2 get_stbn(float2 vpos) {
	int frame = framecount % 64;
	return float2(
		tex2Dfetch(sBN, (vpos % 128) + float2((frame % 8) * 64., (frame / 8) * 64.)).r,
		tex2Dfetch(sBN, (vpos % 128) + float2((frame % 8) * 64., (frame / 8) * 64.) + float2(3., 7.)).r
		);
}