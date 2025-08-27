// VBGTAO
// MIT License...
/* Copyright (c)2025 Yaraslau Lebedzeu.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/

/*

  _____                                                             _       __ _                  
 |  __ \                                                           | |     / _(_)                 
 | |__) | __ ___ _ __  _ __ ___   ___ ___  ___ ___  ___  _ __    __| | ___| |_ _ _ __   ___  ___  
 |  ___/ '__/ _ \ '_ \| '__/ _ \ / __/ _ \/ __/ __|/ _ \| '__|  / _` |/ _ \  _| | '_ \ / _ \/ __| 
 | |   | | |  __/ |_) | | | (_) | (_|  __/\__ \__ \ (_) | |    | (_| |  __/ | | | | | |  __/\__ \ 
 |_|   |_|  \___| .__/|_|  \___/ \___\___||___/___/\___/|_|     \__,_|\___|_| |_|_| |_|\___||___/ 
                | |                                                                               
                |_|                                                                               
*/

#include "ReShade.fxh"
#include "soupcan_includes/FrameworkResources.fxh"

#ifndef PI
	#define PI 3.14159265358979
#endif

#define __PXSDECL__ (float4 vpos : SV_Position, float2 uv : TEXCOORD) : SV_Target

uniform float c_phi<hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 10.0;> = 1.0; // Color avoiding
uniform float n_phi<hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 10.0;> = 1.0; // Normals
uniform float p_phi<hidden = true; ui_type = "slider"; ui_min = 0.0; ui_max = 10.0;> = 2.0; // Depth

#ifndef SCVBAO_SLICES
	#define SCVBAO_SLICES 2
#endif

#ifndef SCVBAO_STEPS
		#define SCVBAO_STEPS 7
#endif

// sacrifice MV usage for more spatial filtering
// pair with disabling MVs in the framework shader, if the PR goes thru.
// ALSO, since this denoises more aggresivly, there's very little point in having textured normals
#ifndef SCAO_USE_MV
	#define SCAO_USE_MV 1
#endif


#define SECTORS 32

#define FAR_CLIP (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE-1)

/*

  _    _       _  __                         
 | |  | |     (_)/ _|                        
 | |  | |_ __  _| |_ ___  _ __ _ __ ___  ___ 
 | |  | | '_ \| |  _/ _ \| '__| '_ ` _ \/ __|
 | |__| | | | | | || (_) | |  | | | | | \__ \
  \____/|_| |_|_|_| \___/|_|  |_| |_| |_|___/
                                             
                                             
*/


uniform int framecount < source = "framecount"; >;

uniform float historySize <ui_type = "slider"; ui_label = "Frame Blending"; ui_tooltip = "Affects the noise over update speed and ghosting ratios. \nThis can be higher on higher FPS. \n0 is no accumulation, and the closer to 1 the more previous results affect the image. \n\nPerformance impact: None"; ui_min = 0.0; ui_max = 0.999;> = 0.6; 
uniform bool debug <ui_label = "Debug view"; ui_tooltip = "Enabled intermediate AO view. \nUseful to gauge the noise and if everything works fine. \n\n Performance impact: None";> = false;
uniform float strength <ui_type = "slider"; ui_label = "Strength"; ui_tooltip = "How much AO affects the input colors. \n\nPerformance impact: None"; ui_min = 0.0; ui_max = 1.0;> = 1.0; 
uniform float power <hidden = true; ui_type = "slider"; ui_label = "Sampling bias power"; ui_tooltip = "A bias to sample closer-by stuff more. Increasing increases effective radius and occlusion from small objects."; ui_min = 1.0; ui_max = 3.0;> = 1.3; 
uniform float R <ui_type = "slider"; ui_label = "Radius"; ui_tooltip = "Increases the effect scale. \nShould be as high as possible. \n\nPerfomance impact: None/minimal"; ui_min = 50.0; ui_max = 2000.0;> = 225.0; 
uniform float THICKNESS <ui_type = "slider"; ui_label = "Thickness"; ui_tooltip = "SCVBAO uses... you guessed it, VBAO. It allows for a thickness heuristic. \nDon't set this too high or low! \n\nPerfomance impact: None, but increases noise"; ui_min = 0.0; ui_max = 4.0;> = 2.0; 

