// Stores some color operations.
// Color spaces YAY!
// OKLab stuff from: https://gist.github.com/totallyRonja/8b9d571225f31c7a0d14872cf1478c85

#define lumaCoeff float3(0.2126, 0.7152, 0.0722)
#define gamma 2.2
#define hdr_modifier 3.0

float4 sRGBtoLinear(float4 s) {
	return pow(s, gamma);
}

float4 linearTosRGB(float4 l) {
	return pow(l, 1 / gamma);
}

static const float3x3 lrgb2cone = float3x3(
    0.412165612, 0.211859107, 0.0883097947,
    0.536275208, 0.6807189584, 0.2818474174,
    0.0514575653, 0.107406579, 0.6302613616
);

static const float3x3 cone2lab = float3x3(
    +0.2104542553, +1.9779984951, +0.0259040371,
    +0.7936177850, -2.4285922050, +0.7827717662,
    +0.0040720468, +0.4505937099, -0.8086757660);

static const float3x3 lab2cone = float3x3(
    +4.0767416621, -1.2684380046, -0.0041960863,
    -3.3077115913, +2.6097574011, -0.7034186147,
    +0.2309699292, -0.3413193965, +1.7076147010);

static const float3x3 cone2lrgb = float3x3(
    1, 1, 1,
    +0.3963377774f, -0.1055613458f, -0.0894841775f,
    +0.2158037573f, -0.0638541728f, -1.2914855480f);

//conversion from oklab to linear srgb
float3 oklab2lrgb(float3 col) {
    col = mul(col, cone2lrgb);
    col = col * col * col;
    col = mul(col, lab2cone);
    return col;
}

//with alpha copy
float4 oklab2lrgb(float4 col) {
    return float4(oklab2lrgb(col.rgb), col.a);
}

//conversion from linear srgb to oklab colorspace
float3 lrgb2oklab(float3 col) {
    col = mul(col, lrgb2cone);
    col = pow(col, 1.0 / 3.0);
    col = mul(col, cone2lab);
    return col;
}

//with alpha copy
float4 lrgb2oklab(float4 col) {
    return float4(lrgb2oklab(col.rgb), col.a);
}

float max3(float x, float y, float z) {
	return max(x, max(y, z)); 
}

float4 inverseTonemapLottes(float4 col) {
	col = saturate(col);
	col = sRGBtoLinear(col);
	col = max(col, 0.001) * 1.00001;
	return col * rcp(1.0 - max3(col.r, col.g, col.b));
}

float4 tonemapLottes(float4 c) {
	c = c * rcp(max3(c.r, c.g, c.b) + 1.0);
	return linearTosRGB(c);
}