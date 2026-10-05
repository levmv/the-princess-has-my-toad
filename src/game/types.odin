package game

Vec2 :: [2]f32
Vec3 :: [3]f32

PLAYER_RADIUS :: f32(0.36)
PLAYER_HEIGHT :: f32(1.65)
CONTACT_MARGIN :: f32(0.0001)
STEP :: f32(1.0 / 120.0)
ENEMY_CAPACITY :: 128
CORE_CAPACITY :: 32
PICKUP_CAPACITY :: 64
PARTICLE_CAPACITY :: 384
DEFAULT_SEED :: u32(1847)
EYE_HEIGHT :: f32(1.5)
RUN_SPEED :: f32(12.5)
GLIDE_SPEED :: f32(16)
JUMP_SPEED :: f32(13.2)
GRAVITY :: f32(38)
VOID_HEIGHT :: f32(-24)
STRIDE_DISTANCE :: f32(4.8)
DASH_COOLDOWN :: f32(1.25)
SHOT_INTERVAL :: f32(1.0 / 22.0)
KICK_DURATION :: f32(0.38)
FRAGMENT_INTERVAL :: f32(0.8)
FRAGMENT_AMMO_MAX :: 24
FRAGMENT_SPEED :: f32(56)
FRAGMENT_GRAVITY :: f32(0.10)
FRAGMENT_RADIUS :: f32(8.5)
SHOTGUN_INTERVAL :: f32(0.85)
SHOTGUN_AMMO_MAX :: 36
SHOTGUN_PELLETS :: 20
VIEW_FOV :: f32(72)
SCOPE_FOV :: f32(28)
CAMERA_DISTANCE :: f32(4.4)
CAMERA_HEIGHT :: f32(1.3)
CAMERA_SIDE :: f32(0.10)
CAMERA_CLEARANCE :: f32(0.2)
CAMERA_NEAR :: f32(0.1)

Input :: struct {
	move: Vec2,
	look: Vec2, // Absolute yaw/pitch at the fixed tick, suitable for replay.
	has_look: bool,
	jump_pressed, jump_held, dash_pressed, fire, focus, interact_pressed, kick_pressed: bool,
	anvil_pressed: bool,
	weapon_select: int, // 0 unchanged; 1 repeater, 2 fragmentator, 3 shotgun.
}

Player :: struct {
	position, velocity: Vec3,
	yaw, pitch: f32,
	health: f32,
	grounded, gliding, in_current: bool,
	glide_ready: bool,
	coyote, jump_buffer, dash_cooldown, dash_time: f32,
	invulnerable, shot_cooldown, recoil, hit_marker, hurt_time, hurt_strength: f32,
	gait_phase, land_time, land_strength, idle_time, air_time, glide_blend: f32,
	weapon_bloom, scope_time: f32,
	kick_time, kick_cooldown, switch_time, fragment_cooldown: f32,
	weapon: Weapon,
	fragment_ammo: int,
	fragment_unlocked: bool,
	shotgun_ammo: int,
	shotgun_unlocked: bool,
	shotgun_cooldown: f32,
}

Plane :: struct {
	normal: Vec3,
	distance: f32,
}

Block :: struct {
	center, size: Vec3,
	style: int,
	// The box bounds plus extra clipping planes define one convex solid.
	// Rendering, movement, the camera and shots all use this same surface.
	clips: [12]Plane,
	clip_count: int,
}

Vent :: struct {
	position: Vec3,
	radius, top: f32,
	controlled: bool,
}

Core :: struct {
	position: Vec3,
	collected: bool,
}

// Persistent wire values. New entries append IDs; reordering names must never
// reinterpret an existing save as another actor or attack phase.
Enemy_Kind :: enum u8 { Sentry = 0, Interceptor = 1, Crab = 2, Kettle = 3, Nanny = 4, Rabbit, Rabbit_Young, Rabbit_Kit }
Enemy_Phase :: enum u8 { Patrol = 0, Windup = 1, Attack = 2, Recover = 3, Dormant, Hatching }

Enemy :: struct {
	content_id: Object_ID,
	anchor, position: Vec3,
	velocity, facing, attack_direction: Vec3,
	knockback: Vec3,
	last_known, known_velocity, nav_goal, separation: Vec3,
	attack_target: Vec3,
	support: Enemy_ID,
	health: int,
	fire_timer, flash, sight_timer, phase_time, awareness: f32,
	memory_time, nav_time, gait_phase, exposed: f32,
	support_time, windup_duration: f32,
	generation: u32,
	heard_sequence: u32,
	kind: Enemy_Kind,
	phase: Enemy_Phase,
	rounds, encounter: int,
	shield: int,
	alerted, sees_player: bool,
	gibbed: bool,
}

