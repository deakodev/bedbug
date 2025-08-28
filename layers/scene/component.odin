package scene

import bc "bedbug:core"
import ecs "bedbug:vendor/ode_ecs"

TagComponent :: struct {
	tag: string,
}

TransformComponent :: struct {
	position: bc.vec3,
	rotation: bc.vec3,
	scale:    bc.vec3,
}

MeshComponent :: struct {
	handle: u64,
	flags:  bit_set[enum {
		Visable,
	}],
}

MaterialComponent :: struct {
	handle: u64,
	flags:  bit_set[enum {
		Visable,
	}],
}
