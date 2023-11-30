package http

import "core:fmt"
import "core:log"
import "core:mem"
import "core:runtime"
import "core:strconv"
import "core:strings"
import "core:testing"

// NOTE(gonz): Making the assumption that 32 kB for headers "ough to be enough for anybody" for now

MAX_HEADERS_LENGTH :: 32 * 1024

Header_Parsing_Error :: union {
	Headers_Too_Long,
	Expected_Header_Name_End,
	Expected_Header_Value_End,
	runtime.Allocator_Error,
}

Headers_Too_Long :: struct {
	length: int,
}

Expected_Header_Name_End :: struct {
	data: string,
}

Expected_Header_Value_End :: struct {
	name: string,
	data: string,
}

Parse_Request_Error :: union {
	mem.Allocator_Error,
	Expectation_Error,
	Response_Line_Parsing_Error,
	Header_Parsing_Error,
}

Parse_Response_Error :: union {
	mem.Allocator_Error,
	Expectation_Error,
	Response_Line_Parsing_Error,
	Header_Parsing_Error,
}

Response_Line_Parsing_Error :: union {
	Invalid_Protocol,
	Invalid_Status,
}

Invalid_Protocol :: struct {
	protocol: string,
}

Invalid_Status :: struct {
	status: string,
}

Request :: struct {
	method:   Method,
	path:     string,
	protocol: string,
	headers:  map[string]string,
}

Response :: struct {
	protocol: string,
	status:   int,
	message:  string,
	headers:  map[string]string,
	body:     []byte,
}

Method :: union {
	GET,
	POST,
}

GET :: struct {}
POST :: struct {
	data: []byte,
}

parse_request :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	m: Request,
	error: Parse_Request_Error,
) {
	data_string := strings.clone_from_bytes(data, allocator) or_return
	tokenizer := tokenizer_create(data_string)
	t := tokenizer_expect(&tokenizer, Upper_Symbol{}) or_return
	if t.token.(Upper_Symbol).value != "GET" {
		error = Expectation_Error(
			Expected_Token{
				expected = Upper_Symbol{value = "GET"},
				actual = t.token,
				location = t.location,
			},
		)

		return Request{}, error
	}

	tokenizer_skip_any_of(&tokenizer, {Space{}})

	m.method = GET{}
	m.path = tokenizer_read_string_until(&tokenizer, []string{" "}) or_return
	m.protocol = tokenizer_read_string_until(&tokenizer, []string{"\r\n"}) or_return
	m.headers = parse_headers(tokenizer.source[tokenizer.position:], allocator) or_return

	return m, nil
}

parse_response :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	m: Response,
	error: Parse_Response_Error,
) {
	data_string := strings.clone_from_bytes(data, allocator) or_return
	tokenizer := tokenizer_create(data_string)
	m.protocol = tokenizer_read_string_until(&tokenizer, []string{" "}) or_return
	tokenizer_skip_any_of(&tokenizer, {Space{}})
	status_string := tokenizer_read_string_until(&tokenizer, []string{" "}) or_return
	status, status_parse_ok := strconv.parse_int(status_string)
	if !status_parse_ok {
		return Response{}, Response_Line_Parsing_Error(Invalid_Status{status = status_string})
	}
	m.status = status
	m.message = tokenizer_read_string_until(&tokenizer, []string{"\r\n"}) or_return
	m.headers = parse_headers(tokenizer.source[tokenizer.position:], allocator) or_return

	return m, nil
}

parse_headers :: proc(
	data: string,
	allocator := context.allocator,
) -> (
	headers: map[string]string,
	error: Header_Parsing_Error,
) {
	length := len(data)
	if length > MAX_HEADERS_LENGTH {
		return nil, Headers_Too_Long{length = length}
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
			return nil, Expected_Header_Name_End{data = tokenizer.source[tokenizer.position:]}
		}
		header_value_builder: strings.Builder
		strings.builder_init_none(&header_value_builder, allocator) or_return

		tokenizer_expect_exact(&tokenizer, Colon{})
		tokenizer_skip_any_of(&tokenizer, {Space{}, Tab{}})

		done_reading_header_value := false
		for !done_reading_header_value {
			value_string, read_until_error := tokenizer_read_string_until(
				&tokenizer,
				[]string{"\r\n"},
			)
			if read_until_error != nil {
				return nil, Expected_Header_Value_End{name = header_name, data = data}
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
	testing.expect_value(t, error, Headers_Too_Long{length = MAX_HEADERS_LENGTH + 1})
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

@(private = "package")
@(test)
test_expires_negative_number :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	d := "Expires: -1\r\n\r\n"
	headers, error := parse_headers(d)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, headers["Expires"], "-1")
}