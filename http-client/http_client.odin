package http_client

import "core:bytes"
import "core:encoding/base64"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:net"
import "core:os"

main :: proc() {
	arguments := os.args
	if len(arguments) < 2 {
		fmt.printf("Usage: %s <address>\n", arguments[0])

		os.exit(1)
	}

	context.logger = log.create_console_logger()

	address := arguments[1]

	ip4_endpoint, resolve_error := net.resolve_ip4(address)
	if resolve_error != nil {
		fmt.printf("Error when resolving: %v\n", resolve_error)

		os.exit(1)
	}

	socket, dial_error := net.dial_tcp(ip4_endpoint)
	if dial_error != nil {
		fmt.printf("Error when dialing: %v\n", dial_error)

		os.exit(1)
	}

	key_bytes: [16]byte
	bytes_filled := rand.read(key_bytes[:])
	assert(bytes_filled == len(key_bytes))
	key := base64.encode(key_bytes[:])
	_send_buffer: [128 * mem.Kilobyte]byte
	send_buffer: bytes.Buffer
	bytes.buffer_init(&send_buffer, _send_buffer[:])
	bytes.buffer_init_allocator(&send_buffer, 0, 64 * mem.Kilobyte)
	bytes.buffer_write_string(&send_buffer, "GET / HTTP/1.1\r\n")
	bytes.buffer_write_string(&send_buffer, "Host: ")
	bytes.buffer_write_string(&send_buffer, address)
	bytes.buffer_write_string(&send_buffer, "\r\n")
	bytes.buffer_write_string(&send_buffer, "Upgrade: websocket\r\n")
	bytes.buffer_write_string(&send_buffer, "Connection: Upgrade\r\n")
	bytes.buffer_write_string(&send_buffer, "Sec-WebSocket-Version: 13\r\n")
	bytes.buffer_write_string(&send_buffer, "Sec-WebSocket-Key: ")
	bytes.buffer_write_string(&send_buffer, key)
	bytes.buffer_write_string(&send_buffer, "\r\n")
	bytes.buffer_write_string(&send_buffer, "\r\n")
	send_slice := bytes.buffer_to_bytes(&send_buffer)
	log.debugf("send_slice (%d):\n'''\n%s\n'''", len(send_slice), send_slice)
	bytes_sent, write_error := net.send_tcp(socket, send_slice)
	if write_error != nil {
		fmt.printf("Error when writing: %v\n", write_error)

		os.exit(1)
	}
	log.debugf("Sent %d bytes\n", bytes_sent)

	receive_buffer: [64 * mem.Kilobyte]byte
	bytes_received, read_error := net.recv_tcp(socket, receive_buffer[:])
	if read_error != nil {
		fmt.printf("Error when reading: %v\n", read_error)

		os.exit(1)
	}

	read_slice := receive_buffer[:bytes_received]
	fmt.printf("Received %d bytes:\n'''\n%s\n'''\n", bytes_received, read_slice)

	message, parse_error := parse_message(read_slice)
	if parse_error != nil {
		fmt.printf("Error when parsing response: %v\n", parse_error)

		os.exit(1)
	}
	for k, v in message.headers {
		fmt.printf("Header\t%s: %s\n", k, v)
	}

	// net.close(socket)
}
