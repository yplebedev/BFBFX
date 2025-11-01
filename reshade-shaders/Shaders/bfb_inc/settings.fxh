#pragma once

uniform float radius <ui_type = "slider"; ui_label = "Radius"; ui_tooltip = "Increases the effect scale"; ui_min = 30.0; ui_max = 2000.0;> = 2000.0;
uniform uint steps <ui_type = "slider"; ui_label = "Steps"; ui_min = 1u; ui_max = 32u;> = 7u;
uniform uint slices <ui_type = "slider"; ui_label = "Rays"; ui_min = 1u; ui_max = 8u;> = 1u;
uniform float thickness <ui_type = "slider"; ui_label = "Thickness"; ui_min = 2.0; ui_max = 16.0;> = 2.0;
uniform float strength <ui_type = "slider"; ui_label = "Strength"; ui_min = 0.1; ui_max = 5.0;> = 1.0;
uniform float tonemapWhite <ui_type = "slider"; ui_label = "Highlight Protection"; ui_min = 2.0; ui_max = 20.0;> = 5.0;