package main

import "core:math"
import rl "vendor:raylib"
import game "game"

blood_splat :: proc(m: ^Mesh_Builder) {
	outline := [14]f32{0.7, 1.2, 0.8, 0.95, 0.65, 1.15, 0.9, 1.25, 0.6, 0.85, 1.1, 0.75, 1.2, 0.8}
	for radius, i in outline {
		next := (i+1)%len(outline)
		a, b := f32(i)*2*math.PI/f32(len(outline)), f32(next)*2*math.PI/f32(len(outline))
		p := game.Vec3{math.cos(a)*radius, 0, math.sin(a)*radius}
		q := game.Vec3{math.cos(b)*outline[next], 0, math.sin(b)*outline[next]}
		mesh_triangle(m, nil, {}, q, p, rl.WHITE, 0, 10)
	}
}

// Shared angular anatomy with a forward neck, pinched waist and uneven jaw.
// Geometry, cloth tears and veins are built once, then instanced in both passes.
Fairy_Ring :: struct { y, width, depth, x, z: f32 }

fairy_loft :: proc(m: ^Mesh_Builder, rings: []Fairy_Ring, color: rl.Color, surface: f32) {
 contour := [8]game.Vec2{{-1, -0.40}, {-0.55, -1}, {0.55, -1}, {1, -0.40}, {1, 0.55}, {0.50, 1}, {-0.50, 1}, {-1, 0.55}}
 for ring, i in rings {
  for corner, j in contour {
   next := contour[(j+1)%len(contour)]
   a := game.Vec3{ring.x+corner.x*ring.width, ring.y, ring.z+corner.y*ring.depth}
   b := game.Vec3{ring.x+next.x*ring.width, ring.y, ring.z+next.y*ring.depth}
   if i == 0 { mesh_triangle(m, nil, {ring.x, ring.y, ring.z}, a, b, color, surface, 10) }
   if i == len(rings)-1 { mesh_triangle(m, nil, {ring.x, ring.y, ring.z}, b, a, color, surface, 10)
   } else {
    upper := rings[i+1]
    c := game.Vec3{upper.x+next.x*upper.width, upper.y, upper.z+next.y*upper.depth}
    d := game.Vec3{upper.x+corner.x*upper.width, upper.y, upper.z+corner.y*upper.depth}
    mesh_quad(m, nil, a, d, c, b, color, surface, 10)
   }
  }
 }
}

fairy_sheet :: proc(m: ^Mesh_Builder, a, b, c: game.Vec3, color: rl.Color) {
 mesh_triangle(m, nil, a, b, c, color, SURFACE_CLOTH, 10)
 mesh_triangle(m, nil, a, c, b, color, SURFACE_CLOTH, 10)
}

fairy_limb :: proc(m: ^Mesh_Builder) {
 fairy_loft(m, []Fairy_Ring{{0, 0.66, 0.62, 0, 0}, {0.22, 1, 0.79, 0.04, 0.07}, {0.58, 0.73, 0.62, -0.04, 0}, {0.86, 0.44, 0.43, 0, 0}, {1, 0.58, 0.48, 0, 0}}, rl.WHITE, SURFACE_SKIN)
}

