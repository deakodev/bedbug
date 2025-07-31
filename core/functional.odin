package core

import sa "core:container/small_array"
import "core:log"

transform :: proc {
	transform_reference,
	transform_copy,
}

transform_reference :: proc(a: ^$A/sa.Small_Array($N, $T), f: proc(x: T) -> T) #no_bounds_check {

	for i in 0 ..< a.len {
		a.data[i] = f(a.data[i])
	}
}

transform_copy :: proc(
	a: $A/sa.Small_Array($N, $T),
	f: proc(x: T) -> $U,
) -> (
	r: sa.Small_Array(N, U),
) #no_bounds_check {

	r.len = a.len
	for i in 0 ..< a.len {
		r.data[i] = f(a.data[i])
	}
	return
}

reduce :: proc(a: ^$A/sa.Small_Array($N, $T), f: proc(acc: T, x: T) -> T) -> (acc: T) #no_bounds_check {

	acc = a.data[0]
	for i in 1 ..< a.len {
		acc = f(acc, a.data[i])
	}
	return
}

// a := sa.Small_Array(3, int){}
// 	sa.append(&a, 1, 2, 3)

// 	bb.transform(&a, proc(x: int) -> int {return x * 2})

// 	log.debug(a)

// 	b := bb.transform(a, proc(x: int) -> int {return x * 2})

// 	log.debug(b)

// 	c := bb.reduce(&b, proc(acc: int, x: int) -> int {return acc + x})

// 	log.debug(c)
