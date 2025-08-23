// Reused code from UjelHDR

uniform float blur_size <ui_label = "Blur size"; ui_tooltip  = "Do not change unless you experience haloing.";> = 20.0;

texture inTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler inTexSam { Texture = inTex; };

float4 Downsample(sampler samp, float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
    float4 acc = tex2D(samp, xy) * 4.0;
    float2 o1 = BUFFER_PIXEL_SIZE * blur_size;
    float2 o2 = float2(o1.x, -o1.y);
    acc += tex2D(samp, xy - o1);
    acc += tex2D(samp, xy + o1);
    acc += tex2D(samp, xy + o2);
    acc += tex2D(samp, xy - o2);
    return acc / 8.0;
}

float4 Upsample(sampler samp, float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target 
{
    float xo = BUFFER_RCP_WIDTH * blur_size;
    float yo = BUFFER_RCP_HEIGHT * blur_size;
    float xo2 = xo * 2;
    float yo2 = yo * 2;
	float4 acc = 
		tex2D(samp, xy + float2(-xo, yo)) +
    	tex2D(samp, xy + float2(xo, yo)) +
		tex2D(samp, xy + float2(xo, -yo)) + 
    	tex2D(samp, xy + float2(-xo, -yo));
    acc *= 2;
    acc += tex2D(samp, xy + float2(-xo2, 0.0));
    acc += tex2D(samp, xy + float2(0.0, yo2));
    acc += tex2D(samp, xy + float2(xo2, 0.0));
    acc += tex2D(samp, xy + float2(0.0, -yo2));
    return acc / 12.0;
}


texture BTex0 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; };
texture BTex1 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture BTex2 { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F; };
texture BTex3 { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture BTex4 { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; };
texture BTex5 { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };

sampler BSam0 { Texture = BTex0; };
sampler BSam1 { Texture = BTex1; };
sampler BSam2 { Texture = BTex2; };
sampler BSam3 { Texture = BTex3; };
sampler BSam4 { Texture = BTex4; };
sampler BSam5 { Texture = BTex5; };

float4 DownSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Downsample(inTexSam, vpos, xy);
}

float4 DownSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Downsample(BSam4, vpos, xy);
}

float4 DownSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Downsample(BSam3, vpos, xy);
}

float4 DownSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Downsample(BSam2, vpos, xy);
}

float4 DownSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Downsample(BSam1, vpos, xy);
}


float4 UpSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Upsample(BSam0, vpos, xy);
}

float4 UpSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Upsample(BSam1, vpos, xy);
}

float4 UpSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Upsample(BSam2, vpos, xy);

}

float4 UpSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Upsample(BSam3, vpos, xy);
}

float4 UpSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	return Upsample(BSam4, vpos, xy);
}