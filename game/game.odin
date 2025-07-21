package game

import bb "bedbug:core"
import "core:log"


Game_Memory :: struct {
	some_number: int,
}


g: ^Game_Memory


update :: proc() {
	log.infof("game update: %d", g.some_number)
}


draw :: proc() {
	log.infof("game draw")
}


@(export)
game_setup :: proc() {

	g = new(Game_Memory)

	g^ = Game_Memory {
		some_number = 100,
	}

	game_hot_reloaded(g)
}


@(export)
game_cleanup :: proc() {
	free(g)
}


@(export)
game_update :: proc() {

	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}


@(export)
game_memory :: proc() -> rawptr {
	return g
}


@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}


@(export)
game_hot_reloaded :: proc(mem: rawptr) {

	g = (^Game_Memory)(mem)
}