Level_Kind :: enum { Arena = 0, RAM = 1 }
Enemy_Spawn :: struct { position: Vec3, kind: Enemy_Kind, health: int, awareness: f32, id: Object_ID }
Encounter :: struct { room: Room_ID, spawns: [8]Enemy_Spawn, count: int }

Death_Cause :: enum u8 { Unknown, Fairy, Hunter, Crab, Kettle, GC, Fragment, Void, Anvil, Nanny, Rabbit }

Projectile :: struct {
	position, velocity: Vec3,
	life: f32,
	source: Death_Cause,
}

Particle :: struct {
	position, velocity: Vec3,
	life, max_life, size: f32,
	kind: int,
}

Trace :: struct {
	start, end: Vec3,
	life: f32,
}

Light_Flash :: struct {
	position, color: Vec3,
	radius, strength, life, max_life: f32,
}

Camera :: struct {
	position, forward, target: Vec3,
	fov: f32,
	scoped: bool,
}

Decor_Block :: struct { shape: Block, base, top: [3]u8 }
Decor_Beam :: struct { a, b: Vec3, radius_a, radius_b: f32, color: [3]u8, material: f32, sides: int }

// World is owned by the level. Simulation and presentation borrow it.
World :: struct {
	kind: Level_Kind,
	sector: Sector_Recipe,
	room_navigation: [SECTOR_ROOM_CAPACITY]Room_Navigation,
	gates: [GATE_CAPACITY]Gate,
	gate_count: int,
	checkpoints: [SECTOR_CHECKPOINT_CAPACITY]Checkpoint,
	checkpoint_count: int,
	pickup_spawns: [PICKUP_CAPACITY]Pickup,
	pickup_count: int,
	blocks: [dynamic]Block,
	decor_blocks: [dynamic]Decor_Block,
	decor_beams: [dynamic]Decor_Beam,
	vents: [dynamic]Vent,
	core_spawns, enemy_spawns, lamps: [dynamic]Vec3,
	encounters: [dynamic]Encounter,
	lift: Shot_Lift,
	boss_exit: Block,
	boss_exit_amount: f32,
	spawn, exit: Vec3,
	seed: u32,
	revision, index_revision: u64,
	nodes: [dynamic]BVH_Node,
	block_order: [dynamic]int,
}

State :: struct {
	world: ^World,
	using run: Run_State,
	restart: Checkpoint_State,
	checkpoint_sequence: u32,
	checkpoint_pending, in_step, respawn_pending: bool,
	last_death: Death_Cause, // Presentation event survives checkpoint restoration; not gameplay state.
}

// Pointer-free simulation state can be copied for an in-memory checkpoint.
// The disk codec explicitly writes named fields; it never dumps this layout.
Character :: enum u8 { Duke = 0, Lora = 1 }

Run_State :: struct {
	hero: Character,
	difficulty: Difficulty,
	campaign: Campaign_Progress,
	checkpoint_id: Object_ID,
	player: Player,
	player_noise: Player_Noise,
	boss: Boss_State,
	anvil: Anvil_State,
	sound_events: [128]Sound_Event,
	sound_sequence: u32,
	cores: [CORE_CAPACITY]Core,
	core_count: int,
	pickups: [PICKUP_CAPACITY]Pickup,
	pickup_count: int,
	pickup_sequence: u32,
	secrets: [8]Object_ID,
	secret_count: int,
	enemies: [ENEMY_CAPACITY]Enemy,
	enemy_count, enemy_total: int,
	mission_checkpoint: u8,
	lift_started: bool,
	next_enemy_generation: u32,
	projectiles: [96]Projectile,
	fragments: [16]Fragment,
	fragments_refused: u32,
	hazards: [24]Floor_Hazard,
	hazards_refused: u32,
	particles: [PARTICLE_CAPACITY]Particle,
	gibs: [96]Particle,
	gib_cursor: int,
	traces: [16]Trace,
	flashes: [12]Light_Flash,
	flash_cursor: int,
	particle_cursor, projectile_cursor, trace_cursor: int,
	projectiles_refused: u32,
	checkpoint: Vec3,
	time: f32,
	collected, kills, deaths: int,
	shot_sequence, damage_sequence, kill_sequence, jump_sequence: u32,
	land_sequence, step_sequence, glide_sequence: u32,
	rng, effect_rng, weapon_rng: u32,
	won, focused: bool,
	message: int,
	message_time: f32,
}

Enemy_ID :: struct { slot, generation: u32 }

Player_Noise :: struct { position: Vec3, radius, life: f32, sequence: u32 }

Floor_Hazard :: struct { position: Vec3, radius, life, warmup, pulse: f32 }
