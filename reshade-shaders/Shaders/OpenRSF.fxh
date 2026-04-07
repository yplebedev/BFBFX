/**  Special thanks to these people for letting
*    use their work for HDR support:
*
*    MaxG3D / MaxG2D
*    Pumbo / Filippo Tarpini
*    EndlesslyFlowering / Lilium
*    
*    Creators of the respective standards.
**/

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

uniform float FOV<hidden = true;> = HALF_PI; // radians, vfov!!!

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


#if BUFFER_COLOR_SPACE == 0
	#define C_SRGB
#elif BUFFER_COLOR_SPACE == 1
	#define HDR_ON
	#define C_SCRGB
#elif BUFFER_COLOR_SPACE == 2
	#define BT2020_PQ
	#define HDR_ON
#else
	#define C_SRGB
#endif

float3 bt_2020_to_rec(float3 c) {
	const float3x3 to_rec = float3x3(
		float3(1.6604910021, -0.5876411388, -0.0728498633),
		float3(-0.1245504745,  1.1328998971, -0.0083494226),
		float3(-0.0181507634, -0.1005788980,  1.1187296614)
	);
	
	return mul(to_rec, c);
}

float3 rec_to_bt_2020(float3 c) {
	const float3x3 to_bt = float3x3(
		float3(0.6274038959,  0.3292830384,  0.0433130657),
		float3(0.0690972894,  0.9195403951,  0.0113623156),
		float3(0.0163914389,  0.0880133079,  0.8955952532)
	);
	
	return mul(to_bt, c);
}

// Directly from SimpleHDRShaders:
static const float sRGB_max_nits = 80.f;
static const float ReferenceWhiteNits_BT2408 = 203.f;
static const float sourceHDRWhitepoint = 80.f / sRGB_max_nits;
static const float HDR10_max_nits = 10000.f;
static const float mid_gray = 0.18f;

static const float PQ_constant_N = (2610.0 / 4096.0 / 4.0);
static const float PQ_constant_M = (2523.0 / 4096.0 * 128.0);
static const float PQ_constant_C1 = (3424.0 / 4096.0);
static const float PQ_constant_C2 = (2413.0 / 4096.0 * 32.0);
static const float PQ_constant_C3 = (2392.0 / 4096.0 * 32.0);
static const float PQMaxWhitePoint = HDR10_max_nits / sRGB_max_nits;

static const float3 BT2020_PrimaryRed = float3(0.6300, 0.3400, 0.0300);
static const float3 BT2020_PrimaryGreen = float3(0.3300, 0.6000, 0.0800);
static const float3 BT2020_PrimaryBlue = float3(0.1500, 0.0600, 1.0000);
static const float3 BT2020_WhitePoint = float3(0.3127, 0.3290, 0.3583);

float3 LinearToPQ(float3 linearCol) {
	linearCol /= HDR10_max_nits;

	float3 colToPow = pow(linearCol, PQ_constant_N);
	float3 numerator = PQ_constant_C1 + PQ_constant_C2 * colToPow;
	float3 denominator = 1.f + PQ_constant_C3 * colToPow;
	float3 pq = pow(numerator / denominator, PQ_constant_M);

	return pq;
}

float3 PQToLinear(float3 ST2084) {
	float3 colToPow = pow(ST2084, 1.0f / PQ_constant_M);
	float3 numerator = max(colToPow - PQ_constant_C1, 0.f);
	float3 denominator = PQ_constant_C2 - (PQ_constant_C3 * colToPow);
	float3 linearColor = pow(numerator / denominator, 1.f / PQ_constant_N);

	linearColor *= HDR10_max_nits;

	return linearColor;
}


float3 gamma_srgb(float3 linearSRGB) {
	float r = linearSRGB.r;
	float g = linearSRGB.g;
	float b = linearSRGB.b;
	
	r = (r <= 0.0031308 ? r * 12.92 : 1.055 * pow(r, 1/2.4) - 0.055);
	g = (g <= 0.0031308 ? g * 12.92 : 1.055 * pow(g, 1/2.4) - 0.055);
	b = (b <= 0.0031308 ? b * 12.92 : 1.055 * pow(b, 1/2.4) - 0.055);
	
	return saturate(float3(r, g, b));
}

float3 linearize_srgb(float3 sRGB) {
	float r = sRGB.r;
	float g = sRGB.g;
	float b = sRGB.b;
		
	r = (r <= 0.04045 ? r / 12.92 : pow((r + 0.055)/1.055, 2.4));
	g = (g <= 0.04045 ? g / 12.92 : pow((g + 0.055)/1.055, 2.4));
	b = (b <= 0.04045 ? b / 12.92 : pow((b + 0.055)/1.055, 2.4));
		
	return saturate(float3(r, g, b));
}

