package http_client

import "core:fmt"
import "core:log"
import "core:runtime"
import "core:strings"
import "core:testing"

// NOTE(gonz): Making the assumption that 32 kB for headers "is enough for everyone" for now

MAX_HEADERS_LENGTH :: 32 * 1024

HeaderParsingError :: union {
	HeadersTooLong,
	ExpectedHeaderNameToEnd,
	ExpectedHeaderValueToEnd,
	runtime.Allocator_Error,
}

HeadersTooLong :: struct {
	length: int,
}

ExpectedHeaderNameToEnd :: struct {
	data: string,
}

ExpectedHeaderValueToEnd :: struct {
	name: string,
	data: string,
}

parse_headers :: proc(
	data: string,
	allocator := context.allocator,
) -> (
	headers: map[string]string,
	error: HeaderParsingError,
) {
	length := len(data)
	if length > MAX_HEADERS_LENGTH {
		return nil, HeadersTooLong{length = length}
	}
	headers = make(map[string]string, 0, allocator)

	tokenizer := tokenizer_create(data)
	for {
		current_token := tokenizer_peek(&tokenizer)
		_, is_newline := current_token.(Newline)
		if is_newline {
			break
		}
		header_name, end_marker_error := tokenizer_read_string_until(&tokenizer, []string{":"})
		if end_marker_error != nil {
			return nil, ExpectedHeaderNameToEnd{data = tokenizer.source[tokenizer.position:]}
		}
		header_value_builder: strings.Builder
		strings.builder_init_none(&header_value_builder, allocator) or_return

		tokenizer_expect_exact(&tokenizer, Colon{})
		tokenizer_skip_any_of(&tokenizer, {Space{}, Tab{}})

		done_reading_header_value := false
		for !done_reading_header_value {
			// TODO(rickard): Here we want to read a string until we hit CRLF, but if we read whitespace
			// immediately after the CRLF we should add the content following that whitespace to the
			// header value
			value_string, read_until_error := tokenizer_read_string_until(
				&tokenizer,
				[]string{"\r\n"},
			)
			if read_until_error != nil {
				return nil, ExpectedHeaderValueToEnd{name = header_name, data = data}
			}
			tokenizer_skip_string(&tokenizer, "\r\n")

			strings.write_string(&header_value_builder, value_string)
			token := tokenizer_peek(&tokenizer)
			#partial switch t in token {
			case Space, Tab:
				tokenizer_skip_any_of(&tokenizer, {Space{}, Tab{}})
				strings.write_byte(&header_value_builder, '\n')
			case:
				done_reading_header_value = true
			}
		}

		header_value := strings.to_string(header_value_builder)
		headers[header_name] = header_value
	}

	return headers, nil
}

@(private = "package")
@(test)
test_normal_single_header_value :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	d := "Content-Type: text/html\r\n\r\n"
	headers, error := parse_headers(d)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, headers["Content-Type"], "text/html")
}

@(private = "package")
@(test)
test_multiline_single_header_and_normal_value :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	d := "X-Multiline-Weird-Header: start of value\r\n end of value\r\nContent-Type: text/html\r\n\r\n"
	headers, error := parse_headers(d)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, headers["Content-Type"], "text/html")
	testing.expect_value(t, headers["X-Multiline-Weird-Header"], "start of value\nend of value")
}

@(private = "package")
@(test)
test_headers_too_long :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	d := strings.repeat("a", MAX_HEADERS_LENGTH + 1)
	headers, error := parse_headers(d)
	testing.expect_value(t, error, HeadersTooLong{length = MAX_HEADERS_LENGTH + 1})
	testing.expect(t, headers == nil, fmt.tprintf("headers == nil: %v", headers == nil))
}

@(private = "package")
@(test)
test_example_headers_1 :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	d := strings.concatenate(
		{
			strings.join(
				[]string{
					"CF-Cache-Status: HIT",
					"CF-RAY: 808909585be53dc0-SOF",
					"Cache-Control: public, max-age=14400",
					"Connection: keep-alive",
					"Content-Encoding: gzip",
					"Content-Type: text/html; charset=utf-8",
					"Date: Mon, 18 Sep 2023 10:51:55 GMT",
					"Expires: Mon, 18 Sep 2023 14:51:55 GMT",
					"Server: cloudflare",
					"Transfer-Encoding: chunked",
					"alt-svc: h3=\":443\"; ma=86400",
					"content-security-policy: default-src 'self' 'unsafe-inline' data: https://datatracker.ietf.org/ https://www.ietf.org/ http://ietf.org/ https://analytics.ietf.org https://static.ietf.org; frame-ancestors 'self' ietf.org *.ietf.org meetecho.com *.meetecho.com",
					"cross-origin-opener-policy: unsafe-none",
					"referrer-policy: strict-origin-when-cross-origin",
					"strict-transport-security: max-age=3600; includeSubDomains",
					"vary: Cookie, Accept-Encoding",
					"x-content-type-options: nosniff",
					"x-frame-options: SAMEORIGIN",
				},
				"\r\n",
			),
			"\r\n\r\n",
		},
	)
	headers, error := parse_headers(d)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, headers["CF-Cache-Status"], "HIT")
	testing.expect_value(t, headers["CF-RAY"], "808909585be53dc0-SOF")
	testing.expect_value(t, headers["Cache-Control"], "public, max-age=14400")
	testing.expect_value(t, headers["Connection"], "keep-alive")
	testing.expect_value(t, headers["Content-Encoding"], "gzip")
	testing.expect_value(t, headers["Content-Type"], "text/html; charset=utf-8")
	testing.expect_value(t, headers["Date"], "Mon, 18 Sep 2023 10:51:55 GMT")
	testing.expect_value(t, headers["Expires"], "Mon, 18 Sep 2023 14:51:55 GMT")
	testing.expect_value(t, headers["Server"], "cloudflare")
	testing.expect_value(t, headers["Transfer-Encoding"], "chunked")
	testing.expect_value(t, headers["alt-svc"], "h3=\":443\"; ma=86400")
	testing.expect_value(
		t,
		headers["content-security-policy"],
		"default-src 'self' 'unsafe-inline' data: https://datatracker.ietf.org/ https://www.ietf.org/ http://ietf.org/ https://analytics.ietf.org https://static.ietf.org; frame-ancestors 'self' ietf.org *.ietf.org meetecho.com *.meetecho.com",
	)
	testing.expect_value(t, headers["cross-origin-opener-policy"], "unsafe-none")
	testing.expect_value(t, headers["referrer-policy"], "strict-origin-when-cross-origin")
	testing.expect_value(
		t,
		headers["strict-transport-security"],
		"max-age=3600; includeSubDomains",
	)
	testing.expect_value(t, headers["vary"], "Cookie, Accept-Encoding")
	testing.expect_value(t, headers["x-content-type-options"], "nosniff")
	testing.expect_value(t, headers["x-frame-options"], "SAMEORIGIN")
}
