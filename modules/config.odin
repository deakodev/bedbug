package config

/* 
	Client-side configuration for engine.
	This declares options and modules for engine-side use.
*/

import bc "bedbug:core"

OPTIONS: bc.Options = {
	// fullscreen = true,
}

Modules :: enum u8 {
	VIEWER,
	EDITOR,
}

CLIENT :: Modules.VIEWER
