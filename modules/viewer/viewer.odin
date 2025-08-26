package viewer

import bc "bedbug:core"
import br "bedbug:runtime"
import "core:log"

Viewer :: struct {
	scene: br.Scene,
}

@(export)
viewer_setup :: proc(bedbug: rawptr) -> (self: rawptr, type: typeid) {

	log.info("setting up viewer...")

	self = new(Viewer)
	viewer := (^Viewer)(self)
	entity := br.entity_create(&viewer.scene)

	return self, type_of(self)
}

@(export)
viewer_cleanup :: proc(bedbug: rawptr, self: rawptr) {
	log.info("cleaning up viewer...")
	free(self)
}

@(export)
viewer_update :: proc(bedbug: rawptr, self: rawptr) {
	viewer := (^Viewer)(self)

}

@(export)
viewer_draw :: proc(bedbug: rawptr, self: rawptr) {

}
