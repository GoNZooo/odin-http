package tokenization

import "core:fmt"
import "core:log"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:testing"

Source_Token :: struct {
	token:    Token,
	location: Location,
}

Token :: union {
	EOF,
	Newline,
	Tab,
	Space,
	Left_Parenthesis,
	Right_Parenthesis,
	Left_Square_Bracket,
	Right_Square_Bracket,
	Left_Curly_Brace,
	Right_Curly_Brace,
	Left_Angle_Bracket,
	Right_Angle_Bracket,
	Caret,
	Colon,
	Comma,
	Dot,
	Underscore,
	Dash,
	Slash,
	Comment,
	Upper_Symbol,
	Lower_Symbol,
	String,
	Single_Quoted_String,
	Float,
	Integer,
	Char,
	Boolean,
}

EOF :: struct {}
Newline :: struct {}
Tab :: struct {}
Space :: struct {}
Left_Parenthesis :: struct {}
Right_Parenthesis :: struct {}
Left_Square_Bracket :: struct {}
Right_Square_Bracket :: struct {}
Left_Curly_Brace :: struct {}
Right_Curly_Brace :: struct {}
Left_Angle_Bracket :: struct {}
Right_Angle_Bracket :: struct {}
Caret :: struct {}
Colon :: struct {}
Comma :: struct {}
Dot :: struct {}
Underscore :: struct {}
Dash :: struct {}
Slash :: struct {}
Comment :: struct {}

Upper_Symbol :: struct {
	value: string,
}

Lower_Symbol :: struct {
	value: string,
}

String :: struct {
	value: string,
}

Single_Quoted_String :: struct {
	value: string,
}

Float :: struct {
	value: f64,
}

Integer :: struct {
	value: int,
}

Char :: struct {
	value: byte,
}

Boolean :: struct {
	value: bool,
}


/*
A mutable structure that keeps track of and allows operations for looking at,
consuming and expecting tokens. Created with `tokenizer_create`.
*/
Tokenizer :: struct {
	filename: string,
	source:   string,
	index:    int,
	position: int,
	line:     int,
	column:   int,
}

Expectation_Error :: union {
	Expected_Token,
	Expected_String,
	Expected_End_Marker,
	Expected_One_Of,
}

Expected_Token_Error :: union {
	Expected_Token,
}

Expected_Token :: struct {
	expected: Token,
	actual:   Token,
	location: Location,
}

Expected_String :: struct {
	expected: string,
	actual:   string,
	location: Location,
}

Expected_End_Marker :: struct {
	expected: []string,
	location: Location,
}

Expected_One_Of_Error :: union {
	Expected_One_Of,
}

Expected_One_Of :: struct {
	expected: []Token,
	actual:   Token,
	location: Location,
}

Location :: struct {
	line:        int,
	column:      int,
	position:    int, // byte offset in source
	source_file: string,
}

// Creates a `Tokenizer` from a given source string. Use `tokenizer_peek`, `tokenizer_next_token`
// and `tokenizer_expect` variants to read tokens from a `Tokenizer`.
tokenizer_create :: proc(source: string) -> Tokenizer {
	return Tokenizer{source = source, line = 1}
}

tokenizer_expect_exact :: proc(
	tokenizer: ^Tokenizer,
	expectation: Token,
) -> (
	token: Source_Token,
	error: Expectation_Error,
) {
	start_location := Location {
		position = tokenizer.position,
		line     = tokenizer.line,
		column   = tokenizer.column,
	}
	read_token, _, _ := tokenizer_next_token(tokenizer)

	if read_token.token != expectation {
		return Source_Token{},
			Expected_Token{
				expected = expectation,
				actual = read_token.token,
				location = start_location,
			}
	}

	return read_token, nil
}

