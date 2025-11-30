#pragma once
// hey :)
// be VERY careful with these. I really, really advise you not to touch these.


uniform float radius <ui_type = "slider"; ui_label = "Radius"; ui_tooltip = "Increases the effect scale"; ui_min = 10.0; ui_max = 600.0;> = 400.0;
uniform bool distanceRadiusBoost <hidden = true; ui_type = "checkbox"; ui_label = "Decrease radius with distance";> = true;
uniform uint steps <ui_type = "slider"; ui_label = "Steps"; ui_min = 1u; ui_max = 32u;> = 7u;
uniform uint slices <ui_type = "slider"; ui_label = "Rays"; ui_min = 1u; ui_max = 8u;> = 1u;
uniform float thickness <ui_type = "slider"; ui_label = "Thickness"; ui_min = 2.0; ui_max = 16.0;> = 2.0;
uniform float strength <ui_type = "slider"; ui_label = "Strength"; ui_min = 0.1; ui_max = 5.0;> = 1.0;
uniform float tonemapWhite <ui_type = "slider"; ui_label = "Highlight Protection"; ui_min = 2.0; ui_max = 14.0;> = 2.0;
uniform bool debug <ui_label = "Debug View";> = false;