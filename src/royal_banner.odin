package main

import "core:math"
import rl "vendor:raylib"
import game "game"

// Screen-printed polygon art, baked once into the ordinary world chunks.
// No texture atlas, new draw pass, frame allocation or language-dependent UI.
banner_polygon :: proc(m: ^Mesh_Builder, b: game.Royal_Banner, points: []game.Vec2, color: rl.Color, layer: f32) {
	up := game.Vec3{0, 1, 0}
	normal := game.cross(b.right, up)
	vertices: [32]game.Vec3
	assert(len(points) >= 3 && len(points) <= len(vertices))
	area := f32(0)
	for p, i in points {
		q := points[(i+1)%len(points)]
		area += p.x*q.y-p.y*q.x
		vertices[i] = b.base+b.right*(p.x*b.width)+up*(p.y*b.height)+normal*(0.02+layer*0.008)
	}
	for i in 1..<len(points)-1 {
		// The authored outline must be visible from its first vertex. This
		// also permits notched silhouettes without triangles outside the print.
		a, c := points[i]-points[0], points[i+1]-points[0]
		assert((a.x*c.y-a.y*c.x)*area >= -0.00000001, "Banner outline needs a different fan origin")
		left, right := i, i+1
		if area < 0 { left, right = right, left }
		mesh_triangle(m, nil, vertices[0], vertices[left], vertices[right], color, SURFACE_CLOTH, 3)
	}
}

banner_stroke :: proc(m: ^Mesh_Builder, b: game.Royal_Banner, from, to: game.Vec2, width: f32, color: rl.Color, layer: f32) {
	d := to-from
	length := math.sqrt(d.x*d.x+d.y*d.y)
	n := game.Vec2{-d.y, d.x}*(width/length)
	banner_polygon(m, b, []game.Vec2{from-n, to-n, to+n, from+n}, color, layer)
}

