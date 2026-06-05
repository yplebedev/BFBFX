#define GI_SHADER
#define WHITEPOINT 15
#include "OpenRSF.fxh"
#include "random.fxh"
#include "filtering.fxh"

static const float thickness = 40.0;
static const float radius = 1.5;
static const uint directions = 1;
static const uint steps = 40;

float2 sort(float2 of) {
	return of.x > of.y ? of.yx : of.xy;
}

float3 display_to_linear(float3 display) {
	return inverseTonemap(BackBuf_to_rec709(display));
}

float3 linear_to_display(float3 lin) {
	float3 temp = tonemap(lin);
	#ifndef HDR_ON
		temp = saturate(temp);
	#endif
	return rec709_to_BackBuf(temp);
}

texture tRadiance { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = 9; };
sampler sRadiance { Texture = tRadiance; };


void compute_gi(inout float AO, inout float3 GI, float4 vpos, float2 uv) {
	float depth = getDepth(uv);
	if (depth > 0.99) return;
	float3 view_pos = getViewPos(uv, depth); view_pos *= 0.99;
	float3 view_vec = -normalize(view_pos);
	
	float3 view_normal = getNormal(uv);
	float2 random = get_stbn(vpos.xy);
	float direction = random.x * TWO_PI;
	
	for (uint i_direction = 0; i_direction < directions; i_direction++) {
		float current_direction = float(i_direction) / float(directions) + direction;
		float2 direction_vector = float2(cos(current_direction), sin(current_direction));
		
		float3 tangent = float3(direction_vector, 0.); 
		float3 projected_tangent = tangent - dot(tangent, view_vec) * view_vec;
		
		float3 slice_normal = cross(tangent, view_vec);
		float3 projected_normal = view_normal - slice_normal * dot(view_normal, slice_normal);
		float projected_normal_len = length(projected_normal);
		float cos_n = saturate(dot(projected_normal, view_vec) / projected_normal_len);
		float sign = -sign(dot(projected_normal, projected_tangent));
		float n = sign * acos(cos_n);
		
		uint bitmask = 0u;
		float3 illumination = 0.;
		[unroll]
		for (float direction = 1.0; direction >= -1.0; direction -= 2.0) {
			for (uint step = 0u; step < steps; step++) {
				float t = (float(step) + random.y - 0.5) / float(steps);
				float2 step_uv = uv + direction * direction_vector * t * t;
				
				if (!onscreen(step_uv)) break;
				float step_depth = tex2Dlod(ORSFShared::sDepth, float4(step_uv, 0., 0.)).x;
				if (step_depth > 0.99) continue;
				
				float3 normal = getNormal(step_uv);
				float3 radiance = tex2Dlod(sRadiance, float4(step_uv, 0., 0.)).rgb;
				
				float3 front = getViewPos(step_uv, step_depth);
				float3 delta_front = normalize(front - view_pos);
				float3 delta_back = normalize(front - view_pos - thickness * view_vec);
			
				
				float2 front_back_angles = acos(float2(
					dot(delta_front, view_vec), dot(delta_back, view_vec)
				));
				
				float2 extent = ((direction * -front_back_angles) - n + HALF_PI) / PI;
				extent = saturate(extent);
				extent = sort(extent);
				extent = smoothstep(0., 1., extent);
				uint2 set_range = uint2(
					ceil(extent.x * 32u),
					floor((extent.y - extent.x) * 32u)
				);
				
				uint old = bitmask;
				uint occluded = ((1u << set_range.y) - 1u) << set_range.x;
				bitmask |= occluded;
				
				
				
				
				illumination += radiance 
							 * (dot(-normalize(delta_front), normal) > 0.)
							 * (saturate(dot(normalize(delta_front), view_normal)))
							 * countbits(bitmask & ~old);
			}
		}
		
		GI += illumination;
		AO += countbits(bitmask) * projected_normal_len;
	}
	
	AO /= directions * 32.;
	AO = 1.0 - AO;
	
	GI /= directions * steps * 4.;
}


