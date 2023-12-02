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
	bytes_received, recv_error := net.recv_tcp(socket, recv_buffer[:])
	if recv_error != nil {
		fmt.printf("Error when receiving: %v\n", recv_error)

		os.exit(1)
	}
	log.debugf("bytes_received: %d\n", bytes_received)

	frame, frame_parse_error := parse_websocket_fragment(recv_buffer[:])
	if frame_parse_error != nil {
		fmt.printf("Error when parsing frame: %v\n", frame_parse_error)

		os.exit(1)
	}

	fmt.printf("frame.final=%v\n", frame.final)
	switch f in frame.data {
	case Continuation_Data:
		fmt.printf("Continuation frame payload length: %d\n", len(f.payload))
	case Text_Data:
		fmt.printf("Text frame payload length: %d\n", len(f.payload))
	case Binary_Data:
		fmt.printf("Binary frame payload length: %d\n", len(f.payload))
	case Close_Data:
		fmt.printf("Close frame payload: '%s'\n", f.payload)
	case Ping_Data:
		fmt.printf("Ping frame payload: '%s'\n", f.payload)
	case Pong_Data:
		fmt.printf("Pong frame payload: '%s'\n", f.payload)
	}

}

Websocket_Fragment :: struct {
	data:  Websocket_Fragment_Data,
	final: bool,
}

Websocket_Fragment_Data :: union {
	Continuation_Data,
	Text_Data,
	Binary_Data,
	Close_Data,
	Ping_Data,
	Pong_Data,
}

Continuation_Data :: struct {
	payload: []byte,
}

Text_Data :: struct {
	payload: []byte,
}

Binary_Data :: struct {
	payload: []byte,
}

Close_Data :: struct {
	payload: []byte,
}

Ping_Data :: struct {
	payload: []byte,
}

Pong_Data :: struct {
	payload: []byte,
}

Websocket_Parse_Error :: union {
	Invalid_Opcode,
}

Invalid_Opcode :: struct {
	opcode: u8,
}

parse_websocket_fragment :: proc(
	data: []byte,
) -> (
	frame: Websocket_Fragment,
	error: Websocket_Parse_Error,
) {
	i: int
	first_byte := data[0]
	fin := (first_byte & 0x80) != 0
	frame.final = fin
	opcode := first_byte & 0x0f
	i += 1

	second_byte := data[1]
	mask := (second_byte & 0x80) != 0
	payload_length: u64 = u64(second_byte) & 0x7f
	log.debugf("initial length: %d\n", payload_length)
	i += 1
	if payload_length == 126 {
		payload_length_bytes := [2]byte{data[i], data[i + 1]}
		payload_length = u64(transmute(u16be)payload_length_bytes)
		log.debugf("16 bit payload length: %d\n", payload_length)
		i += 2
	} else if payload_length == 127 {
		payload_length_bytes := [8]byte {
			data[i],
			data[i + 1],
			data[i + 2],
			data[i + 3],
			data[i + 4],
			data[i + 5],
			data[i + 6],
			data[i + 7],
		}
		payload_length = u64(transmute(u64be)payload_length_bytes)
		log.debugf("64 bit payload length: %d\n", payload_length)
		i += 8
	}
	log.debugf("payload_length: %d\n", payload_length)

	if mask {
		mask_key := data[i:i + 4]
		i += 4
		for j := u64(0); j < payload_length; j += 1 {
			data[i + int(j)] = mask_key[j % 4]
		}
	}

	payload := data[i:i + int(payload_length)]

	switch opcode {
	case 0x02:
		frame.data = Binary_Data {
			payload = payload,
		}

		return frame, nil
	case 0x09:
		frame.data = Ping_Data {
			payload = payload,
		}
		return frame, nil
	case:
		return Websocket_Fragment{}, Invalid_Opcode{opcode = opcode}
	}

	return frame, nil
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
