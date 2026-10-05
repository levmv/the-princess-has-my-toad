#+build js
package main

import "core:mem"

foreign import emscripten "env.o"
foreign emscripten {
	emscripten_get_now :: proc "c" () -> f64 ---
	malloc :: proc "c" (size: uintptr) -> rawptr ---
	@(link_name = "free")
	free_c :: proc "c" (p: rawptr) ---
}

// Odin and raylib share Emscripten's heap. Each allocation retains its original
// pointer so over-aligned maps/SIMD also work. Resize copies from the aligned
// address; a libc realloc could move its alignment offset and corrupt data.
web_allocate :: proc(_: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
	old: rawptr, old_size: int, location := #caller_location) -> ([]u8, mem.Allocator_Error) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if size == 0 {
			if old != nil { free_c((cast(^rawptr)(uintptr(old)-size_of(rawptr)))^) }
			return nil, nil
		}
		a := max(alignment, align_of(rawptr))
		base := malloc(uintptr(size+a-1+size_of(rawptr)))
		if base == nil { return nil, .Out_Of_Memory }
		aligned := (uintptr(base)+size_of(rawptr)+uintptr(a)-1) & ~(uintptr(a)-1)
		(cast(^rawptr)(aligned-size_of(rawptr)))^ = base
		data := mem.byte_slice(rawptr(aligned), size)
		if mode == .Alloc || mode == .Resize { mem.zero(raw_data(data), size) }
		if old != nil {
			copy(data, mem.byte_slice(old, min(old_size, size)))
			free_c((cast(^rawptr)(uintptr(old)-size_of(rawptr)))^)
		}
		return data, nil
	case .Free:
		if old != nil { free_c((cast(^rawptr)(uintptr(old)-size_of(rawptr)))^) }
		return nil, nil
	case .Query_Features:
		(cast(^mem.Allocator_Mode_Set)old)^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		return nil, nil
	case .Free_All, .Query_Info: return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}
