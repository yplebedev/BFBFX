# BFBFX

A collection of ReShade shaders. Features primarily depth-dependent stuff. Also gonna be the trash bin for my future shaders.


Disclamer: even though most of the code is mine, some lines/functions (as annotated with comments) come from:

Zenteon - https://www.zenteon.co/ - https://github.com/Zenteon

Marty McFly/Pascal Gilcher - https://www.martysmods.com - https://github.com/martymcmodding

# SCAO
A complete functional overhaul of SCAO V2. Same tech under the hood, but much higher quality result. By ~~ab~~using motion vectors from Framework it is competitive to shaders like MXAO, albeit with a higher base cost. Similarly to MXAO it has a ground-truth-matching result (result of Marty's Black Magic). Shares code with SCGI.

# SCGI
Also a rewrite of SCGI. Much sharper result, familiar performance target, quite possibly the best geometric detail preserving free GI shader of it's ms window. Provides sufficiently low noise levels and visible illumination at as little as one slice, one step. Runs GI at full-res, a feature unique to just a handful of shaders.