tokenizer_expect :: proc(
	tokenizer: ^Tokenizer,
	expectation: Token,
) -> (
	token: Source_Token,
	error: Expectation_Error,
) {
	start_location := Location {
		position = tokenizer.position,
		line     = tokenizer.line,
		column   = tokenizer.column,
	}
	read_token, _, _ := tokenizer_next_token(tokenizer)

	expectation_typeid := reflect.union_variant_typeid(expectation)
	token_typeid := reflect.union_variant_typeid(read_token.token)

	if expectation_typeid != token_typeid {
		return Source_Token{},
			Expected_Token{
				expected = expectation,
				actual = read_token.token,
				location = start_location,
			}
	}

	return read_token, nil
}

tokenizer_read_string_until :: proc(
	tokenizer: ^Tokenizer,
	end_markers: []string,
) -> (
	string: string,
	error: Expectation_Error,
) {
	start_location := Location {
		position = tokenizer.position,
		line     = tokenizer.line,
		column   = tokenizer.column,
	}
	source := tokenizer.source[tokenizer.position:]
	end_marker_index, _ := strings.index_multi(source, end_markers)
	if end_marker_index == -1 {
		return "", Expected_End_Marker{expected = end_markers, location = start_location}
	}

	string = source[:end_marker_index]
	tokenizer.position += len(string)
	newline_count := strings.count(string, "\n")
	tokenizer.line += newline_count
	if newline_count > 0 {
		tokenizer.column = 1
	} else {
		tokenizer.column += end_marker_index
	}

	return string, nil
}

tokenizer_skip_string :: proc(
	tokenizer: ^Tokenizer,
	expected_string: string,
) -> (
	error: Expectation_Error,
) {
	start_location := Location {
		position = tokenizer.position,
		line     = tokenizer.line,
		column   = tokenizer.column,
	}

	source := tokenizer.source[tokenizer.position:]
	if !strings.has_prefix(source, expected_string) {
		rest_length := min(len(expected_string), len(source))

		return(
			Expected_String{
				expected = expected_string,
				actual = source[:rest_length],
				location = start_location,
			} \
		)
	}

	tokenizer.position += len(expected_string)
	newline_count := strings.count(expected_string, "\n")
	tokenizer.line += newline_count
	if newline_count > 0 {
		tokenizer.column = len(expected_string) - strings.last_index(expected_string, "\n")
	} else {
		tokenizer.column += len(expected_string)
	}


	return nil
}

tokenizer_skip_any_of :: proc(tokenizer: ^Tokenizer, tokens: []Token) {
	match: for {
		token := tokenizer_peek(tokenizer)
		token_tag := reflect.union_variant_typeid(token)
		for t in tokens {
			t_tag := reflect.union_variant_typeid(t)
			if token_tag == t_tag {
				tokenizer_next_token(tokenizer)
				continue match
			}
		}
		break match
	}
}

tokenizer_next_token :: proc(
	tokenizer: ^Tokenizer,
) -> (
	source_token: Source_Token,
	index: int,
	ok: bool,
) {
	source_token = Source_Token {
		location = Location{
			position = tokenizer.position,
			line = tokenizer.line,
			column = tokenizer.column,
		},
	}

	if tokenizer.position >= len(tokenizer.source) {
		source_token.token = EOF{}

		return source_token, tokenizer.index, false
	}

	token := current(tokenizer, true)
	current_index := tokenizer.index
	tokenizer.index += 1

	source_token.token = token

	return source_token, current_index, token != nil
}

tokenizer_peek :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	if tokenizer.index >= len(tokenizer.source) {
		return nil
	}

	return current(tokenizer, false)
}

