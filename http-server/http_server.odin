package http_server

import "core:bytes"
import "core:fmt"
import "core:log"
import "core:net"
import "core:os"
import "core:strconv"

import client "../http-client"

User :: struct {
	name: string,
	age:  byte,
}

main :: proc() {
	context.logger = log.create_console_logger()

	if len(os.args) < 2 {
		fmt.printf("Usage: %s <port>\n", os.args[0])

		os.exit(1)
	}

	port, port_ok := strconv.parse_u64_of_base(os.args[1], 10)
	if !port_ok {
		fmt.printf("Invalid port number: %s\n", os.args[1])

		os.exit(1)
	}

	log.debugf("Starting server on port %d", port)

	endpoint, endpoint_parse_ok := net.parse_endpoint("127.0.0.1")
	if !endpoint_parse_ok {
		log.errorf("Failed to parse endpoint")

		os.exit(1)
	}
	endpoint.port = int(port)

	listen_socket, listen_error := net.listen_tcp(endpoint)
	if listen_error != nil {
		log.errorf("Failed to listen on %v: %v", endpoint, listen_error)

		os.exit(1)
	}

	b: bytes.Buffer
	bytes.buffer_init_allocator(&b, 0, 2048)
	bytes.buffer_write_string(&b, "HTTP/1.1 200 OK\r\n")
	bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
	bytes.buffer_write_string(&b, "\r\n")
	bytes.buffer_write_string(&b, "<html><body><h1>Hello, world!</h1></body></html>\r\n")
	welcome_message := bytes.buffer_to_bytes(&b)

	recv_buffer: [4096]byte
	for {
		client_socket, _, accept_error := net.accept_tcp(listen_socket)
		if accept_error != nil {
			log.errorf("Failed to accept connection: %v", accept_error)

			continue
		}
		defer net.close(client_socket)

		has_double_newlines :: proc(data: []byte) -> bool {
			last_4 := data[len(data) - 4:]
			log.debugf(
				"last_4: %#02x, %#02x, %02x, %02x",
				last_4[0],
				last_4[1],
				last_4[2],
				last_4[3],
			)
			return bytes.compare(last_4, []byte{'\r', '\n', '\r', '\n'}) == 0
		}

		bytes_received := 255
		for bytes_received != 0 {
			n, recv_error := net.recv_tcp(client_socket, recv_buffer[:])
			if recv_error != nil {
				log.errorf("Failed to receive data: %v", recv_error)

				break
			}
			log.debugf("received:\n'''\n%s\n'''", recv_buffer[:n])
			if has_double_newlines(recv_buffer[:n]) {
				break
			}
			bytes_received = n
		}

		message, message_parsing_error := client.parse_message(recv_buffer[:bytes_received])
		if message_parsing_error != nil {
			log.errorf("Failed to parse message: %v", message_parsing_error)

			break
		}
		log.debugf("message=%v", message)

		if message.path == "/favicon.ico" {
			b: bytes.Buffer
			bytes.buffer_write_string(&b, "HTTP/1.1 404 Not Found\r\n")
			net.send_tcp(client_socket, bytes.buffer_to_bytes(&b))

			continue
		}

		bytes_sent := 0
		for bytes_sent < len(welcome_message) {
			n, send_error := net.send_tcp(client_socket, welcome_message)
			if send_error != nil {
				log.errorf("Failed to send data: %v", send_error)

				break
			}
			bytes_sent += n
		}
	}
}
