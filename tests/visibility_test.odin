package tests

import "core:testing"
import game "../src/game"

@(test)
frustum_retains_intersecting_bounds :: proc(t: ^testing.T) {
	identity := (#row_major matrix[4, 4]f32)(1)
	testing.expect(t, game.bounds_visible({{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}}, identity))
	testing.expect(t, game.bounds_visible({{-2, -2, -2}, {2, 2, 2}}, identity))
	for axis in 0..<3 {
		for side in 0..<2 {
			center: game.Vec3
			center[axis] = f32(side*2-1)*2
			testing.expect(t, !game.bounds_visible({center-game.Vec3{0.2, 0.2, 0.2}, center+game.Vec3{0.2, 0.2, 0.2}}, identity))
			center[axis] *= 0.55
			testing.expect(t, game.bounds_visible({center-game.Vec3{0.2, 0.2, 0.2}, center+game.Vec3{0.2, 0.2, 0.2}}, identity))
		}
	}
}