uniform float sampleQThresh1 <hidden = false; ui_type = "slider"; ui_label = "Res dropoff"; ui_tooltip = "How far away to swap out the depth resolution."; ui_min = 0.0; ui_max = 20.0;> = 4.0;

uniform int PREPROC_GUIDE <
	ui_type = "radio";
	ui_category = "Preprocessor Guide";
	ui_category_closed = true;
	ui_text = "\n\nThe preprocessor for SCAO stores some pretty important quality/performance settings\n\n- SCAO_USE_MV: defines if the shader tries to use temporal accumulation. \nThis isn't mandatory, and the end result with this on does look better, though if you experience ghosting keep this off. \n\n- SCVBAO_SLICES: Directly controlls noise levels. \nHigher values take significantly longer to render!\n\n- SCVBAO_STEPS: Defines how precisely the geometry is considered. \nHigher values improve shadowing and detail, and lower noise a little. \nLower values perform significantly better. \n\n\n Pro tip: use both the debug and default view to gaguge noise! You can find the frametime and FPS in the statistics tab on the top of the ReShade menu!";
> = 0;

/*

  _______        _                                                            _               
 |__   __|      | |                         ___                              | |              
    | | _____  _| |_ _   _ _ __ ___  ___   ( _ )    ___  __ _ _ __ ___  _ __ | | ___ _ __ ___ 
    | |/ _ \ \/ / __| | | | '__/ _ \/ __|  / _ \/\ / __|/ _` | '_ ` _ \| '_ \| |/ _ \ '__/ __|
    | |  __/>  <| |_| |_| | | |  __/\__ \ | (_>  < \__ \ (_| | | | | | | |_) | |  __/ |  \__ \
    |_|\___/_/\_\\__|\__,_|_|  \___||___/  \___/\/ |___/\__,_|_| |_| |_| .__/|_|\___|_|  |___/
                                                                       | |                    
                                                                       |_|                    
*/

texture bnt <source = "stbn.png";> {Width = 1024; Height = 1024; Format = R8; };
sampler bn { Texture = bnt; };


