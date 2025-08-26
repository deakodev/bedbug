package scene

import ecs "bedbug:vendor/ode_ecs"

entity_create :: proc(scene: ^Scene) -> ecs.entity_id {

	eid: ecs.entity_id
	err: ecs.Error

	eid, err = ecs.database__create_entity(&scene.registry)
	if err != nil {report_error(err)}

	return eid
}