@(private = "file")
current :: proc(tokenizer: ^Tokenizer, modify: bool) -> (token: Token) {
	tokenizer_copy := tokenizer^
	defer if modify {
		tokenizer^ = tokenizer_copy
	}

	if tokenizer_copy.position >= len(tokenizer_copy.source) {
		return EOF{}
	}

	switch tokenizer_copy.source[tokenizer_copy.position] {
	case '#':
		next_newline_index := strings.index(tokenizer_copy.source[tokenizer_copy.position:], "\n")
		if next_newline_index == -1 {
			tokenizer.position = len(tokenizer.source)

			return EOF{}
		}

		tokenizer_copy.position += next_newline_index

		return Comment{}
	case ' ':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Space{}
	case '\r':
		if tokenizer_copy.source[tokenizer_copy.position + 1] == '\n' {
			tokenizer_copy.position += 2
			tokenizer_copy.line += 1
			tokenizer_copy.column = 0

			return Newline{}
		} else {
			log.panicf(
				"Unexpected carriage return without newline at %v:%v",
				tokenizer_copy.line,
				tokenizer_copy.column,
			)
		}
	case '\n':
		tokenizer_copy.position += 1
		tokenizer_copy.line += 1
		tokenizer_copy.column = 0

		return Newline{}

	case '(':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Left_Parenthesis{}
	case ')':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Right_Parenthesis{}
	case '[':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Left_Square_Bracket{}
	case ']':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Right_Square_Bracket{}
	case '{':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Left_Curly_Brace{}
	case '}':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Right_Curly_Brace{}
	case '<':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Left_Angle_Bracket{}
	case '>':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Right_Angle_Bracket{}
	case '^':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Caret{}
	case '$':
		return read_char(&tokenizer_copy)
	case ':':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Colon{}
	case ',':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Comma{}
	case '.':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Dot{}
	case '_':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Underscore{}
	case '-':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Dash{}
	case '/':
		tokenizer_copy.position += 1
		tokenizer_copy.column += 1

		return Slash{}
	case '0' ..= '9':
		float := read_float(&tokenizer_copy)
		if float != nil {
			return float
		}

		return read_integer(&tokenizer_copy)
	case '"':
		return read_string(&tokenizer_copy, `"`)

	case '\'':
		return read_string(&tokenizer_copy, "'")
	case 't', 'f':
		boolean := read_boolean(&tokenizer_copy)
		if boolean != nil {
			return boolean
		}
		fallthrough
	case 'a' ..= 'z':
		return read_lower_symbol(&tokenizer_copy)
	case 'A' ..= 'Z':
		return read_upper_symbol(&tokenizer_copy)
	case:
		snippet := tokenizer_copy.source[tokenizer_copy.position:]
		if len(snippet) > 64 {
			snippet = snippet[:64]
		}
		log.panicf(
			"Unexpected character '%c' @ %s:%d:%d (snippet: '%s')",
			tokenizer_copy.source[tokenizer_copy.position],
			tokenizer_copy.filename,
			tokenizer_copy.line,
			tokenizer_copy.column,
			snippet,
		)
	}

	return nil
}

@(private = "file")
read_lower_symbol :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	start := tokenizer.position
	source := tokenizer.source[start:]

	assert(source[0] >= 'a' && source[0] <= 'z')

	symbol_value := read_until(source, " \t\n()[]{}<>,.:'\"")
	symbol_length := len(symbol_value)
	tokenizer.position += symbol_length
	tokenizer.column += symbol_length

	return Lower_Symbol{value = symbol_value}
}

@(private = "file")
read_upper_symbol :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	start := tokenizer.position
	source := tokenizer.source[start:]

	assert(source[0] >= 'A' && source[0] <= 'Z')

	symbol_value := read_until(source, " \t\n()[]{}<>,.:'\"")
	symbol_length := len(symbol_value)
	tokenizer.position += symbol_length
	tokenizer.column += symbol_length

	return Upper_Symbol{value = symbol_value}
}

@(private = "file")
read_boolean :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	start := tokenizer.position
	source := tokenizer.source[start:]

	if prefix_matches(source, "true") {
		tokenizer.position += 4
		tokenizer.column += 4

		return Boolean{value = true}
	} else if prefix_matches(source, "false") {
		tokenizer.position += 5
		tokenizer.column += 5

		return Boolean{value = false}
	}

	return nil
}

