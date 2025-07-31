package core

import "core:strings"

string_of_bytes :: proc(bytes: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(bytes[:]), 0)
}

pipe :: proc(initial: $T, ops: ..proc(data: T) -> T) -> (result: T) {

	result = initial
	for op in ops {
		result = op(result)
	}
	return result
}

PatchOp :: struct($P, $T: typeid) {
	patch: P,
	op:    proc(patch: P, data: T) -> T,
}

pipe_patch :: proc(initial: $T, patches: ..PatchOp($P, T)) -> (result: T) {

	result = initial
	for patch in patches {
		result = patch.op(patch.patch, result)
	}
	return result
}
