package main

import "core:strings"
import rl "vendor:raylib"

shader_text :: proc(source: string) -> cstring {
	when ODIN_OS == .JS {
		assert(strings.has_prefix(source, "#version 330\n"))
		es := strings.concatenate({"#version 300 es\nprecision highp float;\nprecision highp int;\n", source[len("#version 330\n"):]})
		defer delete(es)
		return strings.clone_to_cstring(es)
	} else { return strings.clone_to_cstring(source) }
}

load_game_shader :: proc(vertex, fragment: string) -> rl.Shader {
	v: cstring
	if vertex != "" { v = shader_text(vertex) }
	defer delete(v)
	f := shader_text(fragment)
	defer delete(f)
	return rl.LoadShaderFromMemory(v, f)
}
