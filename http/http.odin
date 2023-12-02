package http

import "core:log"
import "core:strings"
import "core:testing"

host_from_url :: proc(url: string) -> (host: string) {
	url := url
	protocol_index := strings.index(url, "://")

	if protocol_index == -1 {
		protocol_index = -3
	}

	after_protocol := url[protocol_index + 3:]

	slash_index := strings.index(after_protocol, "/")
	if slash_index == -1 {
		return after_protocol
	}

	return after_protocol[:slash_index]
}

@(test, private = "package")
test_host_from_url :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	cases := map[string]string {
		"http://google.com/"                 = "google.com",
		"http://google.com"                  = "google.com",
		"http://google.com:8080"             = "google.com:8080",
		"http://google.com:8080/hello"       = "google.com:8080",
		"http://google.com:8080/hello/world" = "google.com:8080",
		"google.com"                         = "google.com",
		"google.com:8080"                    = "google.com:8080",
		"google.com/hello"                   = "google.com",
		"127.0.0.1:4200/ws"                  = "127.0.0.1:4200",
	}

	for input, expected in cases {
		host := host_from_url(input)
		testing.expect_value(t, host, expected)
	}
}

path_from_url :: proc(url: string) -> (path: string) {
	url := url
	protocol_index := strings.index(url, "://")

	if protocol_index == -1 {
		protocol_index = -3
	}

	after_protocol := url[protocol_index + 3:]

	slash_index := strings.index(after_protocol, "/")
	if slash_index == -1 {
		return "/"
	}

	return after_protocol[slash_index:]
}

@(test, private = "package")
test_path_from_url :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	cases := map[string]string {
		"http://google.com/"                 = "/",
		"http://google.com"                  = "/",
		"http://google.com:8080"             = "/",
		"http://google.com:8080/hello"       = "/hello",
		"http://google.com:8080/hello/world" = "/hello/world",
		"google.com"                         = "/",
		"google.com:8080"                    = "/",
		"google.com/hello"                   = "/hello",
	}

	for input, expected in cases {
		path := path_from_url(input)
		testing.expect_value(t, path, expected)
	}
}
