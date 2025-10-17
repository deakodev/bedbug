package meta

import "bedbug:core"

import "core:fmt"
import "core:log"
import vmem "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

META_DIR :: #config(META_DIR, "_meta")
PACKAGE_DIR :: #config(PACKAGE_DIR, ".")
META_PACKAGE_DIR :: META_DIR + "/" + PACKAGE_DIR

main :: proc() {

	meta_setup()

	package_ast, ok := parser.parse_package_from_path(PACKAGE_DIR)
	log.ensuref(ok, "Failed to parse package: %v", package_ast.name)

	// meta_package_file_make()

	// for &package_fi in package_fis {


	// 	package_dest_dir := fmt.tprintf("%v/%v", DEST_DIR, package_fi.name)
	// 	if !os.exists(package_dest_dir) {
	// 		err := os.make_directory(package_dest_dir)
	// 		log.ensuref(err == os.ERROR_NONE, "Could not create package_dest_dir: %v", err)
	// 	}

	// 	package_ast, ok := parser.parse_package_from_path(package_fi.fullpath)
	// 	log.ensuref(ok, "Failed to parse package: %v", package_fi.name)

	// 	layer_file, err := os.open(
	// 		fmt.tprintf("%v/%v.meta.odin", package_dest_dir, package_fi.name),
	// 		os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
	// 		0o644,
	// 	)
	// 	log.ensuref(err == os.ERROR_NONE, "Failed to open layer output file: %v", package_fi.name)

	// 	fmt.fprintfln(layer_file, "/* WARNING: this file is regenerated on each compilation. */")
	// 	fmt.fprintfln(layer_file, "package %v\n", package_ast.name)

	// 	log.infof("%#v", package_ast)

	// 	for _, file in package_ast.files {

	// 		for &decl in file.decls {
	// 			log.infof("%#v", decl)
	// 			#partial switch &decl_derived in decl.derived {
	// 			case ^ast.Value_Decl:
	// 			// 		add_to_api: bool
	// 			// 		add_to_api_opaque: bool
	// 			// 		add_to_api_name: string

	// 			// 		for &attr in decl_derived.attributes {
	// 			// 			for &elem in attr.elems {
	// 			// 				name: string
	// 			// 				value: string

	// 			// 				#partial switch &elem_derived in elem.derived {
	// 			// 				case ^ast.Field_Value:
	// 			// 					if name_ident, name_ident_ok := elem_derived.field.derived.(^ast.Ident);
	// 			// 					   name_ident_ok {
	// 			// 						name = name_ident.name
	// 			// 					}

	// 			// 					if value_lit, value_lit_ok := elem_derived.value.derived.(^ast.Basic_Lit);
	// 			// 					   value_lit_ok {
	// 			// 						value = strings.trim(value_lit.tok.text, "\"")
	// 			// 					}
	// 			// 				case ^ast.Ident:
	// 			// 					name = elem_derived.name
	// 			// 				}

	// 			// 				switch name {
	// 			// 				case "api":
	// 			// 					add_to_api = true
	// 			// 					add_to_api_name = value
	// 			// 				case "api_opaque":
	// 			// 					add_to_api = true
	// 			// 					add_to_api_opaque = true
	// 			// 				}
	// 			// 			}
	// 			// 		}
	// 			// 		if add_to_api {
	// 			// 			if add_to_api_opaque {
	// 			// 				for n in dd.names {
	// 			// 					name := f.src[n.pos.offset:n.end.offset]
	// 			// 					append(&types, fmt.tprintf("%v :: struct{{}}", name))
	// 			// 				}
	// 			// 			} else {
	// 			// 				// The API name is only used for procedures. It's the struct in which the procedure
	// 			// 				// pointers end up.
	// 			// 				api_name := add_to_api_name

	// 			// 				if api_name == "" {
	// 			// 					api_name = default_api_name
	// 			// 				}

	// 			// 				api := &apis[api_name]

	// 			// 				if api == nil {
	// 			// 					apis[api_name] = API{}
	// 			// 					api = &apis[api_name]
	// 			// 				}

	// 			// 				processed := false

	// 			// 				for v, vi in dd.values {
	// 			// 					#partial switch vd in v.derived {
	// 			// 					case ^ast.Proc_Lit:
	// 			// 						name := f.src[dd.names[vi].pos.offset:dd.names[vi].end.offset]
	// 			// 						type := f.src[vd.type.pos.offset:vd.type.end.offset]
	// 			// 						docs := dd.docs == nil ? "" : f.src[dd.docs.pos.offset:dd.docs.end.offset]
	// 			// 						append(&api.entries, API_Entry{name = name, type = type, docs = docs})
	// 			// 						processed = true
	// 			// 					}
	// 			// 				}

	// 			// 				if !processed {
	// 			// 					type := f.src[dd.pos.offset:dd.end.offset]
	// 			// 					append(&types, type)
	// 			// 				}
	// 			// 			}
	// 			// 		}
	// 			// 	}

	// 			}
	// 		}
	// 	}
	// }
}

meta_setup :: proc() {

	context.logger = log.create_console_logger()

	for dir in strings.split(META_PACKAGE_DIR, "/") {
		os.make_directory(dir)
		current_dir := filepath.join({os.get_current_directory(), dir})
		os.set_current_directory(current_dir)
	}
}

package_read :: proc(path: string) -> (fis: []os.File_Info) {

	dir, err := os.open(path)
	defer os.close(dir)
	log.ensuref(err == os.ERROR_NONE, "Failed to open dir: %v", path)

	fis, err = os.read_dir(dir, -1) // -1 to read all items
	log.ensuref(err == os.ERROR_NONE, "Failed to read dir: %v", path)

	return slice.filter(fis, proc(fi: os.File_Info) -> bool {return !fi.is_dir})
}
