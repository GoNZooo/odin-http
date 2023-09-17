package http_client

import "core:strings"
import "core:testing"

// NOTE(gonz): Making the assumption that 32 kB for headers "is enough for everyone" for now

MAX_HEADERS_LENGTH :: 32 * 1024

HeaderParsingError :: union {
	HeadersTooLong,
}

HeadersTooLong :: struct {
	length: int,
}

parse_headers :: proc(data: string) -> (headers: map[string]string, error: HeaderParsingError) {
	length := len(data)
	if length > MAX_HEADERS_LENGTH {
		return nil, HeadersTooLong{length = length}
	}

	return
}

@(private = "package")
@(test)
test_headers_too_long :: proc(t: ^testing.T) {
	d := strings.repeat("a", MAX_HEADERS_LENGTH + 1)
	_, error := parse_headers(d)
	testing.expect_value(t, error, HeadersTooLong{length = MAX_HEADERS_LENGTH + 1})
}
