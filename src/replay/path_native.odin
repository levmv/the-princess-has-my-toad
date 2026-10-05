#+build !js
package replay

import "core:path/filepath"

parent_directory :: proc(path: string) -> string { return filepath.dir(path) }
