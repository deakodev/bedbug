package futon

import bb "bedbug:core"

import "base:runtime"
import "core:fmt"
import "core:log"


@(export)
futon_setup :: proc() {

	log.info("setting up futon")
}


@(export)
futon_cleanup :: proc() {

	log.info("cleaning up futon")

}


@(export)
futon_update :: proc() {

	log.info("updating futon")
}
