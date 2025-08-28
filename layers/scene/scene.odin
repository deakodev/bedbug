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

Scene :: struct {
	database:    ecs.Database,
	tags:        ecs.Table(TagComponent),
	transforms:  ecs.Table(TransformComponent),
	// meshes:      ecs.Table(MeshComponent),
	// materials:   ecs.Table(MaterialComponent),
	renderables: ecs.View,
}

setup :: proc(scene: ^Scene) {

	err: ecs.Error

	// ecs_setup()

	err = ecs.init(&scene.database, 100_000, context.allocator) // Maximum 100K entities
	if err != nil {report_error(err);return}

	err = ecs.table_init(&scene.tags, &scene.database, 100_000) // Maximum 100K Transform components
	if err != nil {report_error(err);return}

	err = ecs.table_init(&scene.transforms, &scene.database, 100_000) // Maximum 100K Transform components
	if err != nil {report_error(err);return}

	err = ecs.view_init(&scene.renderables, &scene.database, {&scene.transforms})
	if err != nil {report_error(err);return}

}

cleanup :: proc(scene: ^Scene) {

	err := ecs.terminate(&scene.database)
	if err != nil {report_error(err)}
}

report_error :: proc(err: ecs.Error, loc := #caller_location) {

	log.error("Error:", err, location = loc)
}

create_entities_with_random_components_and_data :: proc(scene: ^Scene, number_of_components_to_create: int) {

	pos: ^TransformComponent
	err: ecs.Error

	eid: ecs.entity_id
	eid_components_count: int
	for i := 0; i < number_of_components_to_create; i += 1 {
		eid, err = ecs.database__create_entity(&scene.database)
		if err != nil {report_error(err);return}

		// pos, err = ecs.add_component(&scene.transforms, eid)
		// if err != nil {report_error(err);fmt.println(eid);return}
	}
}

destroy_entities_in_range :: proc(scene: ^Scene, start_ix, end_ix: int) {

	assert(end_ix > start_ix)
	assert(start_ix >= 0)

	for i := start_ix; i < end_ix; i += 1 {
		eid := ecs.get_entity(&scene.database, i)
		ecs.database__destroy_entity(&scene.database, eid)
	}
}
