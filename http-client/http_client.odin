package http_client

import "core:bytes"
import "core:encoding/base64"
import "core:fmt"
import "core:io"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:net"
import "core:os"
import "core:time"

import "../http"

main :: proc() {
	arguments := os.args
	if len(arguments) < 2 {
		fmt.printf("Usage: %s <address>\n", arguments[0])

		os.exit(1)
	}

	context.logger = log.create_console_logger()

	address := arguments[1]

	key_bytes: [16]byte
	bytes_filled := rand.read(key_bytes[:])
	assert(bytes_filled == len(key_bytes))
	key := base64.encode(key_bytes[:])
	headers := map[string]string {
		"Host"                  = address,
		"Upgrade"               = "websocket",
		"Connection"            = "Upgrade",
		"Sec-WebSocket-Version" = "13",
		"Sec-WebSocket-Key"     = key,
	}

	response, get_error := get(address, headers)
	if get_error != nil {
		fmt.printf("Error when GETing '%s': %v\n", address, get_error)

		os.exit(1)
	}

	fmt.printf("Response:\n")
	for k, v in response.headers {
		fmt.printf("%s: %s\n", k, v)
	}

	for {
		time.sleep(5 * time.Second)
	}

	// net.close(socket)
}

Get_Error :: union {
	io.Error,
	net.Network_Error,
	mem.Allocator_Error,
	http.Parse_Response_Error,
}

get :: proc(
	url: string,
	headers: map[string]string,
	allocator := context.allocator,
) -> (
	response: http.Response,
	error: Get_Error,
) {
	b: bytes.Buffer
	bytes.buffer_init_allocator(&b, 0, 0, allocator)

	bytes.buffer_write_string(&b, "GET / HTTP/1.1\r\n") or_return
	host_header_exists := false
	host := http.host_from_url(url)
	for key, value in headers {
		if key == "Host" {
			host_header_exists = true
		}
		bytes.buffer_write_string(&b, key) or_return
		bytes.buffer_write_string(&b, ": ") or_return
		bytes.buffer_write_string(&b, value) or_return
		bytes.buffer_write_string(&b, "\r\n") or_return
	}
	if !host_header_exists {
		bytes.buffer_write_string(&b, "Host: ") or_return
		bytes.buffer_write_string(&b, host) or_return
		bytes.buffer_write_string(&b, "\r\n") or_return
	}
	bytes.buffer_write_string(&b, "\r\n") or_return

	send_buffer := bytes.buffer_to_bytes(&b)
	defer delete(send_buffer)

	endpoint := net.resolve_ip4(host) or_return
	socket := net.dial_tcp(endpoint) or_return

	net.send_tcp(socket, send_buffer) or_return

	recv_buffer: [64 * mem.Kilobyte]byte
	bytes_received, recv_error := net.recv_tcp(socket, recv_buffer[:])
	if recv_error != nil {
		return http.Response{}, recv_error
	}

	response = http.parse_response(recv_buffer[:bytes_received], allocator) or_return

	return response, nil
}
