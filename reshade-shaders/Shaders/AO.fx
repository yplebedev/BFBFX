#include "OpenRSF.fxh"
#include "filtering.fxh"

uniform int framecount < source = "framecount"; >;
static const uint bitmask_size = 32u;

// Note; these *can* be uniforms. However, its easier to fuck these up in the GUI
// compared to finding good values. I know you'll poke these if you *really* want to.
static const float thickness = 4.0;
static const float radius = 1 << 13; // thanks hlsl.
static const uint samples = 1;
static const uint steps = 20;

float2 hash23(float2 pos, float time) {
	float3 p3 = float3(pos, time);
	p3 = frac(p3 * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return frac((p3.xx+p3.yz)*p3.zy);
}

float2 sort_asc(float2 of) {
	return float2(min(of.x, of.y), max(of.x, of.y));
}

void set_own_projection_data(in float3 tangent, in float3 projected_tangent, in float3 view_vec, in float3 normal, out float projected_normal_len, out float projection_angle_change) {
	float3 slice_normal = cross(tangent, view_vec);
	float3 projected_normal = normal - slice_normal * dot(normal, slice_normal);
	projected_normal_len = length(projected_normal); // OUT
	float cos_angle_change = saturate(dot(projected_normal, view_vec) / projected_normal_len);
	float sign = -sign(dot(projected_normal, projected_tangent));
	projection_angle_change = sign * acos(cos_angle_change); // OUT
}

void main(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float output : SV_Target0) {
	float AO = 0.;
	
	float depth = getDepth(uv);
	float3 view_pos = getViewPos(uv, depth); view_pos *= 0.99;
	float3 view_vec = -normalize(view_pos);
	
	float3 view_normal = getNormal(uv);
	float direction = hash23(vpos.xy, framecount * 3.).x * TWO_PI;
	
	for (uint i_direction = 0; i_direction < samples; i_direction++) {
		float alpha = float(i_direction) / float(samples) + direction;
		float2 direction_vector = float2(cos(alpha), sin(alpha));
		
		float3 tangent = float3(direction_vector, 0.); 
		float3 projected_tangent = tangent - dot(tangent, view_vec) * view_vec;
		
		float projected_normal_len = -1.;
		float projection_angle_change = -1.;
		set_own_projection_data(tangent, projected_tangent, view_vec, view_normal, projected_normal_len, projection_angle_change);
		
		uint bitmask = 0u;
		for (float direction = 1.0; direction >= -1.0; direction -= 2.0) {
			for (uint step = 1u; step <= steps; step++) {
				float2 step_pixel_loc = vpos.xy + direction_vector * lerp(1.0, radius, float(step) / float(steps)) * direction / length(view_pos);
				step_pixel_loc = floor(step_pixel_loc) + 0.5;
				float2 step_uv = step_pixel_loc / BUFFER_SCREEN_SIZE;
				
				if (!onscreen(step_uv)) break;
				float step_depth = getDepth(step_uv);
				if (step_depth > 0.99) break; // fix for weirdness around the sky
				
				float3 front = getViewPos(step_uv, step_depth);
				float3 delta_front = normalize(front - view_pos);
				float3 delta_back = normalize(front - view_pos - thickness * view_vec);
			
				
				float2 front_back_angles = acos(float2(
					dot(delta_front, view_vec), dot(delta_back, view_vec)
				));
				float2 extent = saturate(((direction * -front_back_angles) - projection_angle_change + HALF_PI) / PI);
				extent = saturate(extent);
				extent = sort_asc(extent);
				extent = smoothstep(0., 1., extent);
				uint2 set_range = uint2(
					ceil(extent.x * bitmask_size),
					floor((extent.y - extent.x) * bitmask_size)
				);
				
				uint step_mask = ((1u << set_range.y) - 1u) << set_range.x;
				bitmask |= step_mask;
			}
		}
		
		AO += countbits(bitmask) * projected_normal_len;
	}
	
	AO /= samples * float(bitmask_size);
	AO = 1.0 - AO;
	
	float3 motion = getMotion(uv);
	output = lerp(tex2D(sAOhistory, uv + motion.xy).r, AO, rcp(1. + tex2D(sAccumLength, uv).r));
}

void blend(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float4 output : SV_Target0) {
	output = float4(tex2D(sAO, uv).rrr, 1.0);
}

technique SSAO<ui_label = "BFBFX: SSAO";> {
	pass Reset { PixelShader = reset; VertexShader = PostProcessVS; RenderTarget = tAccumLength; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN;  }
	pass Main { PixelShader = main; VertexShader = PostProcessVS; RenderTarget = tAO; }
	pass Increment { PixelShader = increment; VertexShader = PostProcessVS; BlendEnable = true; BlendOp = ADD; SrcBlend = ONE; DestBlend = ONE; RenderTarget = tAccumLength; }
	pass Clamp { PixelShader = clamp; VertexShader = PostProcessVS; BlendEnable = true; SrcBlend = ONE; DestBlend = ONE; BlendOp = MIN; RenderTarget = tAccumLength; }
	
	pass Blend { PixelShader = blend; VertexShader = PostProcessVS; }
	pass TemporalLoop { PixelShader = copy_ao; VertexShader = PostProcessVS; RenderTarget = tAOhistory; }
}