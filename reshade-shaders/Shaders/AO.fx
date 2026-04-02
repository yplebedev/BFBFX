#define WHITEPOINT 15
#include "OpenRSF.fxh"
#include "random.fxh"
#include "filtering.fxh"

uniform bool debug<ui_label = "Debug";> = false;

// Note; these *can* be uniforms. However, its easier to fuck these up in the GUI
// compared to finding good values. I know you'll poke these if you *really* want to.
static const float thickness = 4.0;
static const float radius = 1.5; // Fuck it, fulscreen step
static const uint directions = 1;
static const uint steps = 4;
static const float strength<ui_label = "Strength"; ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;> = 1.0; // This looks borked. 

float2 sort(float2 of) {
	return of.x > of.y ? of.yx : of.xy;
}

void compute_ao(inout float AO, float4 vpos, float2 uv) {
	float depth = getDepth(uv);
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
		[unroll]
		for (float direction = 1.0; direction >= -1.0; direction -= 2.0) {
			for (uint step = 0u; step < steps; step++) {
				float t = (float(step) + random.y - 0.5) / float(steps);
				float2 step_uv = uv + direction * direction_vector * t * t;
				
				if (!onscreen(step_uv)) break;
				float step_depth = tex2Dlod(ORSFShared::sDepth, float4(step_uv, 0., 0.)).x;
				if (step_depth > 0.99) continue;
				
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
				
				uint occluded = ((1u << set_range.y) - 1u) << set_range.x;
				bitmask |= occluded;
			}
		}
		
		AO += countbits(bitmask) * projected_normal_len;
	}
	
	AO /= directions * 32.;
	AO = 1.0 - AO;
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float3 output : SV_Target0) {
	float AO = 0.;	
	compute_ao(AO, vpos, uv);
	
	float3 motion = getMotion(uv);
	float2 minmax = minmax_search(sAOhistory, uv + motion.xy);
	
	float history = tex2D(sAOhistory, uv + motion.xy).r;
	history = clamp(history, minmax.x, minmax.y);
	output = lerp(history, AO, rcp(1. + tex2D(sAccumLength, uv).r));
}

float3 display_to_linear(float3 display) {
	return inverseTonemap(BackBuf_to_rec709(display));
}

float3 linear_to_display(float3 lin) {
	return rec709_to_BackBuf(tonemap(lin));
}

void blend(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 output : SV_Target0) {
	float AO = tex2D(sDenoised0, uv).r;
		
	if (debug) {
		output = AO.rrr;
	} else {
		output = tex2Dfetch(ReShade::BackBuffer, vpos.xy); 
		output.rgb = linear_to_display(display_to_linear(output.rgb) * pow(AO, strength));
	}
}

technique SSAO<ui_label = "BFBFX: SSAO";> {
	pass Reset { PixelShader = reset; VertexShader = PostProcessVS; RenderTarget = tAccumLength; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN;  }
	pass Main { PixelShader = main; VertexShader = PostProcessVS; RenderTarget = tAO; }
	pass Increment { PixelShader = increment; VertexShader = PostProcessVS; BlendEnable = true; BlendOp = ADD; SrcBlend = ONE; DestBlend = ONE; RenderTarget = tAccumLength; }
	pass Clamp { PixelShader = clamp_accum; VertexShader = PostProcessVS; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN; RenderTarget = tAccumLength; }
	
	pass Denoise { PixelShader = denoise_0; VertexShader = PostProcessVS; RenderTarget = tDenoised0; }
	pass Denoise { PixelShader = denoise_1; VertexShader = PostProcessVS; RenderTarget = tDenoised1; }
	pass Denoise { PixelShader = denoise_2; VertexShader = PostProcessVS; RenderTarget = tDenoised0; }
	pass Denoise { PixelShader = denoise_1; VertexShader = PostProcessVS; RenderTarget = tDenoised1; }
	pass Denoise { PixelShader = denoise_0; VertexShader = PostProcessVS; RenderTarget = tDenoised0; }
	
	pass Blend { PixelShader = blend; VertexShader = PostProcessVS; }
	pass TemporalLoop { PixelShader = copy_ao; VertexShader = PostProcessVS; RenderTarget = tAOhistory; }
}