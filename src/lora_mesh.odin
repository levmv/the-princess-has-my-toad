package main

import rl "vendor:raylib"
import game "game"

// A separate authored contour mesh on the common 17-bone rig. Same physical
// capsule and weapon anchors: selecting a silhouette never changes aim/collision.
build_lora :: proc(m: ^Skin_Builder) {
 skin := rl.Color{207, 161, 119, 255}
 top := rl.Color{49, 142, 145, 255}
 cloth := rl.Color{72, 61, 52, 255}
 dark := rl.Color{31, 38, 44, 255}
 metal := rl.Color{152, 158, 142, 255}
 hair := rl.Color{77, 40, 26, 255}
 skin_loft(m, []Skin_Ring{{0.77, 0.18, 0.113, 0, 0, 0}, {0.86, 0.174, 0.10, 0, 0, 0}, {0.97, 0.117, 0.085, 0, 0, 0.15}, {1.09, 0.139, 0.096, 0, 0, 1}, {1.23, 0.193, 0.10, 0, 0, 1}, {1.30, 0.172, 0.086, 0, 0, 1}}, top, .Pelvis, .Chest, SURFACE_CLOTH)
 // Deliberately angular, covered bodice: four planes per pyramid, no spheres.
 for sign in ([2]f32{-1, 1}) {
  x := sign*0.096
  tip := game.Vec3{x, 1.17, -0.265}
  corners := [4]game.Vec3{{x-0.087, 1.09, -0.082}, {x+0.087, 1.09, -0.082}, {x+0.087, 1.247, -0.082}, {x-0.087, 1.247, -0.082}}
  for p, i in corners { skin_triangle(m, p, tip, corners[(i+1)%4], top, .Chest, .Chest, {}, SURFACE_CLOTH) }
 }
 skin_loft(m, []Skin_Ring{{0.73, 0.178, 0.116, 0, 0, 0}, {0.81, 0.186, 0.12, 0, 0, 0}, {0.88, 0.16, 0.112, 0, 0, 0}}, cloth, .Pelvis, .Pelvis, SURFACE_CLOTH)
 skin_box(m, {0, 0.883, 0}, {0.334, 0.05, 0.235}, dark, .Pelvis)
 skin_box(m, {0, 0.882, -0.126}, {0.065, 0.042, 0.02}, {211, 165, 68, 255}, .Pelvis)
 for side in 0..<2 {
  sign := f32(side*2-1)
  x := sign*0.125
  thigh := Hero_Bone.Thigh_L if side == 0 else Hero_Bone.Thigh_R
  shin := Hero_Bone.Shin_L if side == 0 else Hero_Bone.Shin_R
  foot := Hero_Bone.Foot_L if side == 0 else Hero_Bone.Foot_R
  skin_loft(m, []Skin_Ring{{0.43, 0.054, 0.062, x, 0, 1}, {0.50, 0.061, 0.065, x, 0, 0.25}, {0.67, 0.076, 0.083, x, 0, 0}, {0.78, 0.093, 0.093, x, 0, 0}, {0.84, 0.085, 0.085, x, 0, 0}}, skin, thigh, shin, SURFACE_SKIN)
  skin_box(m, {x+sign*0.065, 0.695, 0.018}, {0.07, 0.20, 0.085}, cloth, thigh, SURFACE_CLOTH)
  skin_loft(m, []Skin_Ring{{0.10, 0.048, 0.056, x, 0, 0.8}, {0.21, 0.06, 0.064, x, 0.008, 0}, {0.34, 0.063, 0.068, x, 0.014, 0}, {0.465, 0.054, 0.061, x, 0, 0}}, skin, shin, foot, SURFACE_SKIN)
  skin_loft(m, []Skin_Ring{{0.02, 0.068, 0.127, x, -0.048, 0}, {0.075, 0.073, 0.131, x, -0.048, 0}, {0.13, 0.058, 0.097, x, -0.025, 0}, {0.26, 0.062, 0.074, x, 0.008, 0}}, cloth, foot, foot, SURFACE_CLOTH)
  skin_box(m, {x, 0.028, -0.05}, {0.148, 0.034, 0.269}, dark, foot)
  for i in 0..<3 { skin_box(m, {x, 0.115+f32(i)*0.04, -0.071}, {0.078, 0.012, 0.01}, metal, foot, SURFACE_IRON) }
  arm := Hero_Bone.Arm_L if side == 0 else Hero_Bone.Arm_R
  forearm := Hero_Bone.Forearm_L if side == 0 else Hero_Bone.Forearm_R
  hand := Hero_Bone.Hand_L if side == 0 else Hero_Bone.Hand_R
  x = sign*0.27
  skin_loft(m, []Skin_Ring{{0.98, 0.044, 0.048, x, 0, 1}, {1.045, 0.049, 0.053, x, 0, 0.25}, {1.19, 0.061, 0.062, x, 0, 0}, {1.28, 0.066, 0.065, x, 0, 0}}, skin, arm, forearm, SURFACE_SKIN)
  skin_loft(m, []Skin_Ring{{0.77, 0.037, 0.044, x, 0, 1}, {0.83, 0.040, 0.049, x, 0, 0.2}, {0.93, 0.051, 0.054, x, 0, 0}, {1.012, 0.044, 0.048, x, 0, 0}}, skin, forearm, hand, SURFACE_SKIN)
  skin_box(m, {x, 0.828, 0}, {0.092, 0.087, 0.112}, dark, forearm)
  skin_box(m, {x, 0.745, -0.005}, {0.087, 0.11, 0.087}, dark, hand)
  skin_box(m, {sign*0.142, 1.23, 0.088}, {0.042, 0.20, 0.033}, cloth, .Chest, SURFACE_CLOTH)
 }
 skin_loft(m, []Skin_Ring{{1.30, 0.055, 0.055, 0, 0, 0}, {1.43, 0.059, 0.056, 0, 0, 1}}, skin, .Chest, .Head, SURFACE_SKIN)
 skin_loft(m, []Skin_Ring{{1.405, 0.05, 0.071, 0, -0.025, 0}, {1.45, 0.081, 0.088, 0, -0.015, 0}, {1.535, 0.099, 0.097, 0, 0, 0}, {1.59, 0.098, 0.088, 0, 0.006, 0}, {1.61, 0.084, 0.075, 0, 0.014, 0}}, skin, .Head, .Head, SURFACE_SKIN)
 skin_loft(m, []Skin_Ring{{1.575, 0.103, 0.097, 0, 0.012, 0}, {1.653, 0.096, 0.086, 0, 0.023, 0}, {1.665, 0.06, 0.06, 0, 0.022, 0}}, hair, .Head, .Head, SURFACE_CLOTH)
 // Side locks and a chunky off-centre braid remain clear of the wing pack.
 for sign in ([2]f32{-1, 1}) {
  skin_box(m, {sign*0.103, 1.526, 0.025}, {0.029, 0.137, 0.12}, hair, .Head, SURFACE_CLOTH)
  skin_box(m, {sign*0.046, 1.538, -0.096}, {0.050, 0.022, 0.016}, PAPER, .Head)
  skin_box(m, {sign*0.046, 1.537, -0.106}, {0.022, 0.019, 0.011}, dark, .Head)
  skin_box(m, {sign*0.047, 1.565, -0.094}, {0.052, 0.011, 0.018}, hair, .Head, SURFACE_CLOTH)
 }
 for i in 0..<5 {
  skin_box(m, {0.142+f32(i%2)*0.02, 1.535-f32(i)*0.076, 0.10+f32(i)*0.018}, {0.068-f32(i)*0.006, 0.082, 0.067}, hair, .Head, SURFACE_CLOTH)
 }
 skin_box(m, {0.145, 1.225, 0.177}, {0.043, 0.025, 0.042}, ORANGE, .Head)
 skin_triangle(m, {-0.019, 1.53, -0.102}, {0.019, 1.53, -0.102}, {0, 1.49, -0.135}, skin, .Head, .Head, {}, SURFACE_SKIN)
 skin_triangle(m, {-0.019, 1.53, -0.102}, {0, 1.49, -0.135}, {-0.018, 1.487, -0.102}, skin, .Head, .Head, {}, SURFACE_SKIN)
 skin_triangle(m, {0.019, 1.53, -0.102}, {0.018, 1.487, -0.102}, {0, 1.49, -0.135}, skin, .Head, .Head, {}, SURFACE_SKIN)
 skin_box(m, {0, 1.465, -0.108}, {0.055, 0.014, 0.011}, {133, 64, 51, 255}, .Head)
 build_hero_gear(m, metal, dark)
}
