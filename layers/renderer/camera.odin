package renderer

import bb "bedbug:core"

ProjectionType :: enum {
	PERSPECTIVE,
	ORTHOGRAPHIC,
}

Camera :: struct {
	position:        bb.vec3,
	target:          bb.vec3,
	up:              bb.vec3,
	near:            f32,
	far:             f32,
	y_fov:           f32,
	projection_type: ProjectionType,
}

camera_default :: proc(type: ProjectionType) {
	return
}