void radiance(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float3 output : SV_Target0) {
	float3 from_image = display_to_linear(tex2Dfetch(ReShade::BackBuffer, vpos.xy).rgb);
	
	float3 mv = getMotion(uv);
	float4 gi = tex2D(sDenoised1g, uv + mv.xy);
	gi.rgb = rec709_to_xyz(gi.rgb);
	gi.rgb = xyz_to_cg(gi.rgb);
	
	float3 albedo = getAlbedo(uv);
	albedo.rgb = rec709_to_xyz(albedo.rgb);
	albedo.rgb = xyz_to_cg(albedo.rgb);
	
	float3 from_history = gi.rgb * mv.z * getAlbedo(uv);
	
	output = from_image * gi. a + from_history;
	output = cg_to_xyz(output);
	output = xyz_to_rec709(output);
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 output : SV_Target0, out float luma_sq : SV_Target1) {
	float3 GI = 0.;
	float AO = 1.;
	compute_gi(AO, GI, vpos, uv);
	GI *= 32.0;
	
	float3 mv = getMotion(uv);
	
	float4 history = tex2D(sGIhistory, uv + mv.xy);
	
	float weight = rcp(1. + tex2D(sAccumLength, uv).r);
	output = lerp(history, float4(GI, AO), weight);
	
	const float luminance = luminance_from_rec709(GI.rgb);
	luma_sq = lerp(tex2D(sLumaSquaredHistory, uv + mv.xy).r, luminance * luminance, weight);
}

void comp_variance(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	float accum_frames = tex2D(sAccumLength, uv).r;
	float LOD = max(0., 5. - accum_frames);
	
	float luminance = luminance_from_rec709(tex2Dlod(sGI, float4(uv, 0., LOD)).rgb);
	float luminance_sq = tex2Dlod(sLumaSquared, float4(uv, 0., LOD)).r;
	
	float variance = luminance_sq - luminance * luminance;
	output = max(0., max(variance, luminance * luminance * 0.01)) / (1. + accum_frames);
}


uniform bool debug = false;
uniform float intensity = 0.01;
void blend(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 output : SV_Target0) {
	float4 gi = tex2Dfetch(sDenoised1g, vpos.xy);
	gi.rgb = rec709_to_xyz(gi.rgb);
	gi.rgb = xyz_to_cg(gi.rgb);
	
	float3 albedo = getAlbedo(uv);
	albedo.rgb = rec709_to_xyz(albedo.rgb);
	albedo.rgb = xyz_to_cg(albedo.rgb);
	
	float3 image = tex2D(ReShade::BackBuffer, uv).rgb;
	image.rgb = display_to_linear(image.rgb);
	image.rgb = rec709_to_xyz(image.rgb);
	image.rgb = xyz_to_cg(image.rgb);
	
	output = debug ? float4(gi.rgb + gi.a * 0.1, 1.0) : float4(albedo * intensity * gi.rgb + image * gi.a, 1.0);
	if (debug) return;
	
	output.rgb = cg_to_xyz(output.rgb);
	output.rgb = xyz_to_rec709(output.rgb);
	
	// sanitize!
	output.rgb = clamp(output.rgb, 0., HDR10_max_nits);
	output.rgb = linear_to_display(output.rgb);
	
	if ((output.r != output.r) || (output.b != output.b) || (output.g != output.g)) {
		output.rgb = float3(1., 0., 1.);
	}
}

technique GI<ui_label = "BFBFX: SSGI";> {
	pass Radiance { VertexShader = PostProcessVS; PixelShader = radiance; RenderTarget = tRadiance; }
	
	pass Reset { PixelShader = reset; VertexShader = PostProcessVS; RenderTarget = tAccumLength; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN;  }
	pass Main { VertexShader = PostProcessVS; PixelShader = main; RenderTarget0 = tGI; RenderTarget1 = tLumaSquared; }
	pass ComputeVariance { VertexShader = PostProcessVS; PixelShader = comp_variance; RenderTarget0 = tVariance; }
	pass Denoise { VertexShader = PostProcessVS; PixelShader = denoise_0; RenderTarget0 = tDenoised0g; RenderTarget1 = tVarianceS; }
	pass Denoise { VertexShader = PostProcessVS; PixelShader = denoise_1; RenderTarget0 = tDenoised1g; RenderTarget1 = tVariance; }
	pass Denoise { VertexShader = PostProcessVS; PixelShader = denoise_2; RenderTarget = tDenoised0g; RenderTarget1 = tVarianceS; }
	pass Denoise { VertexShader = PostProcessVS; PixelShader = denoise_3; RenderTarget = tDenoised1g; RenderTarget1 = tVariance; }
	
	
	pass Increment { PixelShader = increment; VertexShader = PostProcessVS; BlendEnable = true; BlendOp = ADD; SrcBlend = ONE; DestBlend = ONE; RenderTarget = tAccumLength; }
	pass Clamp { PixelShader = clamp_accum; VertexShader = PostProcessVS; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN; RenderTarget = tAccumLength; }
	
	pass Blend { VertexShader = PostProcessVS; PixelShader = blend; }
	
	
	pass TemporalLoop { PixelShader = copy_gi; VertexShader = PostProcessVS; RenderTarget0 = tGIhistory; RenderTarget1 = tLumaSquaredHistory; }
}