fairy_body :: proc(m: ^Mesh_Builder, hunter: bool) {
 skin := rl.Color{164, 153, 130, 255} if !hunter else rl.Color{163, 145, 150, 255}
 cloth := rl.Color{76, 37, 42, 255} if !hunter else rl.Color{55, 49, 70, 255}
 fairy_loft(m, []Fairy_Ring{{-0.29, 0.16, 0.11, 0, 0}, {-0.15, 0.17, 0.13, 0, 0.015}, {0.025, 0.10, 0.085, 0.02, 0.005}, {0.20, 0.21, 0.12, -0.015, 0}, {0.31, 0.27, 0.12, 0, 0.025}, {0.40, 0.12, 0.08, 0, 0}}, skin, SURFACE_SKIN)
 mesh_beam(m, {0, 0.31, 0}, {0, 0.51, -0.12}, 0.09, 0.058, skin, SURFACE_SKIN, 7)
 // A ragged collar and torn dress preserve the fairy silhouette. Long shreds
 // alternate with gaps; exposed bones belong to the body rather than a badge.
 for i in 0..<10 {
  a, b := f32(i)*2*math.PI/10, f32(i+1)*2*math.PI/10
  v0 := game.Vec3{math.cos(a)*0.17, -0.14, math.sin(a)*0.13}
  v1 := game.Vec3{math.cos(b)*0.17, -0.14, math.sin(b)*0.13}
  v2 := game.Vec3{math.cos(b)*0.24, -0.38-f32(i%3)*0.085, math.sin(b)*0.23}
  v3 := game.Vec3{math.cos(a)*0.28, -0.56+f32(i%2)*0.12, math.sin(a)*0.23}
  fairy_sheet(m, v0, v3, v1, cloth)
  if i%3 != 1 { fairy_sheet(m, v1, v3, v2, cloth) }
 }
 fairy_sheet(m, {-0.25, 0.31, -0.12}, {0.04, 0.13, -0.14}, {0.17, 0.30, -0.13}, cloth)
 fairy_sheet(m, {-0.26, 0.30, 0.10}, {-0.20, -0.18, 0.15}, {0.18, 0.24, 0.13}, cloth)
 for rib in 0..<4 {
  y := 0.055+f32(rib)*0.053
  width := 0.10+f32(rib)*0.018
  for side in ([2]f32{-1, 1}) {
   mesh_beam(m, {side*0.015, y+0.027, -0.128}, {side*width, y, -0.113}, 0.014, 0.020, {204, 187, 155, 255}, SURFACE_BONE, 5)
  }
 }
 for vertebra in 0..<5 {
  mesh_beam(m, {0, f32(vertebra)*0.067, 0.125}, {0.016, f32(vertebra)*0.067+0.035, 0.15}, 0.028, 0.022, {176, 158, 128, 255}, SURFACE_BONE, 5)
 }
}

fairy_head :: proc(m: ^Mesh_Builder) {
 skin := rl.Color{184, 171, 144, 255}
 // Long hollow cheeks, offset jaw, open eye sockets and a receding scalp.
 fairy_loft(m, []Fairy_Ring{{-0.24, 0.061, 0.057, 0.023, -0.040}, {-0.14, 0.112, 0.092, 0.013, -0.035}, {-0.025, 0.141, 0.11, 0, 0}, {0.10, 0.181, 0.13, -0.006, 0.007}, {0.23, 0.146, 0.12, 0, 0.022}, {0.285, 0.072, 0.077, 0.01, 0.025}}, skin, SURFACE_SKIN)
 for side in ([2]f32{-1, 1}) {
  // Sockets are angular recesses, not a flat black rectangle with huge eyes.
  a, b := game.Vec3{side*0.027, 0.070, -0.146}, game.Vec3{side*0.153, 0.113, -0.102}
  c, d := game.Vec3{side*0.133, -0.010, -0.132}, game.Vec3{side*0.049, -0.030, -0.148}
  fairy_sheet(m, a, b, c, {31, 24, 29, 255})
  fairy_sheet(m, a, c, d, {31, 24, 29, 255})
  enemy_box(m, {side*0.084, 0.034, -0.153}, {0.023, 0.029, 0.014}, {173, 50, 31, 255}, 0.003, SURFACE_LIGHT)
  mesh_beam(m, a+game.Vec3{0, 0.005, -0.008}, b, 0.024, 0.031, skin, SURFACE_SKIN, 5)
  mesh_beam(m, {side*0.12, -0.025, -0.13}, {side*0.063, -0.15, -0.10}, 0.028, 0.012, {139, 122, 112, 255}, SURFACE_SKIN, 5)
  mesh_beam(m, {side*0.16, 0.07, 0}, {side*0.285, 0.195, 0.063}, 0.049, 0.002, skin, SURFACE_SKIN, 5)
 }
 enemy_box(m, {0.012, -0.143, -0.122}, {0.137, 0.13, 0.041}, {41, 21, 27, 255}, 0.01, SURFACE_SKIN)
 for i in 0..<6 {
  x := f32(i)*0.022-0.043
  mesh_beam(m, {x, -0.091, -0.151}, {x+0.007, -0.14-f32(i%3)*0.022, -0.153}, 0.011, 0.002, {204, 188, 155, 255}, SURFACE_BONE, 4)
 }
 mesh_beam(m, {0, 0.065, -0.135}, {0.012, -0.068, -0.196}, 0.021, 0.012, skin, SURFACE_SKIN, 5)
 // Wet-looking black spikes made the old head read as a cartoon crown.
 // These flat, dry strands hang down one side, leaving the skull exposed.
 for i in 0..<7 {
  a := f32(i)*0.48-0.15
  p := game.Vec3{math.cos(a)*0.13, 0.225, math.sin(a)*0.11+0.02}
  q := game.Vec3{math.cos(a)*0.187, 0.047, math.sin(a)*0.148+0.04}
  end := q+game.Vec3{0.032, -0.26-f32(i%3)*0.047, 0.055}
  fairy_sheet(m, p-game.Vec3{0.026, 0, 0}, q, p+game.Vec3{0.026, 0, 0}, {53, 45, 45, 255})
  fairy_sheet(m, p+game.Vec3{0.026, 0, 0}, q, end, {63, 51, 48, 255})
 }
}

