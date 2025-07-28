package game

import bb "bedbug:core"
import "core:log"

Game :: struct {
	some_number: int,
}

g: ^Game

@(export)
game_setup :: proc(bedbug: rawptr, self: rawptr) {

	g = new(Game)

	g^ = Game {
		some_number = 100,
	}

	hot_reloaded(g)
}

@(export)
game_cleanup :: proc(bedbug: rawptr, self: rawptr) {

	free(g)
}

@(export)
game_update :: proc(bedbug: rawptr, self: rawptr) {

}

memory :: proc() -> rawptr {

	return g
}

memory_size :: proc() -> int {

	return size_of(Game)
}

hot_reloaded :: proc(mem: rawptr) {

	g = (^Game)(mem)
}
