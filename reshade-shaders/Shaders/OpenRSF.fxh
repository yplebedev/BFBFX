#pragma once
#include "ReShade.fxh"

#define RES(x) Width = BUFFER_WIDTH / x; Height = BUFFER_HEIGHT / x

#define POINT_SAMPLE \
	MagFilter = POINT;\
	MinFilter = POINT;\
	MipFilter = POINT

#if __RENDERER__ == 0x9000 || (__RENDERER__ >= 0x10000 && __RENDERER__ < 0x20000)
	#warning "Potentially unsupported API used; consider using a wrapper."
#endif


static const float PI = 3.14159265358979;
static const float TWO_PI = 2 * PI;
static const float HALF_PI = 0.5 * PI;

static const float GAUSS_3[9] = {
    1/16f, 1/8f, 1/16f, 
    1/8f, 1/4f, 1/8f, 
    1/16f, 1/8f, 1/16f, 
};

static const float GAUSS_5[25] = {
    1/273f , 4/273f , 7/273f , 4/273f , 1/273f ,
    4/273f , 16/273f, 26/273f, 16/273f, 4/273f ,
    7/273f , 26/273f, 41/273f, 26/273f, 7/273f ,
    4/273f , 16/273f, 26/273f, 16/273f, 4/273f ,
    1/273f , 4/273f , 7/273f , 4/273f , 1/273f 
};

static const float GAUSS_7[49] = {
    0/1003f  , 0/1003f  , 1/1003f  , 2/1003f  , 1/1003f  , 0/1003f  , 0/1003f  ,
    0/1003f  , 3/1003f  , 13/1003f , 22/1003f , 13/1003f , 3/1003f  , 0/1003f  ,
    1/1003f  , 13/1003f , 59/1003f , 97/1003f , 59/1003f , 13/1003f , 1/1003f  ,
    2/1003f  , 22/1003f , 97/1003f , 159/1003f, 97/1003f , 22/1003f , 2/1003f  ,
    1/1003f  , 13/1003f , 59/1003f , 97/1003f , 59/1003f , 13/1003f , 1/1003f  ,
    0/1003f  , 3/1003f  , 13/1003f , 22/1003f , 13/1003f , 3/1003f  , 0/1003f  ,
    0/1003f  , 0/1003f  , 1/1003f  , 2/1003f  , 1/1003f  , 0/1003f  , 0/1003f  ,
};

uniform float FOV<hidden = false;> = HALF_PI; // radians, vfov!!!

uniform float PEAK_LUMINANCE<hidden=true;> = 1000.0/10000.0; // https://en.wikipedia.org/wiki/Perceptual_quantizer                                                                                                                                                      |__/             

namespace ORSFShared {
	texture tAlbedo { RES(1); Format = RGB10A2; };
	sampler sAlbedo { Texture = tAlbedo; };
	
	texture tDepth { RES(1); Format = R16; MipLevels = 6; };
	sampler sDepth { Texture = tDepth; POINT_SAMPLE; };
	
	texture tSmoothN { RES(1); Format = RG16; };
	sampler sSmoothN { Texture = tSmoothN; POINT_SAMPLE; };
	
	texture tGeoN { RES(1); Format = RG16; };
	sampler sGeoN { Texture = tGeoN; POINT_SAMPLE; };
	
	texture tTexN { RES(1); Format = RG16; };
	sampler sTexN { Texture = tTexN; POINT_SAMPLE; };
	
	texture tMotion { RES(1); Format = RGBA16F; };
	sampler sMotion { Texture = tMotion; };
}

float2 OctWrap(float2 v)
{
    return (1.0- abs(v.yx)) * (v.xy >= 0.0 ? 1.0 : -1.0);
}
 
float3 UVtoOCT(float2 xy)
{
	
	float3 xyz = float3(2f * xy - 1f, 0.0);                

	float2 posAbs = abs(xyz.xy);
	xyz.z = 1.0 - (posAbs.x + posAbs.y);

	if(xyz.z < 0) {
        xyz.xy = sign(xyz.xy) * (1.0 - posAbs.yx);
	}
	return -xyz; //already normalized
}

float2 OCTtoUV(float3 xyz) {
	xyz = -xyz;
	float3 octsn = sign(xyz);
	
	float sd = dot(xyz, octsn);        
	float3 oct = xyz / sd;
	
	if(oct.z < 0) {
		float3 posAbs = abs(oct);
		oct.xy = octsn.xy * (1.0 - posAbs.yx);
	}
		return 0.5 + 0.5 * oct.xy;
}