texture AO1 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAO1 { Texture = AO1;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
texture AO2 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAO2 { Texture = AO2; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture AO3 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8; };
sampler sAO3 { Texture = AO3; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
// Optimization is fun asf.
texture minZ { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16; };
sampler sminZ { Texture = minZ; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture minZ2 { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = R16; };
sampler sminZ2 { Texture = minZ2; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
texture minZ3 { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = R16; };
sampler sminZ3 { Texture = minZ3; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
	
sampler lowN { Texture = zfw::tLowNormal;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
sampler highN{ Texture = zfw::tNormal;
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
	
texture prevD { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = R16; };
sampler sprevD { Texture = prevD; 
	MagFilter = POINT;
	MinFilter = POINT;
	MipFilter = POINT; };
/* 

   _____                _       
  / ____|              | |      
 | |     ___  _ __  ___| |_ ___ 
 | |    / _ \| '_ \/ __| __/ __|
 | |___| (_) | | | \__ \ |_\__ \
  \_____\___/|_| |_|___/\__|___/
 (That arent hash-defs)
                                
*/

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

static const float kernel_3[9] = {
    1.0/16.0, 1.0/8.0, 1.0/16.0,
    1.0/8.0,  1.0/4.0, 1.0/8.0 ,
    1.0/16.0, 1.0/8.0, 1.0/16.0
};
static const float2 offset_3[9] = {
    float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0),
	float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0),
	float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0)
};

/* 


  _    _ _   _ _ _ _         
 | |  | | | (_) (_) |        
 | |  | | |_ _| |_| |_ _   _ 
 | |  | | __| | | | __| | | |
 | |__| | |_| | | | |_| |_| |
  \____/ \__|_|_|_|\__|\__, |
                        __/ |
                       |___/ 
*/

// STBN stuff
float2 getTemporalOffset() {
	return float2(framecount % 8, (framecount >> 3) % 8);
}

// also vpos
float2 stbn(float2 p) {
	#define xyOffset float2(5, 7)
	return float2(tex2Dfetch(bn, (p % 64) + getTemporalOffset() * 64).x,
				  tex2Dfetch(bn, ((p + xyOffset) % 64) + getTemporalOffset() * 64).x);
	
}

// Gathers pixels around the sample point
// By Zenteon
float4 GatherLinDepth(float2 texcoord, sampler s) {
    #if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    texcoord.y = 1.0 - texcoord.y;
    #endif
    #if RESHADE_DEPTH_INPUT_IS_MIRRORED
            texcoord.x = 1.0 - texcoord.x;
    #endif
    texcoord.x /= RESHADE_DEPTH_INPUT_X_SCALE;
    texcoord.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
    #if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    texcoord.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
    #else
    texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
    #endif
    #if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
    #else
    texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
    #endif
    float4 depth = tex2DgatherR(s, texcoord) * RESHADE_DEPTH_MULTIPLIER;
    
    #if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    const float C = 0.01;
    depth = (exp(depth * log(C + 1.0)) - 1.0) / C;
    #endif
    #if RESHADE_DEPTH_INPUT_IS_REVERSED
    depth = 1.0 - depth;
    #endif
    const float N = 1.0;
    depth /= RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - depth * (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - N);
    
    return depth;
}

// Quickly transforms f3 and f to f4
float4 autoF4(float3 x) {
	return float4(x, 1.0);
}
float4 autoF4(float x) {
	return float4(x, x, x, 1.0);
}

// One denoiser pass.
float4 atrous(sampler input, float2 texcoord, float level) {
	float4 noisy = tex2D(input, texcoord);
	float3 normal = zfw::getNormal(texcoord);
	float3 pos = zfw::uvToView(texcoord);
	
	float4 sum = 0.0;
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 25; i++) {
		float2 uv = texcoord + offset[i] * step * exp2(level);

		float4 ctmp = tex2Dlod(input, float4(uv, 0.0, 0.0));
		float4 t = noisy - ctmp;
		
		float dist2 = dot(t, t);
		float c_w = min(exp(-(dist2)/c_phi), 1.0);
		
		float3 ntmp = zfw::getNormal(uv);
		t = normal - ntmp;
		dist2 = max(dot(t, t), 0.0);
		float n_w = min(exp(-dist2 / n_phi), 1.0);
		
		
		float3 ptmp = zfw::uvToView(uv);
		t = pos - ptmp;
		dist2 = dot(t, t);
		float p_w = min(exp(-dist2 / p_phi), 1.0);
		p_w += 0.001;
		
		float weight = c_w * n_w * p_w;
		sum += ctmp * weight * kernel[i];
		cum_w += weight * kernel[i];
	}
	return sum/cum_w;
}

// Smaller kernel, shaper and faster
float4 atrous_low(sampler input, float2 texcoord, float level) {
	float4 noisy = tex2D(input, texcoord);
	float3 normal = zfw::getNormal(texcoord);
	float3 pos = zfw::uvToView(texcoord);
	
	float4 sum = 0.0;
	float2 step = ReShade::PixelSize;
	
	
	float cum_w = 0.0;
	[unroll]
	for (int i = 0; i < 9; i++) {
		float2 uv = texcoord + offset_3[i] * step * exp2(level);

		float4 ctmp = tex2Dlod(input, float4(uv, 0.0, 0.0));
		float4 t = noisy - ctmp;
		
		float dist2 = dot(t, t);
		float c_w = min(exp(-(dist2)/c_phi), 1.0);
		
		float3 ntmp = zfw::getNormal(uv);
		t = normal - ntmp;
		dist2 = max(dot(t, t), 0.0);
		float n_w = min(exp(-dist2 / n_phi), 1.0);
		
		float fullZ = ReShade::GetLinearizedDepth(uv);
		float3 ptmp = zfw::uvzToView(uv, fullZ);
		t = pos - ptmp;
		dist2 = dot(t, t);
		float p_w = min(exp(-dist2 / p_phi), 1.0);
		p_w += 0.001;
		
		
		float weight = c_w * n_w * p_w;
		sum += ctmp * weight * kernel_3[i];
		cum_w += weight * kernel_3[i];
	}
	return sum/cum_w;
}

// Upsamples 2x from depth and normals
// Modified from papadanku.github.io
// https://www.semanticscholar.org/paper/Multistep-joint-bilateral-depth-upsampling-Riemens-Gangwal/1ddf9ad017faf63b04778c1ddfc2330d64445da8
float4 bilateralUpscale(
   sampler image, // This should be 1/2 the size as guideHigh
   sampler guideLow, // This should be 1/2 the size as guideHigh
   sampler guideHigh, // This should be 2/1 the size as image and guideLow
   float2 tex
)
{
   // Initialize variables
   float2 pixelSize = ldexp(fwidth(tex.xy), 1.0);
   float4 guideHighSample = tex2D(guideHigh, tex);
   float guideHighZ = ReShade::GetLinearizedDepth(tex);
   float4 bilateralSum = 0.0;
   float4 weightSum = 0.0;

   [unroll]
   for (int dx = -1; dx <= 1; dx++)
   {
      [unroll]
      for (int dy = -1; dy <= 1; dy++)
      {
         // Calculate offset
         float2 offset = float2(float(dx), float(dy));
         float2 offsetTex = tex + (offset * pixelSize);

         // Sample image and guide
         float4 imageSample = tex2Dlod(image, float4(offsetTex, 0.0, 0.0));
         float4 guideLowSample = tex2D(guideLow, offsetTex);
         float guideLowZ = tex2D(sminZ, offsetTex).r;

         // Calculate weight
         float3 delta = guideLowSample.xyz - guideHighSample.xyz;
         float deltaZ = guideLowZ - guideHighZ;
         float dotDD = dot(delta, delta) * dot(deltaZ, deltaZ);
         float weight = (dotDD > 0.0) ? 1.0 / dotDD : 1.0;

         bilateralSum += (imageSample * weight);
         weightSum += weight;
      }
   }

   return bilateralSum / weightSum;
}
 
float2 snapVPOS(float2 vpos) {
	return floor(vpos) + float2(0.5, 0.5);
}

float2 snapVPOS2(float2 vpos) {
	return floor(vpos / 2.0) * 2.0 + float2(1.0, 1.0);
}

float2 snapVPOS3(float2 vpos) {
	return floor(vpos / 4.0) * 4.0 + float2(2.0, 2.0);
}

float2 snapVPOS4(float2 vpos) {
	return floor(vpos / 8.0) * 8.0 + float2(4.0, 4.0);
}

// Fetches lower res depth further away to save on fetch costs.
//                    VPOS (pixcoords), distance
float getAdaptiveZ(inout float2 samplePos, float t) {
	float res = 0;
	const uint drops = 3;
	const float dropLength = 16.0;
	
	if (t < dropLength) {
		samplePos = snapVPOS(samplePos);
		res = ReShade::GetLinearizedDepth(samplePos * BUFFER_PIXEL_SIZE);
	}
	if (t >= dropLength && t < dropLength * 2.0 && drops > 0) {
		samplePos = snapVPOS2(samplePos);
		res = tex2Dfetch(sminZ, samplePos * 0.5).x;
	}
	if (t >= dropLength * 2.0 && t < dropLength * 4.0 && drops > 1) {
		samplePos = snapVPOS3(samplePos);
		res = tex2Dfetch(sminZ2, samplePos * 0.25).x;
	}
	if (t >= dropLength * 4.0 && drops > 2) {
		samplePos = snapVPOS4(samplePos);
		res = tex2Dfetch(sminZ3, samplePos * 0.125).x;
	}
	return res;
}

/*

  __  __       _          __                  _   _                 
 |  \/  |     (_)        / _|                | | (_)                
 | \  / | __ _ _ _ __   | |_ _   _ _ __   ___| |_ _  ___  _ __  ___ 
 | |\/| |/ _` | | '_ \  |  _| | | | '_ \ / __| __| |/ _ \| '_ \/ __|
 | |  | | (_| | | | | | | | | |_| | | | | (__| |_| | (_) | | | \__ \
 |_|  |_|\__,_|_|_| |_| |_|  \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
                                                                    
                                                                    

*/

// Inner (step) loop, sets the bitfield
uint sliceSteps(float3 positionVS, float3 V, float2 start, float2 rayDir, float t, float step, float samplingDirection, float N, uint bitfield) {
    for (uint i = 0; i < SCVBAO_STEPS; i++, t += step) {
        float2 samplePos = start + t * rayDir;
        samplePos = floor(samplePos) + 0.5;
        float2 samplePosUV = samplePos.xy / BUFFER_SCREEN_SIZE;
        
        float2 range = saturate(samplePosUV * samplePosUV - samplePosUV);
		bool is_outside = range.x != -range.y; //and of course if we are not inside we are outside. 	
    	if (is_outside) break;
        
        float depth = getAdaptiveZ(samplePos, t);
        float3 samplePosVS = zfw::uvzToView(samplePosUV, depth);
        float3 delta = samplePosVS - positionVS;
        float thicknessModifier = clamp(samplePosVS.z * 0.1, 0.5, 1.2);
	
	    float2 fb = acos(float2(dot(normalize(delta), V), dot(normalize(delta + THICKNESS * normalize(samplePosVS) * thicknessModifier), V)));
	    fb = saturate(((samplingDirection * -fb) - N + PI/2) / PI);
	    fb = fb.x > fb.y ? fb.yx : fb;
	    fb = smoothstep(0., 1., fb); // cosine lobe for AO. look: cdf.
	    
   	 uint a = ceil(fb.x * SECTORS);
    	uint b = floor((fb.y - fb.x) * SECTORS);
    	bitfield |= ((1 << b) - 1) << a;
    	t *= power;
    }
    return bitfield;
}

// Basic init for variables, outer (slice) loop
float gtao(float2 uv, float2 vpos) {
	float2 random = stbn(vpos);
	
	float2 start = vpos;
	float3 positionVS = zfw::uvToView(uv);
	

	float ao = 0.0;
	
	float3 V = normalize(-positionVS);
	float3 normalVS = zfw::getNormal(uv);
	positionVS += 0.002 * normalVS;
	
    float step = max(1.0, clamp(R / positionVS.z, SCVBAO_STEPS, R * 4) / (SCVBAO_STEPS + 1.0));
		
	for(float slice = 0.0; slice < 1.0; slice += 1.0 / SCVBAO_SLICES) {
		float phi = PI * frac(slice + random.x);
		float2 direction = float2(cos(phi), sin(phi));
		
		float3 directionF3 = float3(direction, 0.0);
		float3 oDirV = directionF3 - dot(directionF3, V) * V;
		float3 sliceN = cross(directionF3, V);
		float3 projN = normalVS - sliceN * dot(normalVS, sliceN);
		float cosN = saturate(dot(projN, V) / length(projN));
		float signN = -sign(dot(projN, oDirV));

		float N = signN * acos(cosN);
		
		uint aoBF = 0;
		float offset = max(random.y * step, length(BUFFER_PIXEL_SIZE));
		aoBF = sliceSteps(positionVS, V, start, direction, offset, step, 1, N, aoBF);
		aoBF = sliceSteps(positionVS, V, start, -direction, offset, step, -1, N, aoBF);

		ao += float(countbits(aoBF)) * length(projN);
	}
	ao = 1.0 - ao / (float(SECTORS) * SCVBAO_SLICES);
	return positionVS.z > FAR_CLIP || ao < -0.001 ? 1.0 : ao;
}

/*

  _____                        
 |  __ \                       
 | |__) |_ _ ___ ___  ___  ___ 
 |  ___/ _` / __/ __|/ _ \/ __|
 | |  | (_| \__ \__ \  __/\__ \
 |_|   \__,_|___/___/\___||___/
                               
                               

*/

// Gathers & linearizes source depth, writes to lower res tex
float prepMinZ __PXSDECL__ {
	float4 z4 = GatherLinDepth(uv, ReShade::DepthBuffer);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

// -||-
float prepMinZ2 __PXSDECL__ {
	float4 z4 = tex2DgatherR(sminZ, uv);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

// -||-
float prepMinZ3 __PXSDECL__ {
	float4 z4 = tex2DgatherR(sminZ2, uv);
	return min(min(z4.x, z4.y), min(z4.z, z4.w));
}

float4 main __PXSDECL__ {
	float ao = gtao(uv, vpos.xy);
	#if SCAO_USE_MV
		const float3 mv = zfw::getVelocity(uv);
		const float prevZ = tex2D(sprevD, uv + mv.xy).x;
		const float currZ = ReShade::GetLinearizedDepth(uv);
		const float deltaZ = prevZ - currZ;
		const float rejectZWeight = dot(deltaZ, deltaZ);
		
		
		ao = lerp(ao, tex2D(sAO3, uv + mv.xy).x, historySize * mv.z * (mv.z < 0.4 ? 0.0 : 1.0) * (rejectZWeight > 0.0001 ? 0.0 : 1.0));
	#endif
	return autoF4(ao);
}

// Writes to reuse next frame
float4 save __PXSDECL__ {
	return tex2Dfetch(sAO1, vpos.xy);
}

float4 denoiseMIN __PXSDECL__ {
	return autoF4(atrous_low(sAO1, uv, 0).xxx);
}

float4 denoiseFULL1 __PXSDECL__ {
	return autoF4(atrous(sAO1, uv, 0).xxx);
}

float4 denoiseFULL2 __PXSDECL__ {
	return autoF4(atrous(sAO2, uv, 0).xxx);
}

float4 upscale __PXSDECL__ {
	const float3 hdr = zfw::toneMapInverse(tex2Dfetch(ReShade::BackBuffer, vpos.xy).rgb, 15.0);
	#if SCAO_USE_MV
		if (debug) return tex2D(sAO2, uv).xxxx;
		float3 blended = tex2D(sAO2, uv).xxx * hdr;
	#endif
	#if !SCAO_USE_MV
		if (debug) return tex2D(sAO1, uv).xxxx;
		float3 blended = tex2D(sAO1, uv).xxx * hdr;
	#endif
	return autoF4(zfw::toneMap(lerp(hdr, blended, strength), 15.0));
}

float reprojD __PXSDECL__ {
	return tex2Dfetch(sminZ, vpos.xy).x;
}

technique SCAO {
	pass PrepZ {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ;
		RenderTarget = minZ;
	}
	pass Prepz2 {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ2;
		RenderTarget = minZ2;
	}
	pass Prepz3 {
		VertexShader = PostProcessVS;
		PixelShader = prepMinZ3;
		RenderTarget = minZ3;
	}
	pass Main { 
		VertexShader = PostProcessVS;
		PixelShader = main;
		RenderTarget = AO1;
	}
	#if SCAO_USE_MV
		pass Save {
			VertexShader = PostProcessVS;
			PixelShader = save;
			RenderTarget = AO3;
		}
		pass Denoise {
			VertexShader = PostProcessVS;
			PixelShader = denoiseMIN;
			RenderTarget = AO2;
		}
	#endif
	#if !SCAO_USE_MV
		pass DenoiseFULL1 {
			VertexShader = PostProcessVS;
			PixelShader = denoiseFULL1;
			RenderTarget = AO2;
		}
		pass DenoiseFULL2 {
			VertexShader = PostProcessVS;
			PixelShader = denoiseFULL2;
			RenderTarget = AO1;
		}
	#endif
	// probs gonna be a misnomer for a while.
	pass Upscale {
		VertexShader = PostProcessVS;
		PixelShader = upscale;
	}
	#if SCAO_USE_MV
		pass SaveZ {
			VertexShader = PostProcessVS;
			PixelShader = reprojD;
			RenderTarget = prevD;
		}
	#endif
}