fairy_wing :: proc(m: ^Mesh_Builder) {
 outline := [12]game.Vec2{{0, 0}, {0.23, 0.28}, {0.76, 0.70}, {1.09, 0.68}, {0.92, 0.46}, {0.87, 0.52}, {0.72, 0.22}, {0.68, 0.29}, {0.52, 0.015}, {0.44, 0.10}, {0.26, -0.14}, {0.11, -0.04}}
 root := game.Vec3{0.17, 0.08, 0.015}
 for p, i in outline {
  q := outline[(i+1)%len(outline)]
  a, b := game.Vec3{p.x, p.y, 0}, game.Vec3{q.x, q.y, 0}
  color := rl.Color{126, 119, 92, 255} if i%3 != 0 else rl.Color{104, 104, 91, 255}
  if i == 2 || i == 6 || i == 8 {
   // Actual holes through the membrane, six triangles around each tear.
   center := (root+a+b)/3
   u, v, w := center+(root-center)*0.40, center+(a-center)*0.54, center+(b-center)*0.54
   fairy_sheet(m, root, a, v, color); fairy_sheet(m, root, v, u, color)
   fairy_sheet(m, a, b, w, color); fairy_sheet(m, a, w, v, color)
   fairy_sheet(m, b, root, u, color); fairy_sheet(m, b, u, w, color)
  } else { fairy_sheet(m, root, a, b, color) }
  mesh_beam(m, a, b, 0.009, 0.005, {66, 57, 47, 255}, SURFACE_BONE, 4)
  if i%2 == 0 {
   mesh_beam(m, root, a, 0.018, 0.004, {176, 148, 106, 255}, SURFACE_BONE, 4)
   mid := root+(a-root)*0.60
   mesh_beam(m, mid, b*0.83+root*0.17, 0.006, 0.002, {92, 73, 54, 255}, SURFACE_BONE, 4)
  }
 }
}