float3 getNormal(float2 uv) {
	float2 encoded = tex2Dlod(ORSFShared::sTexN, float4(uv, 0., 0.)).rg;
	return normalize(UVtoOCT(encoded));
}

float3 getAlbedo(float2 uv) {
	return tex2D(ORSFShared::sAlbedo, uv).rgb;
}

float getDepth(float2 uv, float LOD = 0.) {
	return tex2Dlod(ORSFShared::sDepth, float4(uv, 0., LOD)).r;
}

float3 getMotion(float2 uv) {
	return tex2D(ORSFShared::sMotion, uv).xyz;
}

#define f RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define n 1.0

float REMAP_PRIVATE(float t, float src_from, float src_to, float dest_from, float dest_to) {
	return dest_from + (t - src_from) * (dest_to - dest_from) / (src_to - src_from);
}

#define remap(t, src_from, src_to, dest_from, dest_to) REMAP_PRIVATE(t, src_from, src_to, dest_from, dest_to)

float3 getViewPos(float2 uv, float z) {
	float fin_z = remap(z, 0., 1., n, f);
	float2 norm = (uv - 0.5.xx) * 2.0;
	float fl = 2.0 * tan(FOV * 0.5);
	
	float3 pos = float3(norm * fl * fin_z, fin_z);
	pos.y *= rcp(BUFFER_ASPECT_RATIO);
	
	return pos;
}

float3 getViewPos(float3 uvz) {
	float fin_z = remap(uvz.z, 0., 1., n, f);
	float2 norm = (uvz.xy - 0.5.xx) * 2.0;
	float fl = 2.0 * tan(FOV * 0.5);
	
	float3 pos = float3(norm * fl * fin_z, fin_z);
	pos.y *= rcp(BUFFER_ASPECT_RATIO);
	
	return pos;
}

#undef remap
#undef f
#undef n

float blur3x3_1(sampler input, float2 uv, float scale) {
	float accum = 0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).r * GAUSS_3[(deltaX + 1) + 3*(deltaY + 1)];
		}
	}
	return accum;
}

float2 blur3x3_2(sampler input, float2 uv, float scale) {
	float2 accum = 0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rg * GAUSS_3[(deltaX + 1) + 3*(deltaY + 1)];
		}
	}
	return accum;
}

float3 blur3x3_3(sampler input, float2 uv, float scale) {
	float3 accum = 0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgb * GAUSS_3[(deltaX + 1) + 3*(deltaY + 1)];
		}
	}
	return accum;
}

float4 blur3x3_4(sampler input, float2 uv, float scale) {
	float4 accum = 0;
	for (int deltaX = -1; deltaX <= 1; deltaX++) {
		for (int deltaY = -1; deltaY <= 1; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgba * GAUSS_3[(deltaX + 1) + 3*(deltaY + 1)];
		}
	}
	return accum;
}




float blur5x5_1(sampler input, float2 uv, float scale) {
	float accum = 0;
	for (int deltaX = -2; deltaX <= 2; deltaX++) {
		for (int deltaY = -2; deltaY <= 2; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).r * GAUSS_5[(deltaX + 2) + 5*(deltaY + 2)];
		}
	}
	return accum;
}

float2 blur5x5_2(sampler input, float2 uv, float scale) {
	float2 accum = 0;
	for (int deltaX = -2; deltaX <= 2; deltaX++) {
		for (int deltaY = -2; deltaY <= 2; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rg * GAUSS_5[(deltaX + 2) + 5*(deltaY + 2)];
		}
	}
	return accum;
}

float3 blur5x5_3(sampler input, float2 uv, float scale) {
	float3 accum = 0;
	for (int deltaX = -2; deltaX <= 2; deltaX++) {
		for (int deltaY = -2; deltaY <= 2; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgb * GAUSS_5[(deltaX + 2) + 5*(deltaY + 2)];
		}
	}
	return accum;
}

float4 blur5x5_4(sampler input, float2 uv, float scale) {
	float4 accum = 0;
	for (int deltaX = -2; deltaX <= 2; deltaX++) {
		for (int deltaY = -2; deltaY <= 2; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgba * GAUSS_5[(deltaX + 2) + 5*(deltaY + 2)];
		}
	}
	return accum;
}



