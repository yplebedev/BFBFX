float3 lsrbg2xyz(float3 rgb) {
	float3x3 toXYZ = float3x3(
		float3(0.4124564, 0.3575761, 0.1804375),
		float3(0.2126729, 0.7151522, 0.0721750),
		float3(0.0193339, 0.1191920, 0.9503041)
	);
	
	return mul(toXYZ, rgb);
}

float3 xyz2lsrgb(float3 xyz) {
	float3x3 tosrgb = float3x3(
		float3( 3.24045,   -1.53714, -0.498532),
		float3(-0.969266,   1.87601,  0.0415561),
		float3( 0.0556434, -0.204026, 1.05723)
	);
	
	return mul(tosrgb, xyz);
}

float3 xyz2aces2065(float3 xyz) {
	float3x3 toACES2065_1 = float3x3(
		float3( 1.0498110175, 0.0000000000,-0.0000974845),
		float3(-0.4959030231, 1.3733130458, 0.0982400361),
		float3( 0.0000000000, 0.0000000000, 0.9912520182)
	);
	
	return mul(toACES2065_1, xyz);
}

float3 aces20652cg(float3 ACES2065_1) {
	float3x3 toACEScg = float3x3(
		float3( 1.4514393161,-0.2365107469,-0.2149285693),
		float3(-0.0765537734, 1.1762296998,-0.0996759264),
		float3( 0.0083161484,-0.0060324498, 0.9912520182)
	);
	
	return mul(toACEScg, ACES2065_1);
}

float3 cg2aces2065(float3 cg) {
	float3x3 to2065 = float3x3(
		float3( 0.695446,   0.140683,   0.164937 ),
		float3( 0.0447911,  0.859674,   0.0961568),
		float3(-0.00556189, 0.00405144, 1.00803  )
	);
	
	return mul(to2065, cg);
}

float3 aces20652xyz(float3 ACES2065_1) {
	float3x3 toxyz = float3x3(
		float3( 0.952552, 0.0,       0.0000936786),
		float3( 0.343966, 0.728166, -0.0721325),
		float3( 0.0,      0.0,       1.00883)
	);
	
	return mul(toxyz, ACES2065_1);
}

float3 xyz2cg(float3 xyz) {
	return aces20652cg(xyz2aces2065(xyz));
}

float3 cg2xyz(float3 cg) {
	return aces20652xyz(cg2aces2065(cg));
}