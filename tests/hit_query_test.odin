package tests

import "core:testing"
import game "../src/game"

@(test)
enemy_hit_bound_preserves_the_unpruned_query_for_every_kind_and_phase :: proc(t: ^testing.T) {
	rng := u32(0x9415326)
	hits: [game.Hit_Zone]int
	for kind in game.Enemy_Kind {
		for phase in game.Enemy_Phase {
			for sample in 0..<2048 {
				e := game.Enemy{health = 1, kind = kind, phase = phase, position = {230, 7, -440}, phase_time = game.random_stream(&rng)*game.enemy_windup(kind)}
				e.facing = game.forward(game.random_stream(&rng)*6.28, (game.random_stream(&rng)-0.5)*3.14)
				if sample%8 == 0 { e.facing = {} }
				if sample%7 == 0 { e.exposed = 1 }
				direction := game.forward(game.random_stream(&rng)*6.28, (game.random_stream(&rng)-0.5)*3.14)
				offset := game.Vec3{game.random_stream(&rng)-0.5, game.random_stream(&rng)-0.5, game.random_stream(&rng)-0.5}*4
				distance := game.random_stream(&rng)*150
				if sample%4 == 0 { distance = 0.2 }
				origin := e.position+offset-direction*distance
				limit := distance+4 if sample%3 != 0 else game.random_stream(&rng)*distance
				exact_distance, exact_zone := game.enemy_hit_exact(e, origin, direction, limit)
				actual_distance, actual_zone := game.enemy_hit(e, origin, direction, limit)
				hits[exact_zone] += 1
				if actual_zone != exact_zone || actual_distance != exact_distance {
					testing.expectf(t, false, "Culled hit: %v/%v sample %d, exact %v at %f, actual %v at %f", kind, phase, sample, exact_zone, exact_distance, actual_zone, actual_distance)
					return
				}
			}
		}
	}
	for zone in game.Hit_Zone { testing.expect(t, hits[zone] > 10, "Exercise misses, bodies, plate edges and exposed inserts") }
}