float blur7x7_1(sampler input, float2 uv, float scale) {
	float accum = 0;
	for (int deltaX = -3; deltaX <= 3; deltaX++) {
		for (int deltaY = -3; deltaY <= 3; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).r * GAUSS_7[(deltaX + 3) + 7*(deltaY + 3)];
		}
	}
	return accum;
}


float2 blur7x7_2(sampler input, float2 uv, float scale) {
	float2 accum = 0;
	for (int deltaX = -3; deltaX <= 3; deltaX++) {
		for (int deltaY = -3; deltaY <= 3; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rg * GAUSS_7[(deltaX + 3) + 7*(deltaY + 3)];
		}
	}
	return accum;
}

float3 blur7x7_3(sampler input, float2 uv, float scale) {
	float3 accum = 0;
	for (int deltaX = -3; deltaX <= 3; deltaX++) {
		for (int deltaY = -3; deltaY <= 3; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgb * GAUSS_7[(deltaX + 3) + 7*(deltaY + 3)];
		}
	}
	return accum;
}

float4 blur7x7_4(sampler input, float2 uv, float scale) {
	float4 accum = 0;
	for (int deltaX = -3; deltaX <= 3; deltaX++) {
		for (int deltaY = -3; deltaY <= 3; deltaY++) {
			float2 offset = ReShade::PixelSize * scale * float2(deltaX, deltaY);
			accum += tex2Dlod(input, float4(uv + offset, 0., 0.)).rgba * GAUSS_7[(deltaX + 3) + 7*(deltaY + 3)];
		}
	}
	return accum;
}                                          

float3 BackBuf_to_rec709(float3 BackBufferColor) {
	#if BUFFER_COLOR_SPACE == 0
		return BackBufferColor; // Unknown, probably rare enough atp.
	#endif
	
	#if BUFFER_COLOR_SPACE == 1 // sRGB
		float r = BackBufferColor.r;
		float g = BackBufferColor.g;
		float b = BackBufferColor.b;
		
		r = (r <= 0.04045 ? r / 12.92 : pow((r + 0.055)/1.055, 2.4));
		g = (g <= 0.04045 ? g / 12.92 : pow((g + 0.055)/1.055, 2.4));
		b = (b <= 0.04045 ? b / 12.92 : pow((b + 0.055)/1.055, 2.4));
		
		return saturate(float3(r, g, b));
	#endif
	
	#if BUFFER_COLOR_SPACE == 2 // scRGB
		return BackBufferColor;
	#endif
	
	#if BUFFER_COLOR_SPACE == 2 // HDR10 ST2084
		float m1 = 0.1593017578125;
		float m2 = 78.84375;
		float c2 = 18.8515625;
		float c3 = 18.6875;
		float c1 = c3 - c2 + 1.0;
		
		return pow((c1 + c2 * pow(PEAK_LUMINANCE, m1)) / (1.0 + c3 * pow(PEAK_LUMINANCE, m1)), m2); // oh god, this will be fun in about six months or so
	#endif
	
	#if BUFFER_COLOR_SPACE == 3 // HDR10 HLG, https://en.wikipedia.org/wiki/Hybrid_log%E2%80%93gamma
		return 0.rrr; // Fake
	#endif
}


float3 rec709_to_BackBuf(float3 ToDisplay) {
	#if BUFFER_COLOR_SPACE == 0
		return ToDisplay; // Unknown, probably rare enough atp.
	#endif
	
	#if BUFFER_COLOR_SPACE == 1 // sRGB
		float r = ToDisplay.r;
		float g = ToDisplay.g;
		float b = ToDisplay.b;
		
		r = (r <= 0.0031308 ? r * 12.92 : 1.055 * pow(r, 1/2.4) - 0.055);
		g = (g <= 0.0031308 ? g * 12.92 : 1.055 * pow(g, 1/2.4) - 0.055);
		b = (b <= 0.0031308 ? b * 12.92 : 1.055 * pow(b, 1/2.4) - 0.055);
		
		return saturate(float3(r, g, b));
	#endif
	
	#if BUFFER_COLOR_SPACE == 2 // scRGB
		return ToDisplay;
	#endif
	
	#if BUFFER_COLOR_SPACE == 2 // HDR10 ST2084
		float m1 = 0.1593017578125;
		float m2 = 78.84375;
		float c2 = 18.8515625;
		float c3 = 18.6875;
		float c1 = c3 - c2 + 1.0;
		
		return pow(max(pow(ToDisplay, 1.0/m2) - c1, 0.0) / (c2 - c3 * pow(ToDisplay, 1.0/m2)), 1.0/m1); // oh god, this will be fun in about six months or so
	#endif
	
	#if BUFFER_COLOR_SPACE == 3 // HDR10 HLG, https://en.wikipedia.org/wiki/Hybrid_log%E2%80%93gamma
		return 0.rrr; // Literally not real
	#endif
}

