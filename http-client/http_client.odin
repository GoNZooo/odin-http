package http_client

import "core:bytes"
import "core:crypto"
import "core:encoding/base64"
import "core:fmt"
import "core:io"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:net"
import "core:os"

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
	host := http.host_from_url(address)
	headers := map[string]string {
		"Host"                  = host,
		"Upgrade"               = "websocket",
		"Connection"            = "Upgrade",
		"Sec-WebSocket-Version" = "13",
		"Sec-WebSocket-Key"     = key,
	}

	response, socket, get_error := get(address, headers)
	if get_error != nil {
		fmt.printf("Error when GETing '%s': %v\n", address, get_error)

		os.exit(1)
	}

	fmt.printf("Headers: %#v\n", headers)
	fmt.printf("Response: %#v\n", response)

	recv_buffer := make([]byte, 256 * mem.Megabyte)
	fragment_serialization_buffer: [128 * mem.Kilobyte]byte
	for {
		log.debugf("receiving...")
		bytes_received, recv_error := net.recv_tcp(socket, recv_buffer[:])
		if recv_error != nil {
			fmt.printf("Error when receiving: %v\n", recv_error)

			os.exit(1)
		}
		log.debugf("bytes_received: %d\n", bytes_received)

		frame, remaining_data, frame_parse_error := http.parse_websocket_fragment(recv_buffer[:])
		if frame_parse_error != nil {
			fmt.printf("Error when parsing frame: %v\n", frame_parse_error)

			os.exit(1)
		}

		#partial switch f in frame.data {
		case http.Ping_Data:
			fmt.printf("Received ping, sending pong\n")
			mask_key: [4]byte
			crypto.rand_bytes(mask_key[:])

			// log.debugf("first 4 bytes in payload: '%02x'", f.payload[:4])
			// for &b in f.payload {
			// 	b = 0
			// }
			// log.debugf("first 4 bytes in payload: '%02x'", f.payload[:4])
			pong_fragment := http.Websocket_Fragment {
				data = http.Pong_Data{payload = f.payload},
				final = true,
				mask = true,
				mask_key = mask_key,
			}
			serialized_data, serialize_error := http.serialize_websocket_fragment(
				fragment_serialization_buffer[:],
				pong_fragment,
			)
			if serialize_error != nil {
				fmt.printf("Error when sending pong: %v\n", serialize_error)

				os.exit(1)
			}

			log.debugf("serialized_data: '%02x'", serialized_data)
			sent_bytes, send_error := net.send_tcp(socket, serialized_data)
			if send_error != nil {
				fmt.printf("Error when sending pong: %v\n", send_error)

				os.exit(1)
			}
			log.debugf("sent_bytes=%d", sent_bytes)
			assert(
				sent_bytes == len(serialized_data),
				fmt.tprintf(
					"sent_bytes: %d, len(serialized_data): %d\n",
					sent_bytes,
					len(serialized_data),
				),
			)
		case:
		// do nothing
		}

		log.debugf("len(remaining_data): %d\n", len(remaining_data))

		fmt.printf("frame.final=%v\n", frame.final)
		switch f in frame.data {
		case http.Continuation_Data:
			fmt.printf("Continuation frame payload length: %d\n", len(f.payload))
		case http.Text_Data:
			fmt.printf("Text frame payload length: %d\n", len(f.payload))
		case http.Binary_Data:
			fmt.printf("Binary frame payload length: %d\n", len(f.payload))
		case http.Close_Data:
			fmt.printf("Close frame payload: '%s'\n", f.payload)
		case http.Ping_Data:
			fmt.printf("Ping frame payload: '%s'\n", f.payload)
		case http.Pong_Data:
			fmt.printf("Pong frame payload: '%s'\n", f.payload)
		}
	}
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
	socket: net.TCP_Socket,
	error: Get_Error,
) {
	b: bytes.Buffer
	bytes.buffer_init_allocator(&b, 0, 0, allocator)

	path := http.path_from_url(url)

	bytes.buffer_write_string(&b, "GET ") or_return
	bytes.buffer_write_string(&b, path) or_return
	bytes.buffer_write_string(&b, " HTTP/1.1\r\n") or_return
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
	socket = net.dial_tcp(endpoint) or_return

	net.send_tcp(socket, send_buffer) or_return

	recv_buffer: [64 * mem.Kilobyte]byte
	bytes_received, recv_error := net.recv_tcp(socket, recv_buffer[:])
	if recv_error != nil {
		return http.Response{}, socket, recv_error
	}

	response = http.parse_response(recv_buffer[:bytes_received], allocator) or_return

	return response, socket, nil
}
