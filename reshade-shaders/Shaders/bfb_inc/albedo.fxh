#pragma once

#include "OpenRSF.fxh"

// r - in, r - out.
static const float mip = 0.0;

float down(sampler src, float2 uv, float scale = 1.0) {
	float accum = 0.0;
	float2 delta = ReShade::PixelSize * 0.5 * scale;
	
	accum += tex2Dlod(src, float4(uv, 0., 0)).r * 4;
	
	accum += tex2Dlod(src, float4(uv + delta, 0.,  mip)).r;
	
	delta.y *= -1.0;
	accum += tex2Dlod(src, float4(uv + delta, 0.,  mip)).r;
	
	delta.x *= -1.0;
	accum += tex2Dlod(src, float4(uv + delta, 0.,  mip)).r;
	
	delta.y *= -1.0;
	accum += tex2Dlod(src, float4(uv + delta, 0.,  mip)).r;
	
	return accum * 0.125;
}

float up(sampler src, float2 uv, float scale = 1.0) {
	float accum = 0.0;
	float2 delta = ReShade::PixelSize * 0.5 * scale;
	
	accum += tex2Dlod(src, float4(uv + float2(-delta.x * 2.0, 0.), 0., 0.)).r;
	accum += tex2Dlod(src, float4(uv + float2( delta.x * 2.0, 0.), 0., 0.)).r;
	accum += tex2Dlod(src, float4(uv + float2(0., -delta.y * 2.0), 0., 0.)).r;
	accum += tex2Dlod(src, float4(uv + float2(0.,  delta.y * 2.0), 0., 0.)).r;
	
	accum += tex2Dlod(src, float4(uv + float2(-delta.x, delta.y), 0., 0.)).r * 2.0;
	accum += tex2Dlod(src, float4(uv + float2( delta.x, delta.y), 0., 0.)).r * 2.0;
	accum += tex2Dlod(src, float4(uv + float2(-delta.x,-delta.y), 0., 0.)).r * 2.0;
	accum += tex2Dlod(src, float4(uv + float2( delta.x,-delta.y), 0., 0.)).r * 2.0;
	
	return accum / 12.0;
}

texture tSource { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; };
sampler sSource { Texture = tSource; };

texture tFinalBlurred { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16; };
sampler sFinalBlurred { Texture = tFinalBlurred; };

texture tBlur1 { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16; };
sampler sBlur1 { Texture = tBlur1; };

texture tBlur2 { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = R16; };
sampler sBlur2 { Texture = tBlur2; };

texture tBlur3 { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16; };
sampler sBlur3 { Texture = tBlur3; };

texture tBlur4 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = R16; };
sampler sBlur4 { Texture = tBlur4; };

texture tBlur5 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = R16; };
sampler sBlur5 { Texture = tBlur5; };

void prep_luma(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = rec709_to_ok(BackBuf_to_rec709(tex2Dfetch(ReShade::BackBuffer, vpos.xy).rgb)).r;
}

void blur_down0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sSource, uv, 2.0);
}

void blur_down1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sBlur1, uv, 4.0);
}

void blur_down2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sBlur2, uv, 8.0);
}

void blur_down3(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sBlur3, uv, 16.0);
}

void blur_down4(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sBlur4, uv, 32.0);
}

void blur_down5(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = down(sBlur5, uv, 64.0);
}

void blur_up0(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = up(sBlur5, uv, 2.0);
}

void blur_up1(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = up(sBlur4, uv, 4.0);
}

void blur_up2(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = up(sBlur3, uv, 8.0);
}

void blur_up3(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = up(sBlur2, uv, 16.0);
}

void blur_up4(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float res : SV_Target0) {
	res = up(sBlur1, uv, 32.0);
}

void albedo(float4 vpos : SV_Position, float2 uv : TEXCOORD, out float3 albedo : SV_Target0) {
	float3 source = rec709_to_ok(BackBuf_to_rec709(tex2Dfetch(ReShade::BackBuffer, vpos.xy).rgb));
	albedo = lerp(source, float3(lerp(1.0 - tex2Dfetch(sFinalBlurred, vpos.xy).r, 0.7, 0.2), source.gb), 0.5);
	albedo = ok_to_rec709(albedo);	
}