float3 getSRGB(float3 linearSRGB) {
	float r = linearSRGB.r;
	float g = linearSRGB.g;
	float b = linearSRGB.b;
	
	r = (r <= 0.0031308 ? r * 12.92 : 1.055 * pow(r, 1/2.4) - 0.055);
	g = (g <= 0.0031308 ? g * 12.92 : 1.055 * pow(g, 1/2.4) - 0.055);
	b = (b <= 0.0031308 ? b * 12.92 : 1.055 * pow(b, 1/2.4) - 0.055);
	
	return saturate(float3(r, g, b));
}

float3 getLSRGB(float3 sRGB) {
	float r = sRGB.r;
	float g = sRGB.g;
	float b = sRGB.b;
		
	r = (r <= 0.04045 ? r / 12.92 : pow((r + 0.055)/1.055, 2.4));
	g = (g <= 0.04045 ? g / 12.92 : pow((g + 0.055)/1.055, 2.4));
	b = (b <= 0.04045 ? b / 12.92 : pow((b + 0.055)/1.055, 2.4));
		
	return saturate(float3(r, g, b));
}

// directly from https://bottosson.github.io/posts/oklab/
#define cbrtf(x) pow(x, 0.33333333)

float3 rec709_to_ok(float3 c) 
{
    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
	float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
	float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;

    float l_ = cbrtf(l);
    float m_ = cbrtf(m);
    float s_ = cbrtf(s);

    return float3 (
        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_
    );
}

float3 ok_to_rec709(float3 c) 
{
    float l_ = c.r + 0.3963377774f * c.g + 0.2158037573f * c.b;
    float m_ = c.r - 0.1055613458f * c.g - 0.0638541728f * c.b;
    float s_ = c.r - 0.0894841775f * c.g - 1.2914855480f * c.b;

    float l = l_*l_*l_;
    float m = m_*m_*m_;
    float s = s_*s_*s_;

    return float3(
		+4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
		-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
		-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s
    );
}

float3 oklch_to_ok(float3 lch) {
	return float3(lch.r, lch.g*cos(lch.b), lch.g*sin(lch.b));
}

float3 ok_to_oklch(float3 ok) {
	return float3(ok.r, length(ok.gb), atan2(ok.b, ok.g));
}

float3 rec709_to_xyz(float3 rec) {
	float3x3 toXYZ = float3x3(
		float3(0.4124564, 0.3575761, 0.1804375),
		float3(0.2126729, 0.7151522, 0.0721750),
		float3(0.0193339, 0.1191920, 0.9503041)
	);
	
	return mul(toXYZ, rec);
}

float3 xyz_to_rec709(float3 xyz) {
	float3x3 rec = float3x3(
		float3( 3.24045,   -1.53714, -0.498532),
		float3(-0.969266,   1.87601,  0.0415561),
		float3( 0.0556434, -0.204026, 1.05723)
	);
	
	return mul(rec, xyz);
}




float3 xyz_to_aces2065(float3 xyz) {
	float3x3 toACES2065_1 = float3x3(
		float3( 1.06349549153674,  0.006408910197529,-0.015806786587775),
		float3(-0.492074128004177, 1.368223407498281, 0.091337088325457),
		float3(-0.002816461639118, 0.004644171056578, 0.916418574549673)
	);
	
	return mul(toACES2065_1, xyz);
}

float3 aces2065_to_cg(float3 ACES2065_1) {
	float3x3 toACEScg = float3x3(
		float3( 1.4514393161, -0.2365107469, -0.2149285693),
		float3(-0.0765537734,  1.1762296998, -0.0996759264),
		float3( 0.0083161484, -0.0060324498,  0.9977163014)
	);
	
	return mul(toACEScg, ACES2065_1);
}

float3 cg_to_aces2065(float3 cg) {
	float3x3 to2065 = float3x3(
		float3( 0.6954522414, 0.1406786965, 0.1638690622),
		float3( 0.0447945634, 0.8596711185, 0.0955343182),
		float3(-0.0055258826, 0.0040252103, 1.0015006723)
	);
	
	return mul(to2065, cg);
}

