package main

import gl "graphics"
import rl "vendor:raylib"
import game "game"

Hero_Bone :: enum { Pelvis, Chest, Head, Thigh_L, Shin_L, Foot_L, Thigh_R, Shin_R, Foot_R, Arm_L, Forearm_L, Hand_L, Arm_R, Forearm_R, Hand_R, Gun, Pack }
HERO_BIND :: [17]game.Vec3{
	{0, 0.84, 0}, {0, 1.10, 0}, {0, 1.41, 0},
	{-0.125, 0.84, 0}, {-0.125, 0.46, 0}, {-0.125, 0.10, 0},
	{0.125, 0.84, 0}, {0.125, 0.46, 0}, {0.125, 0.10, 0},
	{-0.27, 1.26, 0}, {-0.27, 1.00, 0}, {-0.27, 0.78, 0},
	{0.27, 1.26, 0}, {0.27, 1.00, 0}, {0.27, 0.78, 0},
	{}, {0, 1.10, 0.15},
}
Hero_GPU :: struct { mesh: rl.Mesh, weights_buffer: u32 }
Hero_Renderer :: struct {
	models: [game.Character]Hero_GPU,
	character: game.Character,
	bones: [Hero_Bone][4][4]f32,
	skin_location, bones_location: [2]i32,
	flash_location: i32,
	flash: f32,
	visible, active: bool,
}
Skin_Builder :: struct { mesh: Mesh_Builder, weights: [dynamic][4]f32 }
Skin_Ring :: struct { y, width, depth, x, z, blend: f32 }

skin_triangle :: proc(m: ^Skin_Builder, a, b, c: game.Vec3, color: rl.Color, first, second: Hero_Bone, blend: [3]f32, surface: f32 = SURFACE_PAINT) {
	normal := game.normalized(game.cross(b-a, c-a))
	if game.length(normal) < 0.5 { return }
	for p, i in ([3]game.Vec3{a, b, c}) {
		append(&m.mesh.positions, p)
		append(&m.mesh.normals, normal)
		append(&m.mesh.uv, game.Vec2{1, surface})
		append(&m.mesh.colors, color)
		append(&m.weights, [4]f32{f32(first), f32(second), 1-blend[i], blend[i]})
	}
}

// Authored chamfered contours give clothing, muscle, jaw and boots their own
// silhouettes. Adjacent rings share skin weights across a bending joint.
skin_loft :: proc(m: ^Skin_Builder, rings: []Skin_Ring, color: rl.Color, first: Hero_Bone, second: Hero_Bone, surface: f32 = SURFACE_PAINT) {
	contour := [8]game.Vec2{{-1, -0.55}, {-0.55, -1}, {0.55, -1}, {1, -0.55}, {1, 0.55}, {0.55, 1}, {-0.55, 1}, {-1, 0.55}}
	for ring, i in rings {
		for corner, j in contour {
			next := contour[(j+1)%len(contour)]
			a := game.Vec3{ring.x+corner.x*ring.width, ring.y, ring.z+corner.y*ring.depth}
			b := game.Vec3{ring.x+next.x*ring.width, ring.y, ring.z+next.y*ring.depth}
			if i == 0 { skin_triangle(m, {ring.x, ring.y, ring.z}, a, b, color, first, second, {ring.blend, ring.blend, ring.blend}, surface) }
			if i == len(rings)-1 {
				skin_triangle(m, {ring.x, ring.y, ring.z}, b, a, color, first, second, {ring.blend, ring.blend, ring.blend}, surface)
			} else {
				upper := rings[i+1]
				c := game.Vec3{upper.x+next.x*upper.width, upper.y, upper.z+next.y*upper.depth}
				d := game.Vec3{upper.x+corner.x*upper.width, upper.y, upper.z+corner.y*upper.depth}
				skin_triangle(m, a, d, c, color, first, second, {ring.blend, upper.blend, upper.blend}, surface)
				skin_triangle(m, a, c, b, color, first, second, {ring.blend, upper.blend, ring.blend}, surface)
			}
		}
	}
}

skin_box :: proc(m: ^Skin_Builder, center, size: game.Vec3, color: rl.Color, bone: Hero_Bone, surface: f32 = SURFACE_PAINT) {
	skin_loft(m, []Skin_Ring{
		{center.y-size.y*0.5, size.x*0.5, size.z*0.5, center.x, center.z, 0},
		{center.y+size.y*0.5, size.x*0.5, size.z*0.5, center.x, center.z, 0},
	}, color, bone, bone, surface)
}

