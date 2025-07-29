package game

import bb "bedbug:core"
import "core:log"

Game :: struct {
	some_number: int,
}

@(export)
game_setup :: proc(bedbug: rawptr) -> (self: rawptr, type: typeid) {

	log.info("setting up game...")

	self = new(Game)

	return self, type_of(self)
}

@(export)
game_cleanup :: proc(bedbug: rawptr, self: rawptr) {
	log.info("cleaning up game...")
	free(self)
}

@(export)
game_update :: proc(bedbug: rawptr, self: rawptr) {
	game := (^Game)(self)
	game.some_number += 1
	log.info("some_number:", game.some_number)
}

@(export)
game_draw :: proc(bedbug: rawptr, self: rawptr) {

}
