package core

Module :: struct {
	using symbols: ^DynlibSymbols,
	type:          typeid,
	self:          rawptr,
}

Plugin :: struct($T: typeid) {
	libs:    [T]Dynlib,
	modules: [T]Module,
	client:  T,
}
