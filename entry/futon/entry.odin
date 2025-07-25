package entry

import "bedbug:bedbug"
import "core:log"

//temp
import im "bedbug:vendor/imgui"
import im_glfw "bedbug:vendor/imgui/imgui_impl_glfw"
import im_vk "bedbug:vendor/imgui/imgui_impl_vulkan"

main :: proc() {

	when ODIN_DEBUG {
		context.logger = bedbug.logger_setup()
		context.allocator = bedbug.allocator_setup()
		defer bedbug.allocator_cleanup()
	}

	bedbug_ptr := new(bedbug.Bedbug)
	context.user_ptr = bedbug_ptr

	if ok := bedbug.setup(bedbug_ptr); !ok {
		panic("failed to initialize bedbug.")
	}

	imgui := im.get_current_context()

	futon_lib := bedbug.dynlib_load(bedbug.Futon_Symbols)
	futon := bedbug.dynlib_generation(futon_lib)
	futon.setup(imgui)

	game_lib := bedbug.dynlib_load(bedbug.Game_Symbols)
	game := bedbug.dynlib_generation(game_lib)
	game.setup()

	current_frame: u32 = 0
	run: for bedbug.should_run() {

		bedbug.update()

		if bedbug_ptr.core.window.iconified {
			bedbug.wait_events()
			continue run
		}

		// // ImGUi new frame
		im_glfw.new_frame()
		im_vk.new_frame()
		im.new_frame()

		// // Some ImGUi UI to test
		// im.show_demo_window()

		// // Make ImGUi calculate internal draw structures
		// im.render()

		futon.update(bedbug_ptr)
		bedbug.frame_draw(bedbug_ptr.renderer)
		// futon.update()
		// game.update()

		// todo: imple in core
		// force_reload := game.force_reload()
		// force_restart := game.force_restart()
		force_reload := false
		force_restart := false

		if bedbug.dynlib_should_reload(game_lib) || force_reload || force_restart {
			game_lib = bedbug.dynlib_load(bedbug.Game_Symbols)
			game_reload := bedbug.dynlib_generation(game_lib)

			force_restart = force_restart || game.memory_size() != game_reload.memory_size()

			if !force_restart {
				game_memory := game.memory()
				game = game_reload
				game.hot_reloaded(game_memory)

			} else {

				game.cleanup()

				bedbug.allocator_clear()

				// dynlib_unload(&game_lib)
				clear(&game_lib.generations)

				game = game_reload
				game.setup()
			}
		}

		free_all(context.temp_allocator)
		bedbug.allocator_check()
	}

	game.cleanup()
	bedbug.dynlib_unload(game_lib)
	delete(game_lib.generations)

	futon.cleanup()
	bedbug.dynlib_unload(futon_lib)
	delete(futon_lib.generations)

	bedbug.cleanup(bedbug_ptr)
	free(bedbug_ptr)
}
