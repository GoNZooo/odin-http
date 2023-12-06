package http_server

import "core:bytes"
import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"

import http "../http"

ThreadState :: struct {
	socket:   net.TCP_Socket,
	handlers: [dynamic]Registered_Handler,
}

Server :: struct {
	handlers: [dynamic]Registered_Handler,
}

Registered_Handler :: struct {
	matcher: Matcher,
	handler: Handler,
}

Matcher :: #type proc(request: http.Request) -> bool

Handler :: #type proc(socket: net.TCP_Socket, request: http.Request, allocator: mem.Allocator)

server_register_handler :: proc(
	server: ^Server,
	matcher: Matcher,
	handler: Handler,
	allocator := context.allocator,
) -> mem.Allocator_Error {
	append(&server.handlers, Registered_Handler{matcher = matcher, handler = handler}) or_return

	return nil
}

get_handler :: proc(handlers: [dynamic]Registered_Handler, request: http.Request) -> Handler {
	for h in handlers {
		if h.matcher(request) {
			return h.handler
		}
	}

	return nil
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

	server: Server
	server.handlers = make([dynamic]Registered_Handler, 0, 0)
	server_register_handler(
		&server,
		proc(r: http.Request) -> bool {return r.path == "/"},
		handle_welcome,
	)
	server_register_handler(
		&server,
		proc(r: http.Request) -> bool {return r.path == "/ws"},
		handle_websocket,
	)

	thread_pool: thread.Pool
	thread.pool_init(&thread_pool, context.allocator, 1000)
	thread.pool_start(&thread_pool)

	for {
		client_socket, _, accept_error := net.accept_tcp(listen_socket)
		if accept_error != nil {
			log.errorf("Failed to accept connection: %v", accept_error)

			continue
		}

		client_arena := new(virtual.Arena)
		client_allocator := virtual.arena_allocator(client_arena)
		arena_init_error := virtual.arena_init_growing(client_arena, 4 * mem.Kilobyte)
		if arena_init_error != nil {
			log.errorf("Failed to initialize arena: %v", arena_init_error)

			continue
		}
		client_state := new(ThreadState)
		client_state.socket = client_socket
		client_state.handlers = server.handlers
		thread.pool_add_task(&thread_pool, client_allocator, handle_client, client_state)
	}
}

