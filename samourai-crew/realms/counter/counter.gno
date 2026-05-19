package counter

import "strconv"

var count int

func Increment() { count++ }

func Render(_ string) string {
	return strconv.Itoa(count)
}
