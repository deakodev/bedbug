package bedbug_runtime

import bc "bedbug:core"
import br "bedbug:layers/renderer"
import bs "bedbug:layers/scene"

logger_setup :: bc.logger_setup
allocator_tracking_setup :: bc.allocator_tracking_setup
allocator_tracking_cleanup :: bc.allocator_tracking_cleanup
allocator_tracking_check :: bc.allocator_tracking_check
bytes_formated_string :: bc.bytes_formated_string

Scene :: bs.Scene
scene_setup :: bs.setup
scene_cleanup :: bs.cleanup
entity_create :: bs.entity_create
scene_json_write :: bs.scene_json_write