float3 BackBuf_to_rec709(float3 bb) {
	#ifdef C_SRGB
		return linearize_srgb(bb);
	#endif
	
	#ifdef C_SCRGB
		return bb;
	#endif
	
	#ifdef BT2020_PQ
		return bt_2020_to_rec(PQToLinear(bb));
	#endif
}

float3 rec709_to_BackBuf(float3 bb) {
	#ifdef C_SRGB
		return gamma_srgb(bb);
	#endif
	
	#ifdef C_SCRGB
		return bb;
	#endif
	
	#ifdef BT2020_PQ
		return LinearToPQ(rec_to_bt_2020(bb));
	#endif
}

// Directly from https://bottosson.github.io/posts/oklab/
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
		float3(0.4338873456,  0.3762240091,  0.1898886453),
		float3(0.2126390059,  0.7151686788,  0.0721923154),
		float3(0.0177500401,  0.1094476209,  0.8728023391)
	);
	
	return mul(toXYZ, rec);
}

float3 xyz_to_rec709(float3 xyz) {
	float3x3 rec = float3x3(
		float3(3.0803990907, -1.5373831776, -0.5430159131),
		float3(-0.9212233589,  1.8759675015,  0.0452558574),
		float3(0.0528739390, -0.2039769589,  1.1511030199)
	);
	
	return mul(rec, xyz);
}




float3 xyz_to_aces2065(float3 xyz) {
	float3x3 toACES2065_1 = float3x3(
		float3(1.0105283620,  0.0051800005, -0.0157083625),
		float3(-0.4673022484,  1.3693796728,  0.0979225756),
		float3(0.0003795563, -0.0011375197,  1.0007579634)
	);
	
	return mul(toACES2065_1, xyz);
}

float3 aces2065_to_cg(float3 ACES2065_1) {
	float3x3 toACEScg = float3x3(
		float3(1.4514393161, -0.2365107469, -0.2149285693),
		float3(-0.0765537733,  1.1762296998, -0.0996759265),
		float3(0.0083161484, -0.0060324498,  0.9977163014)
	);
	
	return mul(toACEScg, ACES2065_1);
}

float3 cg_to_aces2065(float3 cg) {
	float3x3 to2065 = float3x3(
		float3(0.6954522414,  0.1406786965,  0.1638690622),
		float3(0.0447945634,  0.8596711184,  0.0955343182),
		float3(-0.0055258826,  0.0040252103,  1.0015006723)
	);
	
	return mul(to2065, cg);
}

float3 aces2065_to_xyz(float3 ACES2065_1) {
	float3x3 toxyz = float3x3(
		float3(0.9878534487, -0.0037236048,  0.0158701560),
		float3(0.3371054160,  0.7289276303, -0.0660330462),
		float3(0.0000085116,  0.0008299538,  0.9991615346)
	);
	
	return mul(toxyz, ACES2065_1);
}


float3 xyz_to_cg(float3 xyz) {
	return aces2065_to_cg(xyz_to_aces2065(xyz));
}

float3 cg_to_xyz(float3 cg) {
	return aces2065_to_xyz(cg_to_aces2065(cg));
}


#ifndef WHITEPOINT
	#define WHITEPOINT 15.0
#endif

// https://github.com/Zenteon/FrameworkDocs/blob/7960864098f664967b87d8da4e4db3948cb5968f/Headers/FrameworkResources.fxh#L193
// p much, this works really well, and mine had a lot of edge case issues for uses outside of bloom.
// see ujelfx repo for the old stuff (warning; old code)
static const float TONEMAP_EPS = 0.0001;

float3 inverseTonemap(float3 c) {
	#ifdef HDR
		return c;
	#else
		float HDR_RED = 1.0 + rcp(WHITEPOINT);
		float l = dot(c, float3(0.2126, 0.7152,0.0722));
		c /= l + TONEMAP_EPS;
		return c * HDR_RED * l / (l + 1.0);
	#endif
}

float3 tonemap(float3 c) {
	#ifdef HDR
		return c;
	#else
		float HDR_RED = 1.0 + rcp(WHITEPOINT);
		float l = dot(c, float3(0.2126, 0.7152,0.0722));
		c /= l + TONEMAP_EPS;
		
		const float floor_val = 0.0000001;
		return max(c * -l / (l - HDR_RED), floor_val);
	#endif
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
#undef hue_preservation
#undef sat_preservation
#undef shoulder