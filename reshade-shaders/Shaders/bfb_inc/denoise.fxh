#pragma once

static const float kernel[25] = {
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    3.0/128.0, 3.0/32.0,  9.0/64.0,  3.0/32.0,  3.0/128.0,
    1.0/64.0,  1.0/16.0,  3.0/32.0,  1.0/16.0,  1.0/64.0,
    1.0/256.0, 1.0/64.0,  3.0/128.0, 1.0/64.0,  1.0/256.0
};
static const float2 offset[25] = {
    float2(-2.0, -2.0), float2(-1.0, -2.0), float2(0.0, -2.0), float2(1.0, -2.0), float2(2.0, -2.0),
    float2(-2.0, -1.0), float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0), float2(2.0, -1.0),
    float2(-2.0,  0.0), float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0), float2(2.0,  0.0),
    float2(-2.0,  1.0), float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0), float2(2.0,  1.0),
    float2(-2.0,  2.0), float2(-1.0,  2.0), float2(0.0,  2.0), float2(1.0,  2.0), float2(2.0,  2.0)
};

// agnosticism along color, normals and pos. inverse for advanced.
#define c_phi 4.0
#define n_phi 128.0
#define p_phi 1.0
#define epsilon 0.2


// AO
texture tDNAO { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; };
sampler sDNAO { Texture = tDNAO; };

float atrous(sampler input, float2 texcoord, float level) {
	float4 noisy = tex2D(input, texcoord).r;
	float3 normal = zfw::getNormal(texcoord);
	float3 pos = zfw::uvToView(texcoord);
	float relaxation = dot(-normalize(pos), normal);
	
	float sum = 0.0;
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);

		float ctmp = tex2Dlod(input, float4(uv, 0.0, 0.0)).r;
		float4 t = noisy - ctmp;
		
		float dist2 = dot(t, t);
		float c_w = min(exp(-(dist2)/c_phi), 1.0);
		
		float3 ntmp = zfw::getNormal(uv);
		t = normal - ntmp;
		dist2 = max(dot(t, t), 0.0);
		float n_w = min(exp(-dist2 / n_phi), 1.0);
		
		
		float3 ptmp = zfw::uvToView(uv);
		t = pos - ptmp;
		t *= relaxation;
		dist2 = dot(t, t);
		float p_w = min(exp(-dist2 / p_phi), 1.0);
		p_w += 0.001;
		
		float weight = c_w * n_w * p_w;
		sum += ctmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	return sum/cum_w;
}


// GI
texture tDNGI { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDNGI { Texture = tDNGI; };

texture tDNGIs { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sDNGIs { Texture = tDNGIs; };

float3 lin2ok(float3 c) 
{
    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
	float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
	float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;

    float l_ = cbrtf(l);
    float m_ = cbrtf(m);
    float s_ = cbrtf(s);

    return float3(
        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_
    );
}

float3 ok2lin(float3 c) 
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

// SVGF stuff
void computeVariance(pData, out float variance : SV_Target0) {
	uint accumL = tex2D(sExpRejMask, uv).x;
	float luma = lin2ok(tex2D(sTAA, uv).rgb).r;
	float sumSquared = luma * luma;
	float sumOfSquares = tex2D(sLumaSquaredTAA, uv).r;
	variance = sumSquared - sumOfSquares;
	
	if (accumL <= 4u) {
		// spatial estimate
		sumOfSquares = 0.;
		float savedLuma = luma;
		luma = 0.;
	
		float3 normal = zfw::getNormal(uv);
		float z = zfw::getDepth(uv);
		
		float cum_w = 0.;
		for (int i = 0; i < 25; i++) {
			float2 curruv = uv + offset[i] * ReShade::PixelSize;
			
			float luma_tmp = lin2ok(tex2Dlod(sGI, float4(curruv, 0., 0.)).rgb).r;
			float luma_sq_tmp = tex2Dlod(sLumaSquared, float4(curruv, 0., 0.)).r;
			
			float3 N_tmp = zfw::getNormal(curruv);
			float Z_tmp = zfw::getDepth(curruv);
			
			float normalW = pow(saturate(dot(normal, N_tmp)), n_phi);
			
			
			float depthW = exp(-abs(z - Z_tmp) / (p_phi * abs(length(offset[i]) * (z - Z_tmp)) + epsilon)); // SVGF eq 3, hopefully correct.
			
			float lumW = exp(-abs(savedLuma - luma_tmp) / (c_phi + epsilon));
			
			float weight = normalW * depthW;
			sumOfSquares += weight * kernel[i] * luma_sq_tmp;
			luma += weight * kernel[i] * luma_tmp;
			cum_w += weight * kernel[i];
		}
		
		variance = luma * luma - sumOfSquares;
	}
}

texture tVariance { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 3; };
sampler sVariance { Texture = tVariance; MinLOD = 0.0f; MaxLOD = 2.0f; };

texture tVarianceS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sVarianceS { Texture = tVarianceS; };

float4 atrous_advanced(sampler gi, sampler sVar, float2 texcoord, float level, inout float variance) {
	float3 normal = zfw::getNormal(texcoord);
	float4 GI = tex2D(sTAA, texcoord);
	float z = zfw::getDepth(texcoord);
	float lum = lin2ok(GI.rgb).x;
	
	float4 sum = 0.0;
	float sum_var = 0.0;
	
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);
		
		float3 GI_tmp = tex2Dlod(gi, float4(uv, 0., 0.)).rgb;
		float AO_tmp = tex2Dlod(gi, float4(uv, 0., 0.)).a;
		float var_tmp = tex2Dlod(sVar, float4(uv, 0., 0.)).r;
		
		float3 N_tmp = zfw::getNormal(uv);
		float Z_tmp = zfw::getDepth(uv);
		float lum_tmp = lin2ok(GI_tmp).x;
		
		float normalW = pow(saturate(dot(normal, N_tmp)), n_phi);
		
		
		float depthW = exp(-abs(z - Z_tmp) / (p_phi * abs(length(offset[i]) * (z - Z_tmp)) + epsilon)); // SVGF eq 3, hopefully correct.
		
		float lumW = exp(-abs(lum - lum_tmp) / (c_phi * sqrt(variance) + epsilon));
		
		float weight = normalW * depthW;
		sum += float4(GI_tmp, AO_tmp) * weight * kernel[i];
		sum_var += var_tmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	variance = sum_var / cum_w;
	return sum / cum_w;
}