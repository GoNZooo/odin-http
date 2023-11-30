package tokenization

import "core:log"
import "core:strings"
import "core:testing"

prefix_matches :: proc(s: string, prefix: string) -> bool {
	return strings.has_prefix(s, prefix)
}

read_until :: proc(s: string, characters: string) -> string {
	character_index := strings.index_any(s, characters)
	if character_index == -1 {
		return s
	}

	v := s[:character_index]

	return v
}

@(test)
test_read_until :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	testing.expect_value(t, read_until("hello", "e"), "h")
	testing.expect_value(t, read_until("hello there", " "), "hello")
	testing.expect_value(t, read_until("there", " "), "there")
}