@(private = "file")
read_char :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	character := tokenizer.source[tokenizer.position]
	assert(character == '$')
	tokenizer.position += 1
	character = tokenizer.source[tokenizer.position]
	tokenizer.position += 1
	tokenizer.column += 2

	return Char{value = character}
}

@(private = "file")
read_float :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	start := tokenizer.position
	character := tokenizer.source[tokenizer.position]
	has_period := false
	new_position := tokenizer.position
	for new_position < len(tokenizer.source) && character >= '0' && character <= '9' ||
	    character == '.' {
		switch character {
		case '0' ..= '9':
			new_position += 1
		case '.':
			has_period = true
			new_position += 1
		case:
			break
		}

		if new_position >= len(tokenizer.source) {
			break
		}

		character = tokenizer.source[new_position]
	}

	if !has_period {
		return nil
	}

	slice := tokenizer.source[start:new_position]
	float_value, parse_ok := strconv.parse_f64(slice)
	if !parse_ok {
		return nil
	}

	tokenizer.column += len(slice)
	tokenizer.position = new_position
	token = Float {
		value = float_value,
	}

	return
}

@(private = "file")
read_integer :: proc(tokenizer: ^Tokenizer) -> (token: Token) {
	start := tokenizer.position
	character := tokenizer.source[tokenizer.position]
	is_number := character >= '0' && character <= '9'
	if !is_number {
		return nil
	}

	for is_number {
		if tokenizer.position >= len(tokenizer.source) {
			break
		}
		character = tokenizer.source[tokenizer.position]
		switch character {
		case '0' ..= '9':
			tokenizer.position += 1
		case:
			is_number = false
		}
	}

	slice := tokenizer.source[start:tokenizer.position]
	int_value, parse_ok := strconv.parse_int(slice)
	if !parse_ok {
		log.panicf("Failed to parse integer ('%s') with state: %v", slice, tokenizer)
	}

	tokenizer.column += len(slice)

	return Integer{value = int_value}
}

@(private = "file")
read_string :: proc(tokenizer: ^Tokenizer, quote_characters: string) -> (token: Token) {
	start := tokenizer.position
	character := string(tokenizer.source[tokenizer.position:tokenizer.position + 1])
	if character != quote_characters {
		return nil
	}

	rest_of_string := tokenizer.source[start + 1:]
	end_quote_index := strings.index(rest_of_string, quote_characters)
	if end_quote_index == -1 {
		log.panicf("Failed to find end quote for string: %s", rest_of_string)
	}
	string_contents := rest_of_string[:end_quote_index]
	// NOTE: 2 because we want to skip over the quote in terms of position; we've already read it
	tokenizer.position += end_quote_index + 2
	last_newline_index := strings.last_index(string_contents, "\n")
	if last_newline_index == -1 {
		tokenizer.column += len(string_contents) + 2
	} else {
		tokenizer.line += strings.count(string_contents, "\n")
		tokenizer.column = end_quote_index - last_newline_index
	}

	if quote_characters == "'" {
		return Single_Quoted_String{value = string_contents}
	}

	return String{value = string_contents}
}

@(test, private = "package")
test_tokenize_empty :: proc(t: ^testing.T) {
	tokenizer := tokenizer_create("")
	count := 0
	for _ in tokenizer_next_token(&tokenizer) {
		count += 1
	}

	testing.expect_value(t, count, 0)
	testing.expect_value(t, tokenizer.line, 1)
	testing.expect_value(t, tokenizer.column, 0)
	testing.expect_value(t, tokenizer.index, 0)
}

@(test, private = "package")
test_tokenize_integer :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("123")
	token, index, ok := tokenizer_next_token(&tokenizer)
	testing.expect_value(
		t,
		token,
		Source_Token{
			token = Integer{value = 123},
			location = Location{position = 0, line = 1, column = 0},
		},
	)
	testing.expect_value(t, index, 0)
	testing.expect_value(t, ok, true)
}

