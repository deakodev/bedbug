package scene

import "base:runtime"
import bb "bedbug:core"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:time"

import ecs "bedbug:vendor/ode_ecs"
import oc "bedbug:vendor/ode_ecs/ode_core"

Transform :: struct {
	position: bb.vec3,
	rotation: bb.vec3,
	scale:    bb.vec3,
}

MeshRef :: struct {
	handle: u64,
	flags:  bit_set[enum {
		Visable,
	}],
}

MaterialRef :: struct {
	handle: u64,
	flags:  bit_set[enum {
		Visable,
	}],
}

Scene :: struct {
	registry:    ecs.Database,
	transforms:  ecs.Table(Transform),
	meshes:      ecs.Table(MeshRef),
	materials:   ecs.Table(MaterialRef),
	renderables: ecs.View,
}

setup :: proc(scene: ^Scene) {

	err: ecs.Error
	allocator := context.allocator

	err = ecs.init(&scene.registry, 100_000, allocator) // Maximum 100K entities
	if err != nil {report_error(err);return}

	err = ecs.table_init(&scene.transforms, &scene.registry, 100_000) // Maximum 100K Transform components
	if err != nil {report_error(err);return}

	err = ecs.view_init(&scene.renderables, &scene.registry, {&scene.transforms})
	if err != nil {report_error(err);return}


}

cleanup :: proc(scene: ^Scene) {

	err := ecs.terminate(&scene.registry)
	if err != nil {report_error(err)}
}

report_error :: proc(err: ecs.Error, loc := #caller_location) {

	log.error("Error:", err, location = loc)
}

create_entities_with_random_components_and_data :: proc(scene: ^Scene, number_of_components_to_create: int) {

	pos: ^Transform
	err: ecs.Error

	eid: ecs.entity_id
	eid_components_count: int
	for i := 0; i < number_of_components_to_create; i += 1 {
		eid, err = ecs.database__create_entity(&scene.registry)
		if err != nil {report_error(err);return}

		pos, err = ecs.add_component(&scene.transforms, eid)
		if err != nil {report_error(err);fmt.println(eid);return}
	}
}

destroy_entities_in_range :: proc(scene: ^Scene, start_ix, end_ix: int) {
	assert(end_ix > start_ix)
	assert(start_ix >= 0)

	for i := start_ix; i < end_ix; i += 1 {
		eid := ecs.get_entity(&scene.registry, i)
		ecs.database__destroy_entity(&scene.registry, eid)
	}
}
