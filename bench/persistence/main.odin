package main

import "core:fmt"
import "core:os"
import game "../../src/game"
import storage "../../src/storage"

main :: proc() {
	assert(len(os.args) == 3, "persistence-test write|read|inspect|death temporary-directory")
	w: game.World
	game.world_init_ram(&w, 10831)
	defer game.world_destroy(&w)
	g := game.State{world = &w, difficulty = .Nightmare, hero = .Lora}
	game.init(&g)
	s: storage.Store
	storage.init(&s, os.args[2])
	defer storage.destroy(&s)
	if os.args[1] == "inspect" {
		data: game.Save_Data
		assert(storage.read_save(s.paths[.Quick], &data).kind == .None)
		r := &data.live.state
		fmt.print("{")
		fmt.printf("\"time\":%.7f,\"health\":%.3f,\"position\":[%.6f,%.6f,%.6f],\"focused\":%t,\"shots\":%d,\"seed\":%d", r.time, r.player.health, r.player.position.x, r.player.position.y, r.player.position.z, r.focused, r.shot_sequence, data.seed)
		fmt.printf(",\"anvil\":%d,\"anvil_timer\":%.5f,\"anvil_target\":[%.5f,%.5f,%.5f],\"boss_health\":%d", int(r.anvil.phase), r.anvil.timer, r.anvil.target.x, r.anvil.target.y, r.anvil.target.z, r.boss.health)
		fmt.printf(",\"hero\":%d,\"deaths\":%d}\n", int(r.hero), r.deaths)
	} else if os.args[1] == "death" {
        // A controlled delayed hit in the arrival room. The normal game opens
        // its death UI; this fixture needs no debug command in the executable.
        for &enemy in g.enemies { enemy.health = 0 }
        game.capture_checkpoint(&g)
        g.player.health, g.player.invulnerable = 1, 0
        g.projectiles[0] = {g.player.position+game.Vec3{0, 0.8, -20}, {0, 0, 1}, 40, .Fairy}
        assert(storage.write(&s, &g, .Quick).kind == .None)
        fmt.println("DEATH FIXTURE OK: fairy bolt reaches stationary player after twenty simulation seconds")
    } else if os.args[1] == "write" {
		assert(storage.write(&s, &g, .Checkpoint).kind == .None)
		g.player.health, g.player.fragment_ammo, g.player.fragment_unlocked = 67, 7, true
		g.player.position, g.player.velocity = {0, 1.2, 10}, {0, 3, -2}
		g.enemies[5].health, g.kills = 0, 1
		g.projectiles[0] = {{0, 3, 9}, {1, 0, 0}, 2, .Fairy}
		assert(storage.write(&s, &g, .Quick).kind == .None)
		fmt.println("WRITE OK: two atomic save slots")
	} else {
		assert(os.args[1] == "read")
		slot, ok := storage.latest(&s)
		assert(ok && slot == .Quick)
		assert(storage.load(&s, &g, slot).kind == .None)
		assert(g.hero == .Lora && g.world.seed == 10831 && g.difficulty == .Nightmare && g.player.health == 67 && g.player.fragment_ammo == 7 && g.player.fragment_unlocked)
		assert(g.player.position == game.Vec3{0, 1.2, 10} && g.player.velocity == game.Vec3{0, 3, -2} && g.enemies[5].health == 0 && g.kills == 1 && g.projectiles[0].life == 2)
		game.respawn(&g)
		assert(g.hero == .Lora && g.enemies[5].health > 0 && g.kills == 0 && g.player.fragment_ammo == 0)
		fmt.println("READ OK: fresh process restored airborne combat and its earlier checkpoint")
	}
}