@(test, private = "package")
test_tokenize_float :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("42.0")
	token, index, ok := tokenizer_next_token(&tokenizer)
	testing.expect_value(
		t,
		token,
		Source_Token{
			token = Float{value = 42},
			location = Location{position = 0, line = 1, column = 0},
		},
	)
	testing.expect_value(t, index, 0)
	testing.expect_value(t, ok, true)
}

@(test, private = "package")
test_read_double_quoted_string :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(`"hello"`)
	token, index, ok := tokenizer_next_token(&tokenizer)
	testing.expect_value(
		t,
		token,
		Source_Token{
			token = String{value = "hello"},
			location = Location{position = 0, line = 1, column = 0},
		},
	)
	testing.expect_value(t, index, 0)
	testing.expect_value(t, ok, true)
	rest_of_string := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_string, "")
}

@(test, private = "package")
test_read_single_quoted_string :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(`'hello'`)
	token, index, ok := tokenizer_next_token(&tokenizer)
	testing.expect_value(
		t,
		token,
		Source_Token{
			token = Single_Quoted_String{value = "hello"},
			location = Location{position = 0, line = 1, column = 0},
		},
	)
	testing.expect_value(t, index, 0)
	testing.expect_value(t, ok, true)
	rest_of_string := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_string, "")
}

@(test, private = "package")
test_read_symbols :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("()[]{}<>:,.")
	expected_tokens := []Source_Token{
		Source_Token{
			token = Left_Parenthesis{},
			location = Location{position = 0, line = 1, column = 0},
		},
		Source_Token{
			token = Right_Parenthesis{},
			location = Location{position = 1, line = 1, column = 1},
		},
		Source_Token{
			token = Left_Square_Bracket{},
			location = Location{position = 2, line = 1, column = 2},
		},
		Source_Token{
			token = Right_Square_Bracket{},
			location = Location{position = 3, line = 1, column = 3},
		},
		Source_Token{
			token = Left_Curly_Brace{},
			location = Location{position = 4, line = 1, column = 4},
		},
		Source_Token{
			token = Right_Curly_Brace{},
			location = Location{position = 5, line = 1, column = 5},
		},
		Source_Token{
			token = Left_Angle_Bracket{},
			location = Location{position = 6, line = 1, column = 6},
		},
		Source_Token{
			token = Right_Angle_Bracket{},
			location = Location{position = 7, line = 1, column = 7},
		},
		Source_Token{token = Colon{}, location = Location{position = 8, line = 1, column = 8}},
		Source_Token{token = Comma{}, location = Location{position = 9, line = 1, column = 9}},
		Source_Token{token = Dot{}, location = Location{position = 10, line = 1, column = 10}},
	}
	token_count := 0
	for token, i in tokenizer_next_token(&tokenizer) {
		testing.expect_value(t, token, expected_tokens[i])
		token_count += 1
	}
	testing.expect_value(t, token_count, len(expected_tokens))
}

@(test, private = "package")
test_read_char :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("$a$b$c")
	expected_tokens := []Source_Token{
		Source_Token{
			token = Char{value = 'a'},
			location = Location{position = 0, line = 1, column = 0},
		},
		Source_Token{
			token = Char{value = 'b'},
			location = Location{position = 2, line = 1, column = 2},
		},
		Source_Token{
			token = Char{value = 'c'},
			location = Location{position = 4, line = 1, column = 4},
		},
	}
	token_count := 0
	for token, i in tokenizer_next_token(&tokenizer) {
		testing.expect_value(t, token, expected_tokens[i])
		token_count += 1
	}
	testing.expect_value(t, token_count, 3)
}

@(test, private = "package")
test_read_boolean :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("true \nfalse")
	expected_tokens := []Source_Token{
		Source_Token{
			token = Boolean{value = true},
			location = Location{position = 0, line = 1, column = 0},
		},
		Source_Token{token = Space{}, location = Location{position = 4, line = 1, column = 4}},
		Source_Token{token = Newline{}, location = Location{position = 5, line = 1, column = 5}},
		Source_Token{
			token = Boolean{value = false},
			location = Location{position = 6, line = 2, column = 0},
		},
	}
	token_count := 0
	for token, i in tokenizer_next_token(&tokenizer) {
		testing.expect_value(t, token, expected_tokens[i])
		token_count += 1
	}
	testing.expect_value(t, token_count, len(expected_tokens))
}

