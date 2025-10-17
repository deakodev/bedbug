package thingy

import bc "bedbug:core"
import "core:fmt"

Hello :: struct {
	value: string,
}

g_hello: Hello = {
	value = "Hello",
}

hello :: proc(state: ^Hello) -> ^Hello {

	fmt.println(g_hello.value)

	if (state != nil) {
		fmt.println(state.value)
	}

	return &g_hello
}