build_hero :: proc(m: ^Skin_Builder) {
	cloth := rl.Color{50, 65, 72, 255}
	armor := rl.Color{118, 130, 126, 255}
	shirt := rl.Color{146, 66, 46, 255}
	skin := rl.Color{195, 153, 117, 255}
	dark := rl.Color{30, 37, 39, 255}
	// Waist, ribcage and shoulders, with a soft skin transition at the spine.
	skin_loft(m, []Skin_Ring{{0.78, 0.16, 0.108, 0, 0, 0}, {0.88, 0.155, 0.104, 0, 0, 0}, {0.98, 0.13, 0.095, 0, 0, 0.2}, {1.11, 0.18, 0.115, 0, 0, 1}, {1.25, 0.235, 0.13, 0, -0.006, 1}, {1.32, 0.20, 0.095, 0, 0, 1}}, shirt, .Pelvis, .Chest, SURFACE_CLOTH)
	skin_box(m, {0, 0.875, 0}, {0.34, 0.065, 0.235}, dark, .Pelvis)
	skin_box(m, {0, 0.875, -0.128}, {0.075, 0.056, 0.025}, armor, .Pelvis, SURFACE_IRON)
	for side in 0..<2 {
		sign := f32(side*2-1)
		x := sign*0.125
		thigh := Hero_Bone.Thigh_L if side == 0 else Hero_Bone.Thigh_R
		shin := Hero_Bone.Shin_L if side == 0 else Hero_Bone.Shin_R
		foot := Hero_Bone.Foot_L if side == 0 else Hero_Bone.Foot_R
		skin_loft(m, []Skin_Ring{{0.43, 0.066, 0.071, x, -0.004, 1}, {0.49, 0.073, 0.079, x, -0.006, 0.5}, {0.62, 0.094, 0.094, x, 0, 0}, {0.79, 0.101, 0.106, x, 0, 0}, {0.85, 0.083, 0.083, x, 0, 0}}, cloth, thigh, shin, SURFACE_CLOTH)
		skin_loft(m, []Skin_Ring{{0.10, 0.053, 0.06, x, 0, 0.8}, {0.20, 0.065, 0.069, x, 0.008, 0}, {0.35, 0.077, 0.08, x, 0.014, 0}, {0.47, 0.066, 0.07, x, 0, 0}}, cloth, shin, foot, SURFACE_CLOTH)
		skin_box(m, {x, 0.46, -0.065}, {0.14, 0.14, 0.073}, armor, shin, SURFACE_IRON)
		skin_loft(m, []Skin_Ring{{0.02, 0.078, 0.137, x, -0.055, 0}, {0.065, 0.08, 0.14, x, -0.055, 0}, {0.13, 0.067, 0.11, x, -0.036, 0}, {0.21, 0.055, 0.068, x, 0.004, 0}}, dark, foot, foot)
		skin_box(m, {x, 0.027, -0.055}, {0.16, 0.034, 0.28}, armor, foot, SURFACE_IRON)
		arm := Hero_Bone.Arm_L if side == 0 else Hero_Bone.Arm_R
		forearm := Hero_Bone.Forearm_L if side == 0 else Hero_Bone.Forearm_R
		hand := Hero_Bone.Hand_L if side == 0 else Hero_Bone.Hand_R
		x = sign*0.27
		skin_loft(m, []Skin_Ring{{0.98, 0.053, 0.056, x, 0, 1}, {1.04, 0.063, 0.062, x, 0, 0.25}, {1.17, 0.075, 0.077, x, 0, 0}, {1.28, 0.09, 0.086, x, 0, 0}, {1.31, 0.069, 0.065, x, 0, 0}}, skin, arm, forearm, SURFACE_SKIN)
		skin_loft(m, []Skin_Ring{{0.77, 0.043, 0.05, x, 0, 1}, {0.82, 0.046, 0.055, x, 0, 0.2}, {0.92, 0.069, 0.066, x, 0, 0}, {1.015, 0.052, 0.057, x, 0, 0}}, skin, forearm, hand, SURFACE_SKIN)
		skin_box(m, {x, 0.845, 0}, {0.107, 0.075, 0.125}, dark, forearm)
		skin_box(m, {x, 0.745, -0.005}, {0.104, 0.117, 0.096}, dark, hand)
		skin_box(m, {sign*0.17, 1.19, -0.119}, {0.044, 0.27, 0.024}, dark, .Chest)
	}
	// Neck, jaw, brow, flat-top hair, glasses and a small nose; no sphere head.
	skin_loft(m, []Skin_Ring{{1.30, 0.07, 0.063, 0, 0, 0}, {1.43, 0.074, 0.066, 0, 0, 1}}, skin, .Chest, .Head, SURFACE_SKIN)
	// The scalp ends inside the hair volume. Keeping both top caps at the
	// same height causes visible z-fighting from the elevated chase camera.
	skin_loft(m, []Skin_Ring{{1.40, 0.064, 0.078, 0, -0.022, 0}, {1.45, 0.104, 0.093, 0, -0.014, 0}, {1.54, 0.117, 0.105, 0, 0, 0}, {1.585, 0.109, 0.10, 0, 0.005, 0}, {1.60, 0.098, 0.089, 0, 0.007, 0}}, skin, .Head, .Head, SURFACE_SKIN)
	skin_loft(m, []Skin_Ring{{1.585, 0.114, 0.106, 0, 0.007, 0}, {1.65, 0.102, 0.094, 0, 0.01, 0}}, {74, 56, 35, 255}, .Head, .Head)
	skin_box(m, {0, 1.553, -0.105}, {0.207, 0.034, 0.025}, dark, .Head)
	for sign in ([2]f32{-1, 1}) { skin_box(m, {sign*0.119, 1.532, 0.003}, {0.028, 0.061, 0.043}, skin, .Head, SURFACE_SKIN) }
	skin_triangle(m, {-0.022, 1.54, -0.108}, {0.022, 1.54, -0.108}, {0, 1.485, -0.151}, skin, .Head, .Head, {}, SURFACE_SKIN)
	skin_triangle(m, {-0.022, 1.54, -0.108}, {0, 1.485, -0.151}, {-0.023, 1.484, -0.109}, skin, .Head, .Head, {}, SURFACE_SKIN)
	skin_triangle(m, {0.022, 1.54, -0.108}, {0.023, 1.484, -0.109}, {0, 1.485, -0.151}, skin, .Head, .Head, {}, SURFACE_SKIN)
	skin_box(m, {0, 1.468, -0.111}, {0.067, 0.008, 0.011}, {95, 66, 52, 255}, .Head)
	build_hero_gear(m, armor, dark)
}

