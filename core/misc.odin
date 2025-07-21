package core

import "core:strings"

string_of_bytes :: proc(bytes: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(bytes[:]), 0)
}
