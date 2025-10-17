package meta

// import "core:ast"

PluginAttributeOpaque :: "opaque"

// #partial switch &ed in e.derived {
// 						case ^ast.Field_Value:
// 							if name_ident, name_ident_ok := ed.field.derived.(^ast.Ident); name_ident_ok {
// 								name = name_ident.name
// 							}

// 							if value_lit, value_lit_ok := ed.value.derived.(^ast.Basic_Lit); value_lit_ok {
// 								value = strings.trim(value_lit.tok.text, "\"")
// 							}
// 						case ^ast.Ident:
// 							name = ed.name
// 						}
