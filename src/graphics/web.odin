#+build js
package graphics

ARRAY_BUFFER :: 0x8892
STREAM_DRAW :: 0x88E0
STATIC_DRAW :: 0x88E4
TRIANGLES :: 0x0004
LINES :: 0x0001
FLOAT :: 0x1406
UNSIGNED_SHORT :: 0x1403

foreign import webgl "env.o"
@(link_prefix = "gl")
foreign webgl {
	BindBuffer :: proc "c" (target: u32, buffer: u32) ---
	BindVertexArray :: proc "c" (array: u32) ---
	BufferData :: proc "c" (target: u32, size: int, data: rawptr, usage: u32) ---
	BufferSubData :: proc "c" (target: u32, offset: int, size: int, data: rawptr) ---
	DeleteBuffers :: proc "c" (n: i32, buffers: [^]u32) ---
	DrawArrays :: proc "c" (mode: u32, first: i32, count: i32) ---
	DrawArraysInstanced :: proc "c" (mode: u32, first: i32, count: i32, instancecount: i32) ---
	DrawElementsInstanced :: proc "c" (mode: u32, count: i32, type: u32, indices: rawptr, instancecount: i32) ---
	EnableVertexAttribArray :: proc "c" (index: u32) ---
	GenBuffers :: proc "c" (n: i32, buffers: [^]u32) ---
	Uniform1f :: proc "c" (location: i32, v0: f32) ---
	Uniform1i :: proc "c" (location: i32, v0: i32) ---
	UniformMatrix4fv :: proc "c" (location: i32, count: i32, transpose: bool, value: [^]f32) ---
	UseProgram :: proc "c" (program: u32) ---
	VertexAttrib4f :: proc "c" (index: u32, x: f32, y: f32, z: f32, w: f32) ---
	VertexAttribDivisor :: proc "c" (index: u32, divisor: u32) ---
	VertexAttribPointer :: proc "c" (index: u32, size: i32, type: u32, normalized: bool, stride: i32, pointer: uintptr) ---
}
