package vulkan_backend

import "base:intrinsics"
import "base:runtime"
import bb "bedbug:core"
import "core:log"
import "core:strings"
import "vendor:cgltf"
import vk "vendor:vulkan"

MeshVertex :: struct {
	position: bb.vec3,
	uv_x:     f32,
	normal:   bb.vec3,
	uv_y:     f32,
	color:    bb.vec4,
}

MeshBuffers :: struct {
	index_buffer:  AllocatedBuffer,
	vertex_buffer: AllocatedBuffer,
}

GeoSurface :: struct {
	start_index: u32,
	count:       u32,
}

Mesh :: struct {
	name:     string,
	buffers:  MeshBuffers,
	surfaces: [dynamic]GeoSurface,
}

Meshes :: [dynamic]^Mesh

// Override the vertex colors with the vertex normals which is useful for debugging.
OVERRIDE_VERTEX_COLORS :: #config(OVERRIDE_VERTEX_COLORS, true)

meshes_create_from_gtlf :: proc(
	self: ^Vulkan,
	file_path: string,
	allocator := context.allocator,
) -> (
	meshes: Meshes,
	ok: bool,
) {

	log.debug("loading gtlf: ", file_path)

	gtlf_options := cgltf.options {
		type = .invalid,
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	c_file_path := strings.clone_to_cstring(file_path, context.temp_allocator)

	gtlf_data, result := cgltf.parse_file(gtlf_options, c_file_path)
	if result != .success {
		log.errorf("failed to parse GLTF: %v", result)
		return
	}
	defer cgltf.free(gtlf_data)

	result = cgltf.load_buffers(gtlf_options, gtlf_data, c_file_path)
	if result != .success {
		log.errorf("failed to load glTF buffers: %v\n", result)
		return
	}

	indices_temp: [dynamic]u32;indices_temp.allocator = context.temp_allocator
	vertices_temp: [dynamic]MeshVertex;vertices_temp.allocator = context.temp_allocator

	meshes = make(Meshes, allocator)
	defer if !ok {
		meshes_destroy(&meshes, allocator)
	}

	for &gtlf_mesh in gtlf_data.meshes {
		mesh := new(Mesh, allocator)

		mesh.name = strings.clone(gtlf_mesh.name != nil ? string(mesh.name) : "unnambed_mesh")

		mesh.surfaces = make([dynamic]GeoSurface, allocator)

		clear(&indices_temp)
		clear(&vertices_temp)

		for &primitive in gtlf_mesh.primitives {
			surface: GeoSurface

			surface.start_index = u32(len(indices_temp))
			surface.count = u32(primitive.indices.count)

			initial_vertex := len(vertices_temp)

			{ 	// index data
				index_accessor := primitive.indices

				reserve(&indices_temp, len(indices_temp) + int(index_accessor.count))

				index_count := index_accessor.count
				index_buffer := make([]u32, index_count, context.temp_allocator)

				indices_unpacked := cgltf.accessor_unpack_indices(
					index_accessor,
					raw_data(index_buffer),
					uint(size_of(u32)),
					index_count,
				)
				if indices_unpacked < uint(index_count) {
					log.errorf(
						"[%s]: only unpacked %d indices out of %d expected",
						mesh.name,
						indices_unpacked,
						index_count,
					)
					return
				}

				for index in 0 ..< index_count {
					append(&indices_temp, index_buffer[index] + u32(initial_vertex))
				}
			}

			{ 	// vertex positon data
				position_accessor: ^cgltf.accessor

				for &attribute in primitive.attributes {
					if attribute.type == .position {
						position_accessor = attribute.data
						break
					}
				}

				if position_accessor == nil {
					log.warn("mesh has no position attribute.")
					continue // skip primitive
				}

				previous_vertex_count := len(vertices_temp)
				vertex_count := int(position_accessor.count)
				resize(&vertices_temp, previous_vertex_count + vertex_count)

				for &vertex in vertices_temp {
					vertex = {
						normal = {1, 0, 0},
						color  = {1, 1, 1, 1},
						uv_x   = 0,
						uv_y   = 0,
					}
				}

				positions := make([]f32, vertex_count * 3, context.temp_allocator)

				vertices_unpacked := cgltf.accessor_unpack_floats(
					position_accessor,
					raw_data(positions),
					uint(vertex_count * 3),
				)
				if vertices_unpacked < uint(vertex_count) {
					log.errorf(
						"[%s]: only unpacked %v vertices out of %v expected",
						mesh.name,
						vertices_unpacked,
						vertex_count,
					)
					return
				}

				for &vertex, index in vertices_temp {
					x := index * 3;y, z := x + 1, x + 2
					vertex.position = {positions[x], positions[y], positions[z]}
				}
			}

			{ 	// load vertex normals 
				normal_accessor: ^cgltf.accessor
				for &attribute in primitive.attributes {
					if attribute.type == .normal {
						normal_accessor = attribute.data
						break
					}
				}

				if normal_accessor != nil {
					vertex_count := int(normal_accessor.count)
					normals := make([]f32, vertex_count * 3)
					defer delete(normals)

					normals_unpacked := cgltf.accessor_unpack_floats(
						normal_accessor,
						raw_data(normals),
						uint(vertex_count * 3),
					)
					if normals_unpacked < uint(vertex_count) {
						log.errorf(
							"[%s]: only unpacked %v normals out of %v expected",
							mesh.name,
							normals_unpacked,
							vertex_count,
						)
						return
					}

					for &vertex, index in vertices_temp {
						x := index * 3;y, z := x + 1, x + 2
						vertex.normal = {normals[x], normals[y], normals[z]}
					}
				}
			}

			{ 	// load UV normals 
				uv_accessor: ^cgltf.accessor
				for &attribute in primitive.attributes {
					if attribute.type == .texcoord && attribute.index == 0 {
						uv_accessor = attribute.data
						break
					}
				}

				if uv_accessor != nil {
					vertex_count := int(uv_accessor.count)
					uvs := make([]f32, vertex_count * 2)
					defer delete(uvs)

					if texcoords_unpacked := cgltf.accessor_unpack_floats(
						uv_accessor,
						raw_data(uvs),
						uint(vertex_count * 2),
					); texcoords_unpacked < uint(vertex_count) {
						log.errorf(
							"]%s]: Only unpacked %v texcoords out of %v expected",
							mesh.name,
							texcoords_unpacked,
							vertex_count,
						)
						return
					}

					for &vertex, index in vertices_temp {
						x := index * 2;y := x + 1
						vertex.uv_x, vertex.uv_y = uvs[x], uvs[y]
					}
				}
			}

			{ 	// load vertex colors
				color_accessor: ^cgltf.accessor
				for &attribute in primitive.attributes {
					if attribute.type == .color && attribute.index == 0 {
						color_accessor = attribute.data
						break
					}
				}

				if color_accessor != nil {
					vertex_count := int(color_accessor.count)
					colors := make([]f32, vertex_count * 4)
					defer delete(colors)

					if colors_unpacked := cgltf.accessor_unpack_floats(
						color_accessor,
						raw_data(colors),
						uint(vertex_count * 4),
					); colors_unpacked < uint(vertex_count) {
						log.warnf(
							"[%s]: Only unpacked %v colors out of %v expected",
							mesh.name,
							colors_unpacked,
							vertex_count,
						)
					}

					for i := 0; i < vertex_count; i += 1 {
						idx := i * 4
						vertices_temp[initial_vertex + i].color = {
							colors[idx],
							colors[idx + 1],
							colors[idx + 2],
							colors[idx + 3],
						}
					}

					for &vertex, index in vertices_temp {
						r := index * 4;g, b, a := r + 1, r + 2, r + 3
						vertex.color = {colors[r], colors[g], colors[b], colors[a]}
					}
				}
			}

			append(&mesh.surfaces, surface)
		}

		// Optional: Override vertex colors with normal visualization
		when OVERRIDE_VERTEX_COLORS {
			for &vtx in vertices_temp {
				vtx.color = {vtx.normal.x, vtx.normal.y, vtx.normal.z, 1.0}
			}
		}

		mesh.buffers = mesh_buffers_create(self, indices_temp[:], vertices_temp[:])

		append(&meshes, mesh)
	}

	if len(meshes) == 0 {
		return
	}

	return meshes, true
}

mesh_destroy :: proc(mesh: ^Mesh, allocator := context.allocator) {
	assert(mesh != nil, "Invalid 'Mesh_Asset'")
	context.allocator = allocator
	delete(mesh.name)
	delete(mesh.surfaces)
	free(mesh)
}

meshes_destroy :: proc(meshes: ^Meshes, allocator := context.allocator) {
	context.allocator = allocator
	for &mesh in meshes {
		mesh_destroy(mesh)
	}
	delete(meshes^)
}

// todo: calls should occur on a thread seperate from the render thread
mesh_buffers_create :: proc(self: ^Vulkan, indices: []u32, vertices: []MeshVertex) -> (buffers: MeshBuffers) {

	vertex_buffer_size := vk.DeviceSize(len(vertices) * size_of(MeshVertex))
	index_buffer_size := vk.DeviceSize(len(indices) * size_of(u32))

	buffers.vertex_buffer = allocated_buffer_create(
		self,
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST},
		.Gpu_Only,
	)

	buffers.index_buffer = allocated_buffer_create(self, index_buffer_size, {.INDEX_BUFFER, .TRANSFER_DST}, .Gpu_Only)

	staging_buffer := allocated_buffer_create(self, vertex_buffer_size + index_buffer_size, {.TRANSFER_SRC}, .Cpu_Only)
	defer allocated_buffer_cleanup(staging_buffer)

	data := staging_buffer.alloc_info.mapped_data

	intrinsics.mem_copy(data, raw_data(vertices), vertex_buffer_size)
	intrinsics.mem_copy(rawptr(uintptr(data) + uintptr(vertex_buffer_size)), raw_data(indices), index_buffer_size)

	RecordInfo :: struct {
		staging_buffer_handle: vk.Buffer,
		vertex_buffer_handle:  vk.Buffer,
		index_buffer_handle:   vk.Buffer,
		vertex_buffer_size:    vk.DeviceSize,
		index_buffer_size:     vk.DeviceSize,
	}

	record_info := RecordInfo {
		staging_buffer_handle = staging_buffer.handle,
		vertex_buffer_handle  = buffers.vertex_buffer.handle,
		index_buffer_handle   = buffers.index_buffer.handle,
		vertex_buffer_size    = vertex_buffer_size,
		index_buffer_size     = index_buffer_size,
	}

	device_immediate_command(
		&self.device,
		record_info,
		proc(device: ^Device, command: vk.CommandBuffer, info: RecordInfo) {

			vertex_copy := vk.BufferCopy {
				srcOffset = 0,
				dstOffset = 0,
				size      = info.vertex_buffer_size,
			}
			vk.CmdCopyBuffer(command, info.staging_buffer_handle, info.vertex_buffer_handle, 1, &vertex_copy)

			index_copy := vk.BufferCopy {
				srcOffset = info.vertex_buffer_size,
				dstOffset = 0,
				size      = info.index_buffer_size,
			}
			vk.CmdCopyBuffer(command, info.staging_buffer_handle, info.index_buffer_handle, 1, &index_copy)
		},
	)

	return buffers
}
