package plugins

import bc "bedbug:core"
import "bedbug:plugins/dcm_parser"
// import "bedbug:plugins/thingy"
import "core:fmt"

// /*
// 	Client-side configuration for engine.
// 	This declares options and modules for engine-side use.
// */

OPTIONS: bc.Options = {
	window_title  = "Bedbug",
	window_width  = 1200,
	window_height = 800,
	target_fps    = 60,
	fullscreen    = false,
}


Modules :: enum u8 {
	VIEWER,
	EDITOR,
}

CLIENT :: Modules.VIEWER

Plugin :: bc.Plugin

// Thingy :: thingy.Interface
// thingy_config :: thingy.config

DcmParser :: dcm_parser.Interface
dcm_parser_config :: dcm_parser.config