build_hero_gear :: proc(m: ^Skin_Builder, armor, dark: rl.Color) {
	// Compact wing pack with cooling fins; the silhouette matters from behind.
	skin_loft(m, []Skin_Ring{{0.99, 0.10, 0.045, 0, 0.155, 0}, {1.04, 0.125, 0.06, 0, 0.17, 0}, {1.24, 0.125, 0.06, 0, 0.17, 0}, {1.28, 0.095, 0.043, 0, 0.16, 0}}, armor, .Pack, .Pack, SURFACE_IRON)
	for i in 0..<3 { skin_box(m, {0, 1.07+f32(i)*0.048, 0.234}, {0.17, 0.016, 0.012}, dark, .Pack) }
	skin_box(m, {0, 1.238, 0.233}, {0.13, 0.017, 0.016}, ORANGE, .Pack, SURFACE_LIGHT)
	// Weapon vertices are local to a separate aiming bone; muzzle is z = -0.24.
	skin_box(m, {0, 0, 0.045}, {0.115, 0.12, 0.37}, dark, .Gun)
	skin_box(m, {0, -0.11, 0.11}, {0.064, 0.16, 0.095}, dark, .Gun)
	skin_box(m, {0, 0.006, -0.18}, {0.067, 0.069, 0.12}, armor, .Gun, SURFACE_IRON)
	skin_box(m, {0, 0.075, -0.08}, {0.036, 0.036, 0.052}, dark, .Gun)
	for i in 0..<4 { skin_box(m, {0.061, 0.01, -0.03+f32(i)*0.038}, {0.012, 0.042, 0.016}, armor, .Gun, SURFACE_IRON) }
}

hero_init :: proc(r: ^Renderer) {
	h := &r.hero
 for character in game.Character {
  model := &h.models[character]
  m: Skin_Builder
  if character == .Duke { build_hero(&m) } else { build_lora(&m) }
  assert(len(m.weights) == len(m.mesh.positions))
  model.mesh = mesh_upload(&m.mesh)
  gl.GenBuffers(1, &model.weights_buffer)
  gl.BindVertexArray(model.mesh.vaoId)
  gl.BindBuffer(gl.ARRAY_BUFFER, model.weights_buffer)
  gl.BufferData(gl.ARRAY_BUFFER, len(m.weights)*size_of([4]f32), raw_data(m.weights), gl.STATIC_DRAW)
  gl.EnableVertexAttribArray(12)
  gl.VertexAttribPointer(12, 4, gl.FLOAT, false, 16, 0)
  gl.BindVertexArray(0)
  gl.BindBuffer(gl.ARRAY_BUFFER, 0)
  mesh_destroy_builder(&m.mesh)
  delete(m.weights)
 }
	for shader, i in ([2]rl.Shader{r.scene, r.depth}) {
		h.skin_location[i] = rl.GetShaderLocation(shader, "skinned")
		h.bones_location[i] = rl.GetShaderLocation(shader, "bones[0]")
		assert(h.skin_location[i] >= 0 && h.bones_location[i] >= 0)
	}
	h.flash_location = rl.GetShaderLocation(r.scene, "skinFlash")
	assert(h.flash_location >= 0)
}

hero_destroy :: proc(r: ^Renderer) {
	for &model in r.hero.models {
		rl.UnloadMesh(model.mesh)
		gl.DeleteBuffers(1, &model.weights_buffer)
	}
}