bake_royal_banner :: proc(m: ^Mesh_Builder, s: game.Section_Recipe) {
	b, ok := game.ram_royal_banner(s)
	if !ok { return }
	ink, paper := rl.Color{34, 29, 39, 255}, rl.Color{221, 198, 158, 255}
	gold, red := rl.Color{177, 127, 58, 255}, rl.Color{141, 39, 54, 255}
	banner_polygon(m, b, []game.Vec2{{-0.5, 0}, {0.5, 0}, {0.5, 1}, {-0.5, 1}}, red, 0)
	for side in ([2]f32{-1, 1}) {
		banner_stroke(m, b, {side*0.46, 0.025}, {side*0.46, 0.98}, 0.008, gold, 1)
		// Radiating wedges, faded into the burgundy field.
		for i in 0..<4 {
			y := 0.16+f32(i)*0.19
			banner_polygon(m, b, []game.Vec2{{0, 0.58}, {side*0.44, y}, {side*0.44, y+0.055}}, {160, 59, 59, 255}, 1)
		}
	}
	halo: [24]game.Vec2
	for &p, i in halo { a := f32(i)*2*math.PI/f32(len(halo)); p = {math.cos(a)*0.34, 0.65+math.sin(a)*0.245} }
	banner_polygon(m, b, halo[:], gold, 2)
	// The cloak occupies almost the full width: an imposing bust, not a mascot.
	banner_polygon(m, b, []game.Vec2{{-0.42, 0.11}, {0.42, 0.11}, {0.40, 0.28}, {0.20, 0.42}, {-0.18, 0.43}, {-0.40, 0.28}}, ink, 3)
	banner_polygon(m, b, []game.Vec2{{-0.03, 0.12}, {0.28, 0.12}, {0.22, 0.32}, {0.04, 0.41}}, {78, 46, 75, 255}, 4)
	// Tall, severe collar and a golden chain disappearing into the cloak.
	for side in ([2]f32{-1, 1}) {
		banner_polygon(m, b, []game.Vec2{{side*0.05, 0.30}, {side*0.29, 0.47}, {side*0.17, 0.36}}, paper, 4)
		banner_stroke(m, b, {side*0.22, 0.30}, {side*0.13, 0.20}, 0.007, gold, 5)
	}
	banner_polygon(m, b, []game.Vec2{{-0.255, 0.42}, {0.245, 0.42}, {0.26, 0.67}, {0.16, 0.80}, {-0.16, 0.80}, {-0.27, 0.67}}, ink, 5)
	banner_polygon(m, b, []game.Vec2{{-0.15, 0.69}, {-0.17, 0.58}, {-0.10, 0.47}, {0.015, 0.425}, {0.13, 0.485}, {0.18, 0.61}, {0.12, 0.715}, {-0.07, 0.745}}, paper, 6)
	// Asymmetric print shadow makes the face angular and openly malicious.
	banner_polygon(m, b, []game.Vec2{{0.045, 0.54}, {0.06, 0.71}, {0.18, 0.61}, {0.13, 0.485}, {0.015, 0.425}}, {164, 127, 104, 255}, 7)
	banner_polygon(m, b, []game.Vec2{{-0.015, 0.715}, {-0.18, 0.70}, {-0.08, 0.765}, {0.14, 0.725}, {0.055, 0.67}}, {117, 77, 45, 255}, 8)
	for side in ([2]f32{-1, 1}) {
		banner_polygon(m, b, []game.Vec2{{side*0.025, 0.605}, {side*0.142, 0.643}, {side*0.135, 0.593}, {side*0.07, 0.59}}, ink, 9)
		banner_stroke(m, b, {side*0.057, 0.61}, {side*0.119, 0.623}, 0.006, paper, 10)
		banner_stroke(m, b, {side*0.038, 0.628}, {side*0.151, 0.674}, 0.012, ink, 10)
	}
	banner_polygon(m, b, []game.Vec2{{0, 0.625}, {-0.035, 0.535}, {0.04, 0.55}}, {169, 131, 99, 255}, 10)
	banner_stroke(m, b, {-0.083, 0.505}, {0.027, 0.48}, 0.007, ink, 10)
	banner_stroke(m, b, {0.027, 0.48}, {0.105, 0.526}, 0.007, ink, 10)
	// Five uneven crown points and a single red stone.
	banner_polygon(m, b, []game.Vec2{{-0.22, 0.75}, {0.21, 0.75}, {0.23, 0.80}, {-0.23, 0.80}}, gold, 11)
	for i in 0..<5 {
		x := f32(i-2)*0.09
		banner_polygon(m, b, []game.Vec2{{x-0.047, 0.785}, {x+0.047, 0.785}, {x+0.013, 0.94-abs(f32(i-2))*0.036}}, paper, 12)
	}
	banner_polygon(m, b, []game.Vec2{{0, 0.754}, {0.029, 0.786}, {0, 0.813}, {-0.029, 0.786}}, red, 13)
	// Her heraldic emblem is a frog in a cage. No explanatory slogan is needed.
	banner_polygon(m, b, []game.Vec2{{-0.11, 0.105}, {0.11, 0.105}, {0.13, 0.18}, {0, 0.245}, {-0.13, 0.18}}, gold, 6)
	banner_polygon(m, b, []game.Vec2{{-0.07, 0.13}, {0.07, 0.13}, {0.075, 0.16}, {0.045, 0.195}, {0, 0.18}, {-0.045, 0.195}, {-0.075, 0.16}}, {66, 81, 59, 255}, 7)
	for i in 0..<5 { x := f32(i-2)*0.033; banner_stroke(m, b, {x, 0.114}, {x, 0.204-abs(x)*0.45}, 0.003, ink, 8) }
	// Torn print at the hem and small rubbed patches, deterministic for both copies.
	for i in 0..<13 {
		x := -0.43+f32(i)*0.066
		banner_polygon(m, b, []game.Vec2{{x, 0.012}, {x+0.024, 0.012}, {x+0.017, 0.028+f32(i%3)*0.008}}, {164, 144, 111, 255}, 14)
	}
}
