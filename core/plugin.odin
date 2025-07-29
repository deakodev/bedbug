package core

Layer :: struct {
	using symbols: ^DynlibSymbols,
	type:          typeid,
	self:          rawptr,
}

Plugin :: struct($T: typeid) {
	libs:   [T]Dynlib,
	layers: [T]Layer,
}