fairy_heart :: proc(m: ^Mesh_Builder) {
 fairy_loft(m, []Fairy_Ring{{-0.90, 0.09, 0.13, 0.20, 0}, {-0.43, 0.58, 0.50, 0.12, 0}, {0.20, 0.84, 0.62, -0.08, 0}, {0.60, 0.68, 0.53, -0.13, 0}, {0.77, 0.22, 0.22, -0.18, 0.01}}, {146, 66, 50, 255}, SURFACE_SKIN)
 for side in ([2]f32{-1, 1}) {
  mesh_beam(m, {side*0.28, 0.35, 0}, {side*0.36, 0.90, 0.12}, 0.16, 0.11, {85, 41, 37, 255}, SURFACE_SKIN, 6)
  mesh_beam(m, {side*0.66, 0.22, -0.38}, {side*0.27, -0.47, -0.37}, 0.035, 0.018, {184, 111, 82, 255}, SURFACE_SKIN, 5)
 }
}

draw_fairy :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	right, up, f := game.enemy_basis(e.facing)
	hunter := e.kind == .Interceptor
	dead := e.health <= 0
	charge := game.enemy_charge(e)
	tint := rl.WHITE if e.flash > 0 else rl.Color{230, 228, 210, 255}
	skin := rl.Color{168, 152, 128, 255} if !hunter else rl.Color{167, 147, 153, 255}
	p := e.position
	object_instance(r, .InterceptorHull if hunter else .SentryHull, p, right, up, -f, tint)
	// The head tilts independently; the fast hunter reaches with both claws.
	tilt := f32(0.13)+math.sin(time*3.5+p.x)*0.10
	if dead { tilt = 0.55 }
	object_instance(r, .FairyHead, p+up*0.58+f*0.08, right*math.cos(tilt)+up*math.sin(tilt), up*math.cos(tilt)-right*math.sin(tilt), -f, tint)
	for side in ([2]f32{-1, 1}) {
		flutter := math.sin(time*(29 if hunter else f32(24))+p.x)*0.68
		if dead { flutter = -0.85 }
		x := right*(side*math.cos(flutter))-f*math.sin(flutter)
		for lower in 0..<2 {
			size := f32(1) if lower == 0 else f32(0.72)
			object_instance(r, .EnemyFin, p+right*(side*0.13)+up*(0.25-f32(lower)*0.18)-f*0.15, x*size, up*(size if lower == 0 else -size), f*side, tint)
		}
		shoulder := p+up*0.28+right*(side*0.23)
		elbow := p+right*(side*(0.34+charge*0.09))-up*0.04+f*0.12
		hand := p+right*(side*0.24)+f*(0.60+charge*0.15)-up*(0.17 if !hunter else f32(0))
		if dead { hand = p+right*(side*0.53)-up*0.39 }
		model_beam(r, .FairyLimb, shoulder, elbow, 0.092, skin)
		model_beam(r, .FairyLimb, elbow, hand, 0.061, skin)
		for finger in 0..<3 {
			root := hand+right*(side*f32(finger-1)*0.045)
			end := root+f*(0.16+f32(finger%2)*0.05)-up*0.04
			model_beam(r, .Beam, root, end, 0.018, {194, 172, 140, 255}, SURFACE_BONE)
		}
		knee := p+right*(side*0.14)-up*0.61-f*(0.07+math.sin(time*5+side)*0.045)
		foot := p+right*(side*0.19)-up*0.91-f*0.20
		model_beam(r, .FairyLimb, p+right*(side*0.12)-up*0.24, knee, 0.082, skin)
		model_beam(r, .FairyLimb, knee, foot, 0.051, skin)
		model_beam(r, .Beam, foot, foot+f*0.18, 0.05, {54, 43, 43, 255})
	}
	if !dead {
		point, radius, exposed := game.enemy_model_weak_spot(e)
		pulse := radius*(1+charge*0.12)
		object_instance(r, .FairyHeart, point, right*pulse, up*pulse, -f*pulse, rl.WHITE, SURFACE_LIGHT if exposed else SURFACE_SKIN)
		if e.phase == .Windup { object_instance(r, .Ring, point, right*(0.4-charge*0.15), -f, up*(0.4-charge*0.15), RED) }
	}
}
