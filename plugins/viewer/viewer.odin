package viewer

import bc "bedbug:core"
import br "bedbug:runtime"
import "core:log"

Viewer :: struct {
	scene: br.Scene,
}

@(bedbug_export)
viewer_setup :: proc(bedbug: rawptr) -> (self: rawptr, type: typeid) {

	log.info("setting up viewer...")

	self = new(Viewer)
	viewer := (^Viewer)(self)

	br.scene_setup(&viewer.scene)

	eid := br.entity_create(&viewer.scene)

	// tag := br.entity_component_add(&viewer.scene.tags, eid)
	// br.scene_json_write(&viewer.scene.database)

	return self, type_of(self)
}

@(export)
viewer_cleanup :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {
	log.info("cleaning up viewer...")

	viewer := (^Viewer)(self)
	br.scene_cleanup(&viewer.scene)

	free(self)
	return true
}

@(export)
viewer_update :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {
	viewer := (^Viewer)(self)
	return true
}

@(export)
viewer_draw :: proc(bedbug: rawptr, self: rawptr) -> (ok: bool) {

	return true
}