@(test, private = "package")
test_read_lower_symbol :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("hello there")
	expected_tokens := []Source_Token{
		Source_Token{
			token = Lower_Symbol{value = "hello"},
			location = Location{position = 0, line = 1, column = 0},
		},
		Source_Token{token = Space{}, location = Location{position = 5, line = 1, column = 5}},
		Source_Token{
			token = Lower_Symbol{value = "there"},
			location = Location{position = 6, line = 1, column = 6},
		},
	}
	token_count := 0
	for token, i in tokenizer_next_token(&tokenizer) {
		testing.expect_value(t, token, expected_tokens[i])
		token_count += 1
	}
	testing.expect_value(t, token_count, len(expected_tokens))
}

@(test, private = "package")
test_tokenizer_expect :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("hello")
	read_token, expectation_error := tokenizer_expect(&tokenizer, Lower_Symbol{})
	testing.expect(
		t,
		expectation_error == nil,
		fmt.tprintf("Unexpected error: %v", expectation_error),
	)
	testing.expect_value(
		t,
		read_token,
		Source_Token{
			token = Lower_Symbol{value = "hello"},
			location = Location{position = 0, line = 1, column = 0},
		},
	)

	tokenizer2 := tokenizer_create("hello")
	read_token, expectation_error = tokenizer_expect(&tokenizer2, Upper_Symbol{})
	expected_error := Expected_Token {
		expected = Upper_Symbol{},
		actual = Lower_Symbol{value = "hello"},
		location = Location{position = 0, line = 1, column = 0},
	}
	e := expectation_error.(Expected_Token)
	testing.expect(
		t,
		e == expected_error,
		fmt.tprintf("Expected error: %v, got: %v", expected_error, expectation_error),
	)
}

@(test, private = "package")
test_tokenizer_expect_exact :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("hello")
	read_token, expectation_error := tokenizer_expect_exact(
		&tokenizer,
		Lower_Symbol{value = "hello"},
	)
	testing.expect(
		t,
		expectation_error == nil,
		fmt.tprintf("Unexpected error: %v", expectation_error),
	)
	testing.expect_value(
		t,
		read_token,
		Source_Token{
			token = Lower_Symbol{value = "hello"},
			location = Location{position = 0, line = 1, column = 0},
		},
	)

	tokenizer2 := tokenizer_create("hello")
	read_token, expectation_error = tokenizer_expect_exact(
		&tokenizer2,
		Lower_Symbol{value = "world"},
	)
	expected_error := Expected_Token {
		expected = Lower_Symbol{value = "world"},
		actual = Lower_Symbol{value = "hello"},
		location = Location{position = 0, line = 1, column = 0},
	}
	e := expectation_error.(Expected_Token)
	testing.expect(
		t,
		e == expected_error,
		fmt.tprintf("Expected error: %v, got: %v", expected_error, expectation_error),
	)
}

@(test, private = "package")
test_tokenizer_string_until :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("hello\r\nworld")
	read_string, expectation_error := tokenizer_read_string_until(&tokenizer, {"\r\n", "\n"})
	testing.expect(
		t,
		expectation_error == nil,
		fmt.tprintf("Unexpected error: %v", expectation_error),
	)
	testing.expect_value(t, read_string, "hello")

	tokenizer2 := tokenizer_create("hello\nworld")
	read_string, expectation_error = tokenizer_read_string_until(&tokenizer2, {"\r\n", "\n"})
	testing.expect(
		t,
		expectation_error == nil,
		fmt.tprintf("Unexpected error: %v", expectation_error),
	)
	testing.expect_value(t, read_string, "hello")
}
