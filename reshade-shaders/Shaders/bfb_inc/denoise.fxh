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


#define c_phi 0.3
#define n_phi 128.0
#define p_phi 1.0
#define epsilon 0.01


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



// SVGF stuff
void computeVariance(pData, out float variance : SV_Target0) {
	float luma = dot(tex2D(sTAA, uv).rgb, float3(0.2126, 0.7152, 0.0722));
	float sumSquared = luma * luma;
	float sumOfSquares = tex2D(sLumaSquaredTAA, uv).r;
	variance = sumOfSquares - sumSquared;
}


texture tVariance { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; MipLevels = 3; };
sampler sVariance { Texture = tVariance; MinLOD = 0.0f; MaxLOD = 2.0f; };

texture tVarianceS { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler sVarianceS { Texture = tVarianceS; };


#ifdef GI_D
float4 atrous_advanced(sampler gi, sampler sVar, float2 texcoord, float level, inout float variance) {
	float3 normal = zfw::getNormal(texcoord);
	float4 GI = tex2D(sTAA, texcoord);
	float z = zfw::getDepth(texcoord);
	float lum = dot(GI.rgb, float3(0.2126, 0.7152, 0.0722));
	
	float4 sum = 0.0;
	float sum_var = 0.0;
	
	float2 step = ReShade::PixelSize;
	
	float accumulation = float(tex2D(sAccum, texcoord).r);
	float3 mv = zfw::getVelocity(texcoord);
	
	float denominator = (col * sqrt(max(0., variance / (accumulation + 1e-6))) + epsilon);
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);
		
		float3 GI_tmp = tex2Dlod(gi, float4(uv, 0., 0.)).rgb;
		float AO_tmp = tex2Dlod(gi, float4(uv, 0., 0.)).a;
		float var_tmp = tex2Dlod(sVar, float4(uv, 0., 0.)).r;
		
		float3 N_tmp = zfw::getNormal(uv);
		float Z_tmp = zfw::getDepth(uv);
		float lum_tmp = dot(GI_tmp.rgb, float3(0.2126, 0.7152, 0.0722));
		
		float normalW = pow(saturate(dot(normal, N_tmp)), n_phi);
		float depthW = exp(-abs(z - Z_tmp) / (p_phi * abs(length(offset[i]) * (z - Z_tmp)) + epsilon)); // SVGF eq 3, hopefully correct.
		float lumW = exp(-abs(lum - lum_tmp) / denominator); 
		
		float weight = accumulation < 4u || mv.z < 0.9 ? (depthW * normalW) : (normalW * depthW * lumW);
		sum += float4(GI_tmp, AO_tmp) * weight * kernel[i];
		sum_var += var_tmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	variance = sum_var / cum_w;
	return sum / cum_w;
}
#endif