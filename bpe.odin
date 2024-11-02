package bpe

import "core:strings"
import "core:testing"

Token :: int

// Byte-Pair Encoding (BPE) tokenizer
Tokenizer :: struct {
	merge_rules: map[[2]Token]Token,
	decoder:     map[Token]string,
}

destroy :: proc(t: ^Tokenizer) {
	delete(t.merge_rules)
	for k in t.decoder {
		delete(t.decoder[k])
	}
	delete(t.decoder)
}

encode :: proc(t: ^Tokenizer, input: string) -> [dynamic]Token {
	tokens := make([dynamic]Token, len(input))
	for i in 0 ..< len(input) {
		tokens[i] = cast(Token)input[i]
	}

	for {
		occurrences := count_pairs(tokens)
		defer delete(occurrences)

		candidate, candidate_occurrences := get_most_recurring_pair(occurrences)
		if candidate_occurrences <= 1 {
			break
		}

		merged_token, ok := t.merge_rules[candidate]
		if !ok {
			break
		}

		merge_tokens(&tokens, candidate, merged_token)
	}

	return tokens
}

decode :: proc(t: ^Tokenizer, input: [dynamic]Token) -> string {
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	for token in input {
		decoded, found := t.decoder[token]
		assert(found, "token not correctly cached")
		strings.write_string(&sb, decoded)
	}

	return strings.clone(strings.to_string(sb))
}

@(test)
test_encode_decode :: proc(t: ^testing.T) {
	tok: Tokenizer
	defer destroy(&tok)

	input := "ababc"

	train(&tok, input)

	tokens := encode(&tok, input)
	defer delete(tokens)
	testing.expect(t, len(tokens) == 3)

	decoded := decode(&tok, tokens)
	defer delete(decoded)
	testing.expect(t, strings.compare(input, decoded) == 0)
}

@(private = "file")
// Merge old pair occurrences with new token in place
merge_tokens :: proc(tokens: ^[dynamic]Token, old_pair: [2]Token, new_token: Token) {
	i, j := 0, 0 // i = old index, j = new index
	for {
		defer j += 1
		if i >= len(tokens) {
			break
		}
		// substitute when we find the old pair
		if tokens[i] == old_pair[0] && tokens[i + 1] == old_pair[1] {
			tokens[j] = new_token
			i += 2
			continue
		}
		// otherwise copy back the old tokens
		tokens[j] = tokens[i]
		i += 1
	}
	resize(tokens, j - 1)
}

@(private = "file")
count_pairs :: proc(tokens: [dynamic]Token) -> map[[2]Token]int {
	pair: [2]Token
	occurrences := make(map[[2]Token]int)
	for i in 0 ..< len(tokens) - 1 {
		pair[0] = tokens[i]
		pair[1] = tokens[i + 1]
		occurrences[pair] = occurrences[pair] + 1
	}
	return occurrences
}

@(private = "file")
get_most_recurring_pair :: proc(
	occurrences: map[[2]Token]int,
) -> (
	candidate: [2]Token,
	candidate_occurrences: int,
) {
	for pair in occurrences {
		current_occurrencens := occurrences[pair]
		if (current_occurrencens > candidate_occurrences) {
			candidate[0] = pair[0]
			candidate[1] = pair[1]
			candidate_occurrences = current_occurrencens
		}
	}
	return candidate, candidate_occurrences
}

train :: proc(t: ^Tokenizer, corpus: string) {
	// populate tokens with corpus byte values
	tokens := make([dynamic]Token, len(corpus))
	defer delete(tokens)
	for i in 0 ..< len(corpus) {
		tokens[i] = cast(Token)corpus[i]
	}

	t.merge_rules = make(map[[2]Token]Token)
	// we reserve the first 256 token ids for raw byte values
	next_token := 256
	for {
		defer next_token += 1

		occurrences := count_pairs(tokens)
		defer delete(occurrences)

		candidate, candidate_occurrences := get_most_recurring_pair(occurrences)
		if candidate_occurrences <= 1 {
			break
		}

		merge_tokens(&tokens, candidate, next_token)
		t.merge_rules[candidate] = next_token
	}

	t.decoder = make(map[Token]string)
	for i in 0 ..< 256 {
		t.decoder[i] = strings.clone_from_bytes({cast(byte)i})
	}

	for pair in t.merge_rules {
		ab, found_ab := t.merge_rules[pair]
		assert(found_ab, "merge rule not found for pair")

		decoded_a, found_a := t.decoder[pair[0]]
		assert(found_a, "decoded cached item not found for pair")

		decoded_b, found_b := t.decoder[pair[1]]
		assert(found_b, "decoded cached item  not found for pair")

		t.decoder[ab] = strings.concatenate({decoded_a, decoded_b})
	}
}

@(test)
test_train_graceful_stop_on_too_few_tokens :: proc(t: ^testing.T) {
	tok: Tokenizer
	defer destroy(&tok)
	input := "a"
	train(&tok, input)
}
