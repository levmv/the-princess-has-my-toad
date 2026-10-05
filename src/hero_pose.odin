package main

import "core:math"
import gl "graphics"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"

hero_bone :: proc(h: ^Hero_Renderer, bone: Hero_Bone, origin, x, y, z: game.Vec3) {
	binds := HERO_BIND
	bind := binds[int(bone)]
	p := origin-x*bind.x-y*bind.y-z*bind.z
	h.bones[bone] = {{x.x, x.y, x.z, 0}, {y.x, y.y, y.z, 0}, {z.x, z.y, z.z, 0}, {p.x, p.y, p.z, 1}}
}

hero_segment :: proc(h: ^Hero_Renderer, bone: Hero_Bone, a, b, back: game.Vec3) {
	y := game.normalized(a-b)
	x := game.normalized(game.cross(y, back))
	if game.length(x) < 0.1 { x = {1, 0, 0} }
	z := game.normalized(game.cross(x, y))
	x = game.cross(y, z)
	hero_bone(h, bone, a, x, y, z)
}

hero_joint :: proc(a, b, preferred: game.Vec3, length: f32) -> game.Vec3 {
	direction := game.normalized(b-a)
	bend := game.normalized(preferred-direction*game.dot(direction, preferred))
	return (a+b)*0.5+bend*math.sqrt(max(0.0001, length*length-game.dot(b-a, b-a)*0.25))
}

