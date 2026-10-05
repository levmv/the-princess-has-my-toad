package main

// Shared with scene.fs. UV.x holds baked visibility; UV.y is a surface ID,
// including on authored moving meshes. Ordinary raylib UVs are reset on load.
SURFACE_PAINT :: f32(0)
SURFACE_STONE :: f32(1)
SURFACE_IRON :: f32(2)
SURFACE_LIGHT :: f32(3)
SURFACE_BOARD :: f32(4)
SURFACE_SKIN :: f32(5)
SURFACE_CLOTH :: f32(6)
SURFACE_BONE :: f32(7)
