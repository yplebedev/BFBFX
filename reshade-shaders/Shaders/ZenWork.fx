// ORIGINAL VERSION HERE: https://github.com/Zenteon/ZenteonFX/tree/main
//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2025
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Zenteon: Framework - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
/*
	This is a MODIFIED/REWRITTEN version of Framework, which has been created by me (https://github.com/yplebedev).
	I have been explicitly given the right by the original author to create and distribute the following shader.
	This means, *you* specifically, probably have zero legal right to modify this (or the original) file yourself.

*/
//========================================================================
#include "OpenRSF.fxh"


#include "motion.fxh"
void copyToORSF(PS_INPUTS, out float4 mv : SV_Target0) {
	mv.rg = tex2D(sMV, xy).rg;
	mv.b = tex2D(sDOC, xy).r;
}

#include "normals.fxh"
#include "ZenteonCommon.fxh"
#include "albedo.fxh"

void depth(PS_INPUTS, out float z : SV_Target0) {
	z = ReShade::GetLinearizedDepth(xy);
}

void copy_geo(PS_INPUTS, out float2 normals : SV_Target0) {
	normals = OCTtoUV(tex2Dfetch(sTempN0, vpos.xy).xyz);
}

void copy_smooth(PS_INPUTS, out float2 normals : SV_Target0) {
	normals = OCTtoUV(tex2Dfetch(sHN1, vpos.xy * 0.5).xyz);
}

technique ZenWork<ui_label = "BFB: ZenWork";> {
	// Zenteon: Motion MVs; slower, much higher quality
	pass {	PASS1(Gauss0PS, tCG0); }
	pass {	PASS1(Gauss1PS, tCG1); }
	pass {	PASS1(Gauss2PS, tCG2); }
	pass {	PASS1(Gauss3PS, tCG3); }
	pass {	PASS1(Gauss4PS, tCG4); }
	pass {	PASS1(Gauss5PS, tCG5); }

	pass {	PASS1(DD0PS, tLD0); }
	pass {	PASS1(DD1PS, tLD1); }
	pass {	PASS1(DD2PS, tLD2); }
	pass {	PASS1(DD3PS, tLD3); }
	
	pass {	PASS1(Level5PS, tLevel5); }
	pass {	PASS1(Level4PS, tLevel4); }
	pass {	PASS1(Level3PS, tLevel3); }
	pass {	PASS1(Level2PS, tLevel2); }
	pass {	PASS1(Level1PS, tLevel1); }
	pass {	PASS1(Level0PS, tLevel0); }	
	
	pass {	PASS1(Flood0PS, tTemp1); }
	pass {	PASS1(Flood1PS, tTemp0); }	
	pass {	PASS1(Flood2PS, tTemp1); }	
	pass {	PASS1(Flood3PS, tTemp0); }	
	
	pass {	PASS1(UpscaleMVI0, tQuar); }	
	pass {	PASS1(UpscaleMVI, tHalf); }	
	pass {	PASS1(UpscaleMV, tFull); }	
	
	pass {	PASS2(SavePS, texMotionVectors, tDOC); }

	pass {	PASS1(CopyColPS, tPreFrm); }	
	pass {	PASS1(Copy0PS, tPG0); }	
	pass {	PASS1(Copy1PS, tPG1); }
	pass {	PASS1(Copy2PS, tPG2); }
	pass {	PASS1(Copy3PS, tPG3); }
	pass {	PASS1(Copy4PS, tPG4); }
	pass {	PASS1(Copy5PS, tPG5); }
	
	pass CopyToORSF{	PASS1(copyToORSF, ORSFShared::tMotion); }
	
	// Framework
	pass {	PASS1(GenNormalsPS, tTempN0); }
	pass {	PASS1(copy_geo, ORSFShared::tGeoN); }
	pass {	PASS1(SmoothNormals0PS, tHN0); }
	pass {	PASS1(SmoothNormals1PS, tHN1); }
	pass {	PASS1(SmoothNormals2PS, tHN0); }
	pass {	PASS1(SmoothNormals3PS, tHN1); }
	pass {	PASS1(copy_smooth, ORSFShared::tSmoothN); }
	
	pass {	PASS1(TexNormalsPS, ORSFShared::tTexN); }
	// Albedo
	pass {	PASS1(prep_luma, tSource); }
	pass {	PASS1(blur_down0, tBlur1); }
	pass {	PASS1(blur_down1, tBlur2); }
	pass {	PASS1(blur_down2, tBlur3); }
	pass {	PASS1(blur_down3, tBlur4); }
	pass {	PASS1(blur_down4, tBlur5); }
	pass {	PASS1(blur_up0, tBlur4); }
	pass {	PASS1(blur_up1, tBlur3); }
	pass {	PASS1(blur_up2, tBlur2); }
	pass {	PASS1(blur_up3, tBlur1); }
	pass {	PASS1(blur_up4, tFinalBlurred); }
	pass {	PASS1(albedo, ORSFShared::tAlbedo); }
	
	// Depth
	pass {	PASS1(depth, ORSFShared::tDepth); }
}