prepare_hero :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32, camera: game.Camera) {
	h := &r.hero
	h.active, h.character = true, g.hero
	p := &g.player
	h.flash = 0.55 if p.invulnerable > 0 && int(time*14)%2 == 0 else 0
	pos := p.position
	f := game.forward(p.yaw, 0)
	right := game.Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
	up := game.Vec3{0, 1, 0}
	horizontal := game.Vec3{p.velocity.x, 0, p.velocity.z}
	speed := game.length(horizontal)
	motion := min(1, speed/game.RUN_SPEED)
	travel := game.normalized(horizontal) if speed > 0.1 else f
	// The hips follow a strafe while the shoulders and hands keep aiming.
	leg_yaw := math.atan2(game.dot(travel, right), abs(game.dot(travel, f)))
	leg_yaw = clamp(leg_yaw, -0.85, 0.85)*motion
	leg_forward := f*math.cos(leg_yaw)+right*math.sin(leg_yaw)
	leg_right := right*math.cos(leg_yaw)-f*math.sin(leg_yaw)
	land := math.sin(p.land_time/0.24*math.PI)*p.land_strength
	bob := abs(math.sin(p.gait_phase))*0.018*motion if p.grounded else f32(0)
	idle := min(1, max(0, p.idle_time-2)*0.4) if !camera.scoped else f32(0)
	idle_phase := math.mod(max(0, p.idle_time-3), 18)
	neck := math.sin((idle_phase-3)/2*math.PI)*idle if idle_phase > 3 && idle_phase < 5 else f32(0)
	shift := math.sin((idle_phase-8)/3*math.PI)*idle if idle_phase > 8 && idle_phase < 11 else f32(0)
	check := math.sin((idle_phase-13)/2.5*math.PI)*idle if idle_phase > 13 && idle_phase < 15.5 else f32(0)
	hurt := math.sin(clamp(p.hurt_time/0.28, 0, 1)*math.PI)
	kick := math.sin(clamp(1-p.kick_time/game.KICK_DURATION, 0, 1)*math.PI) if p.kick_time > 0 else f32(0)
	breath := math.sin(time*2.4)*0.006
	stride_crouch := motion*0.065 if p.grounded else f32(0)
	pelvis := pos+up*(0.84+bob-land*0.12-stride_crouch)+right*(math.sin(time*0.9)*idle*0.012+shift*0.045)
	chest := pelvis+up*(0.26+breath)+travel*(0.04*motion)+f*(land*0.04-p.recoil*0.017-kick*0.09-hurt*0.08)
	chest_up := game.normalized(up+travel*0.12*motion+f*(land*0.12-hurt*0.20)+right*shift*0.05)
	chest_right := game.normalized(game.cross(chest_up, -f))
	chest_back := game.cross(chest_right, chest_up)
	hero_bone(h, .Pelvis, pelvis, leg_right, up, -leg_forward)
	hero_bone(h, .Chest, chest, chest_right, chest_up, chest_back)
	head := chest+chest_up*0.31
	look := p.pitch*0.35+math.sin(time*0.65)*idle*0.035-neck*0.12-hurt*0.16-check*0.15
	head_f := f*math.cos(neck*0.32)+right*math.sin(neck*0.32)
	head_right := right*math.cos(neck*0.32)-f*math.sin(neck*0.32)
	hero_bone(h, .Head, head, head_right, up*math.cos(look)-head_f*math.sin(look), -head_f*math.cos(look)-up*math.sin(look))
	hero_bone(h, .Pack, chest+chest_back*0.15, chest_right, chest_up, chest_back)
	for side in 0..<2 {
		sign := f32(side*2-1)
		phase := p.gait_phase+f32(side)*math.PI
		hip := pelvis+leg_right*sign*0.125
		ankle := pos+leg_right*sign*0.125+up*0.1
		if p.grounded {
			ankle += travel*(math.cos(phase)*0.32*motion)+up*(max(0, math.sin(phase))*0.15*motion)
		} else {
			tuck := min(1, p.air_time*10)
			ankle += up*((0.18+f32(side)*0.065)*tuck)+f*((0.08-f32(side)*0.13)*tuck-p.glide_blend*0.24)
		}
		// Respect limb length, even during an extreme landing or dash.
		if side == 1 && kick > 0 {
			from := pos+right*0.14+up*0.73
			reach := max(0, game.world_ray(g.world, from, f, 0.79, 0.15)-0.02)
			ankle = ankle*(1-kick)+(from+f*reach)*kick
		}
		delta := ankle-hip
		if game.length(delta) > 0.75 { ankle = hip+game.normalized(delta)*0.75 }
		knee := hero_joint(hip, ankle, leg_forward, 0.38)
		thigh := Hero_Bone.Thigh_L if side == 0 else Hero_Bone.Thigh_R
		shin := Hero_Bone.Shin_L if side == 0 else Hero_Bone.Shin_R
		foot := Hero_Bone.Foot_L if side == 0 else Hero_Bone.Foot_R
		hero_segment(h, thigh, hip, knee, -leg_forward)
		hero_segment(h, shin, knee, ankle, -leg_forward)
		if side == 1 && kick > 0 {
			a := kick*1.25
			hero_bone(h, foot, ankle, right, up*math.cos(a)-f*math.sin(a), -f*math.cos(a)-up*math.sin(a))
		} else { hero_bone(h, foot, ankle, leg_right, up, -leg_forward) }
	}
	muzzle := game.weapon_muzzle(g)
	if p.weapon == .Fragmentator { muzzle = game.fragment_muzzle_pose(g.world, p) }
	// The menu/inspection camera must not change the actor's aim.
	direction := game.normalized(game.aim_point(g, game.camera(g, camera.scoped))-muzzle)
	gun_right := game.normalized(game.cross(direction, up))
	gun_up := game.cross(gun_right, direction)
	gun_position := muzzle-direction*(0.24+p.recoil*0.035+check*0.025)-up*check*0.045
	if p.weapon == .Shotgun { gun_position -= direction*0.33 }
	hero_bone(h, .Gun, gun_position, gun_right, gun_up, -direction)
	if p.weapon == .Fragmentator {
		r.objects.passes = SHADOW_PASS
		if !camera.scoped { r.objects.passes |= WORLD_PASS }
		object_instance(r, .FragmentBarrel, muzzle, gun_right, direction, gun_up, rl.WHITE)
		object_instance(r, .AmmoPacket, gun_position-gun_right*0.15-gun_up*0.02, gun_right*0.48, gun_up*0.48, -direction*0.48, MINT if p.fragment_ammo > 0 else MUTED)
	}
	if p.weapon == .Shotgun {
		r.objects.passes = SHADOW_PASS
		if !camera.scoped { r.objects.passes |= WORLD_PASS }
		object_instance(r, .ShotgunBody, muzzle-direction*(p.recoil*0.09), gun_right, gun_up, -direction, rl.WHITE)
	}
	for side in 0..<2 {
		sign := f32(side*2-1)
		shoulder := chest+chest_up*0.16+right*(sign*0.27)
		hand := gun_position-direction*0.10-gun_up*0.085
		if side == 0 { hand = gun_position+direction*0.04-gun_up*0.12-gun_right*0.13 }
		if side == 0 && p.weapon == .Shotgun { hand += direction*0.20 }
		elbow := hero_joint(shoulder, hand, right*sign-up*0.7, 0.28)
		arm := Hero_Bone.Arm_L if side == 0 else Hero_Bone.Arm_R
		forearm := Hero_Bone.Forearm_L if side == 0 else Hero_Bone.Forearm_R
		hand_bone := Hero_Bone.Hand_L if side == 0 else Hero_Bone.Hand_R
		hero_segment(h, arm, shoulder, elbow, -f)
		hero_segment(h, forearm, elbow, hand, -f)
		hero_bone(h, hand_bone, hand, gun_right, gun_up, -direction)
	}
	h.visible = !camera.scoped && game.length(camera.position-pos-up*game.EYE_HEIGHT) > 0.65
	// Effects share the exact gameplay muzzle. Body animation never moves a shot.
	r.objects.passes = WORLD_PASS
	if p.recoil > 0.60 {
		flash := (p.recoil-0.6)*0.5
		if p.weapon == .Shotgun { flash *= 1.8 }
		tip := muzzle+direction*(0.20+flash)
		for axis in ([2]game.Vec3{gun_right, gun_up}) {
			lit_triangle(r, muzzle-axis*flash, tip, muzzle+axis*flash, {255, 218, 155, 255})
			lit_triangle(r, muzzle+axis*flash, tip, muzzle-axis*flash, {255, 245, 210, 255})
		}
	}
	r.objects.passes = SHADOW_PASS
	if h.visible { r.objects.passes |= WORLD_PASS }
	if p.glide_blend > 0.01 {
		center := chest+up*0.32-f*0.2
		spread := p.glide_blend
		left, right_tip := center-right*1.9*spread-f*0.65+up*0.08, center+right*1.9*spread-f*0.65+up*0.08
		tail := center-f*1.35-up*0.18
		lit_triangle(r, center, left, tail, ORANGE)
		lit_triangle(r, tail, left, center, ORANGE)
		lit_triangle(r, center, tail, right_tip, {229, 98, 57, 255})
		lit_triangle(r, right_tip, tail, center, {229, 98, 57, 255})
		line3(r, left, center, 0.025, PAPER)
		line3(r, center, right_tip, 0.025, PAPER)
		line3(r, center, tail, 0.02, PAPER)
		line3(r, left, tail, 0.018, PAPER)
		line3(r, right_tip, tail, 0.018, PAPER)
	}
	r.objects.passes = WORLD_PASS
}

hero_draw :: proc(r: ^Renderer, shadow: bool) {
	h := &r.hero
	if !h.active || (!shadow && !h.visible) { return }
	model := &h.models[h.character]
	index := 1 if shadow else 0
	shader := r.depth if shadow else r.scene
	rlgl.DrawRenderBatchActive()
	rl.SetShaderValueMatrix(shader, shader.locs[rl.ShaderLocationIndex.MATRIX_MVP], rlgl.GetMatrixProjection()*rlgl.GetMatrixModelview())
	gl.UseProgram(shader.id)
	gl.Uniform1i(h.skin_location[index], 1)
	if !shadow { gl.Uniform1f(h.flash_location, h.flash) }
	gl.UniformMatrix4fv(h.bones_location[index], i32(len(h.bones)), false, &h.bones[.Pelvis][0][0])
	gl.BindVertexArray(model.mesh.vaoId)
	gl.DrawArrays(gl.TRIANGLES, 0, model.mesh.vertexCount)
	gl.BindVertexArray(0)
	gl.Uniform1i(h.skin_location[index], 0)
}