float3 aces2065_to_xyz(float3 ACES2065_1) {
	float3x3 toxyz = float3x3(
		float3( 0.938279849239345, -0.00445144581227847, 0.0166275235564231),
		float3( 0.337368890823117, 0.729521566676754, -0.066890457499083),
		float3( 0.00117395084939056, -0.00371070640198378, 1.09159450636463)
	);
	
	return mul(toxyz, ACES2065_1);
}




float3 xyz_to_cg(float3 xyz) {
	return aces2065_to_cg(xyz_to_aces2065(xyz));
}

float3 cg_to_xyz(float3 cg) {
	return aces2065_to_xyz(cg_to_aces2065(cg));
}

// tonemapping...
static const float eps = 2e-6;
float3 getReinhardHDR(float3 SDR, float whitepoint, float saturation = 1.0) {
	float luma = rec709_to_ok(SDR).r * 0.5;
    float3 delta = SDR - float3(luma, luma, luma);
    float luma_tonemapped = max(-luma / (luma - 1 - rcp(whitepoint)), eps);
    return lerp(luma_tonemapped + delta, max(-SDR / (SDR - 1 - rcp(whitepoint)), eps), saturation); // good when not tonemapping with rein
}

float3 getReinhardSDR(float3 HDR, float whitepoint, float saturation = 1.0) {
	float luma = rec709_to_ok(HDR).r * 0.5;
	float3 delta = HDR - luma.rrr;
	float luma_tonemapped = (luma * (1.0 + luma / (whitepoint * whitepoint))) / (1.0 + luma);
	
	float3 tonemapped = (HDR * (1.0 + HDR / (whitepoint * whitepoint))) / (1.0 + HDR);

	return lerp(luma_tonemapped.rrr, tonemapped, saturate(saturation));
}

float3 max3(float x, float y, float z) { return max(x, max(y, z)); }
float3 getLottesHDR(float3 SDR, float whitepoint) {
	return SDR * (rcp(max(1.0 - max3(SDR.r, SDR.g, SDR.b) * whitepoint, eps)));
}

float3 getLottesSDR(float3 HDR, float whitepoint) {
	return HDR * rcp(max3(HDR.r, HDR.g, HDR.b) * whitepoint + 1.0);
}

#ifndef slope
	#define slope 0.88
#endif 

#ifndef toe
	#define toe 0.55
#endif 

#ifndef shoulder
	#define shoulder 0.26
#endif 

#ifndef black_c
	#define black_c 0.0
#endif 

#ifndef white_c
	#define white_c 0.04
#endif 


float aces_per_channel(float x) {
	x = log10(x);
	float s = 1.0; // whitepoint
	float ga = slope;
	float t0 = toe;
	float t1 = black_c;
	float s0 = shoulder;
	float s1 = white_c;
	
	float ta = (1.0 - t0 - 0.18) / ga - 0.733;
	float sa = (s0 - 0.18) / ga - 0.733;
	float result = 0.0;
	if (x < ta) {
		result = s * (2 * (1.0 + t1 - t0) / (1.0 + exp(-2 * ga * (x - ta) / (1 + t1 - t0))) - t1);
	} else if (x < sa) {
		result = s * (ga * (x + 0.733) + 0.18);
	} else {
		result = s * (1.0 + s1 - 2 * (1 + s1 - s0) / (1.0 + exp(2 * ga * (x - sa) / (1 + s1 - s0))));
	}
	return result;
}

#ifndef sat_preservation
	#define sat_preservation 1.0
#endif

#ifndef hue_preservation
	#define hue_preservation 1.0
#endif


float3 getACESSDR(float3 rgb) {
	float3 oklch = ok_to_oklch(rec709_to_ok(rgb));
	float3 tonemapped = float3(aces_per_channel(rgb.r), aces_per_channel(rgb.g), aces_per_channel(rgb.b));
	float3 oklch_of_tonemapped = ok_to_rec709(rec709_to_ok(tonemapped));
	
	oklch_of_tonemapped.b = lerp(oklch_of_tonemapped.b, oklch.b, hue_preservation * (dot(rgb, float3(1.0, 1.0, 1.0)) > 1.0));
	// hue shift is actually very minor, but saturation is getting fucked a notch.
	oklch_of_tonemapped.g = lerp(oklch_of_tonemapped.g, oklch.g, sat_preservation * (dot(rgb, float3(1.0, 1.0, 1.0)) < 1.0));
	
	
	return ok_to_rec709(oklch_to_ok(oklch_of_tonemapped));
}

#undef RES