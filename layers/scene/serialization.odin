package scene

import ecs "bedbug:vendor/ode_ecs"
import "core:encoding/json"
import "core:encoding/uuid"

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"


ComponentTypeHash :: distinct u64 // stable hash of component type

ComponentMetadata :: struct {
	name:    string,
	hash:    ComponentTypeHash,
	version: u16,
	size:    int,
	align:   int,
}

scene_json_write :: proc(scene: ^Scene) {

	for i in 0 ..< ecs.database__entities_len(&scene.database) {
		eid := ecs.get_entity(&scene.database, i)
		log.debug("Entity ID:", eid)

		// tag_comp := ecs.get_component(scene.tags, eid)

		// log.debug("Tag:", tag_comp.tag)
	}

}
