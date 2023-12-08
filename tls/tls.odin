package tls

import "core:bytes"
import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:testing"

// Client_Hello :: struct {
//     protocol_version: u16,
//     random: [32]byte,
// } 

hmac_sha256 :: proc(
	key: []byte,
	data: []byte,
	output: []byte,
	allocator := context.allocator,
) -> (
	error: mem.Allocator_Error,
) {
	block_size :: sha2.SHA256_BLOCK_SIZE
	digest_size :: sha2.DIGEST_SIZE_256

	key_bytes: [block_size]byte
	ipad_bytes: [block_size]byte
	opad_bytes: [block_size]byte
	inner_hash_bytes: [digest_size]byte
	outer_hash_bytes: [digest_size]byte

	if len(key) > block_size {
		key_value := sha2.hash_256(key)
		copy(key_bytes[:], key_value[:])
	} else if len(key) <= block_size {
		copy(key_bytes[:], key)
	}

	for i in 0 ..< block_size {
		ipad_bytes[i] = key_bytes[i] ~ 0x36
		opad_bytes[i] = key_bytes[i] ~ 0x5c
	}

	ipad_concatenated := bytes.concatenate([][]byte{ipad_bytes[:], data}, allocator)
	defer delete(ipad_concatenated, allocator)

	inner_hash_bytes = sha2.hash_256(ipad_concatenated)

	opad_concatenated := bytes.concatenate([][]byte{opad_bytes[:], inner_hash_bytes[:]}, allocator)
	defer delete(opad_concatenated, allocator)

	outer_hash_bytes = sha2.hash_256(opad_concatenated)

	copy(output, outer_hash_bytes[:])

	return nil
}

@(test, private = "package")
test_hmac_sha256 :: proc(t: ^testing.T) {
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer expect_no_leaks(t, tracking_allocator)

	TestCase :: struct {
		key:      []byte,
		data:     []byte,
		expected: []byte,
	}

	key1_buffer: bytes.Buffer
	bytes.buffer_write(&key1_buffer, []byte{'1', '2', '3', '4', '5', '6', '7', '8'})
	key1 := bytes.buffer_to_bytes(&key1_buffer)
	expected1 := []byte {
		115,
		36,
		63,
		156,
		225,
		203,
		81,
		241,
		244,
		158,
		162,
		39,
		154,
		204,
		100,
		13,
		113,
		98,
		42,
		100,
		217,
		202,
		3,
		118,
		61,
		174,
		70,
		203,
		115,
		197,
		255,
		59,
	}

	key2 := bytes.repeat([]byte{'1', '2', '3', '4', '5', '6', '7', '8'}, 8)
	expected2 := []byte {
		183,
		8,
		41,
		89,
		48,
		16,
		34,
		180,
		204,
		91,
		217,
		88,
		11,
		112,
		185,
		1,
		29,
		42,
		64,
		1,
		58,
		149,
		114,
		217,
		175,
		144,
		226,
		80,
		192,
		91,
		160,
		12,
	}

	key3 := bytes.repeat([]byte{'1', '2', '3', '4', '5', '6', '7', '8'}, 10)

	expected3 := []byte {
		50,
		238,
		5,
		93,
		130,
		186,
		53,
		32,
		226,
		47,
		219,
		122,
		144,
		224,
		99,
		239,
		19,
		46,
		160,
		38,
		235,
		239,
		212,
		165,
		32,
		208,
		120,
		93,
		96,
		6,
		30,
		73,
	}

	cases := []TestCase {
		{key = key1, data = []byte{'a', 'b', 'c'}, expected = expected1},
		{key = key2, data = []byte{'a', 'b', 'c'}, expected = expected2},
		{key = key3, data = []byte{'a', 'b', 'c'}, expected = expected3},
	}

	for d in cases {
		output: [sha2.DIGEST_SIZE_256]byte
		hmac_error := hmac_sha256(d.key, d.data, output[:])
		testing.expect_value(t, hmac_error, nil)
		testing.expect(
			t,
			bytes.compare(output[:], d.expected) == 0,
			fmt.tprintf("expected %02x, got %02x", d.expected, output[:]),
		)
		delete(d.key, context.allocator)
	}
}

expect_no_leaks :: proc(t: ^testing.T, allocator: mem.Tracking_Allocator) -> bool {
	if len(allocator.allocation_map) != 0 {
		fmt.printf("Expected no leaks, got %d\n", len(allocator.allocation_map))
		for _, v in allocator.allocation_map {
			fmt.printf("\t%s: %d\n", v.location, v.size)
		}
		testing.expect_value(t, len(allocator.allocation_map), 0)

		return false
	}

	return true
}