handle_client :: proc(t: thread.Task) {
	context.allocator = t.allocator
	context.logger = log.create_console_logger()

	state := cast(^ThreadState)t.data
	client_socket := state.socket
	recv_buffer: [64 * mem.Kilobyte]byte

	receive: for {
		bytes_received := 255
		for bytes_received != 0 {
			n, recv_error := net.recv_tcp(client_socket, recv_buffer[:])
			if recv_error == net.TCP_Recv_Error.Connection_Closed || n == 0 {
				log.debugf("Connection closed")

				break receive
			}
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

		request, request_parsing_error := http.parse_request(recv_buffer[:])
		if request_parsing_error != nil {
			log.errorf("Failed to parse request: %v", request_parsing_error)

			break
		}
		log.debugf("request=%v", request)

		handler := get_handler(state.handlers, request)
		if handler == nil {
			handler = handle_404
		}
		handler(client_socket, request, t.allocator)
	}
}

handle_welcome :: proc(socket: net.TCP_Socket, request: http.Request, allocator: mem.Allocator) {
	b: bytes.Buffer
	bytes.buffer_write_string(&b, "HTTP/1.1 200 OK\r\n")
	bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
	bytes.buffer_write_string(&b, "Content-Length: 48\r\n")
	bytes.buffer_write_string(&b, "\r\n")
	bytes.buffer_write_string(&b, "<html><body><h1>Hello, world!</h1></body></html>\r\n")
	welcome_message := bytes.buffer_to_bytes(&b)

	bytes_sent := 0
	for bytes_sent < len(welcome_message) {
		n, send_error := net.send_tcp(socket, welcome_message)
		if send_error != nil {
			log.errorf("Failed to send data: %v", send_error)

			break
		}
		bytes_sent += n
	}
}

handle_404 :: proc(socket: net.TCP_Socket, request: http.Request, allocator: mem.Allocator) {
	b: bytes.Buffer
	bytes.buffer_write_string(&b, "HTTP/1.1 404 Not Found\r\n")
	bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
	bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
	bytes.buffer_write_string(&b, "\r\n")
	not_found_message := bytes.buffer_to_bytes(&b)

	bytes_sent := 0
	for bytes_sent < len(not_found_message) {
		n, send_error := net.send_tcp(socket, not_found_message)
		if send_error != nil {
			log.errorf("Failed to send data: %v", send_error)

			break
		}
		bytes_sent += n
	}
}

handle_websocket :: proc(socket: net.TCP_Socket, request: http.Request, allocator: mem.Allocator) {
	key, has_key := request.headers["Sec-WebSocket-Key"]
	if !has_key {
		log.errorf("Missing Sec-WebSocket-Key header")
		b: bytes.Buffer
		bytes.buffer_write_string(&b, "HTTP/1.1 400 Bad Request\r\n")
		bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
		bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
		bytes.buffer_write_string(&b, "\r\n")

		return
	}

	connection_header, has_connection_header := request.headers["Connection"]
	if !has_connection_header || connection_header != "Upgrade" {
		log.errorf("Missing Connection: Upgrade header")
		b: bytes.Buffer
		bytes.buffer_write_string(&b, "HTTP/1.1 400 Bad Request\r\n")
		bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
		bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
		bytes.buffer_write_string(&b, "\r\n")

		return
	}

	upgrade_header, has_upgrade_header := request.headers["Upgrade"]
	if !has_upgrade_header || upgrade_header != "websocket" {
		log.errorf("Missing Upgrade: websocket header")
		b: bytes.Buffer
		bytes.buffer_write_string(&b, "HTTP/1.1 400 Bad Request\r\n")
		bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
		bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
		bytes.buffer_write_string(&b, "\r\n")

		return
	}

	websocket_version_header, has_websocket_version_header :=
		request.headers["Sec-WebSocket-Version"]
	if !has_websocket_version_header || websocket_version_header != "13" {
		log.errorf("Missing Sec-WebSocket-Version: 13 header")
		b: bytes.Buffer
		bytes.buffer_write_string(&b, "HTTP/1.1 400 Bad Request\r\n")
		bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
		bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
		bytes.buffer_write_string(&b, "\r\n")

		return
	}

	_, has_host_header := request.headers["Host"]
	if !has_host_header {
		log.errorf("Missing Host header")
		b: bytes.Buffer
		bytes.buffer_write_string(&b, "HTTP/1.1 400 Bad Request\r\n")
		bytes.buffer_write_string(&b, "Content-Type: text/html\r\n")
		bytes.buffer_write_string(&b, "Content-Length: 0\r\n")
		bytes.buffer_write_string(&b, "\r\n")

		return
	}

	concatenated_value := strings.concatenate(
		[]string{key, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"},
	)
	sha1_hash := sha1.hash_string(concatenated_value)
	accept_value := base64.encode(sha1_hash[:])

	b: bytes.Buffer
	bytes.buffer_write_string(&b, "HTTP/1.1 101 Switching Protocols\r\n")
	bytes.buffer_write_string(&b, "Upgrade: websocket\r\n")
	bytes.buffer_write_string(&b, "Connection: Upgrade\r\n")
	bytes.buffer_write_string(&b, "Sec-WebSocket-Accept: ")
	bytes.buffer_write_string(&b, accept_value)
	bytes.buffer_write_string(&b, "\r\n")
	bytes.buffer_write_string(&b, "\r\n")

	switching_protocols_message := bytes.buffer_to_bytes(&b)

	bytes_sent := 0
	for bytes_sent < len(bytes.buffer_to_bytes(&b)) {
		n, send_error := net.send_tcp(socket, switching_protocols_message[bytes_sent:])
		if send_error != nil {
			log.errorf("Failed to send data: %v", send_error)

			break
		}
		bytes_sent += n
	}

	recv_buffer: [128 * mem.Kilobyte]byte
	websocket_receive: for {
		bytes_received := 0
		for {
			n, recv_error := net.recv_tcp(socket, recv_buffer[:])
			if recv_error == net.TCP_Recv_Error.Connection_Closed || n == 0 {
				log.debugf("Connection closed")

				break websocket_receive
			}
			if recv_error != nil {
				log.errorf("Failed to receive data: %v", recv_error)

				break websocket_receive
			}
			log.debugf("received:\n'''\n%s\n'''", recv_buffer[:n])
			bytes_received += n
			break
		}

		fragment, _, fragment_parsing_error := http.parse_websocket_fragment(
			recv_buffer[:bytes_received],
		)
		if fragment_parsing_error != nil {
			log.errorf("Failed to parse websocket fragment: %v", fragment_parsing_error)

			break
		}
		log.debugf("fragment=%v", fragment)

		switch t in fragment.data {
		case http.Continuation_Data:
			log.debugf("Received continuation data: '%s'", t.payload)
		case http.Text_Data:
			log.debugf("Received text data: '%s'", t.payload)
		case http.Binary_Data:
			log.debugf("Received binary data: '%s'", t.payload)
		// control fragments
		case http.Close_Data:
			log.debugf("Closing connection because other side sent CLOSE fragment")
			break websocket_receive
		case http.Ping_Data:
			log.debugf("Received ping data: '%s'", t.payload)
		case http.Pong_Data:
			log.debugf("Received pong data: '%s'", t.payload)
		}
	}
}

has_double_newlines :: proc(data: []byte) -> bool {
	if len(data) < 4 {
		return false
	}

	last_4 := data[len(data) - 4:]
	return bytes.compare(last_4, []byte{'\r', '\n', '\r', '\n'}) == 0
}
