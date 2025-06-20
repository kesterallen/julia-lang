
using ArgParse
using Printf

abstract type FilterRule end

struct IncludeRule <: FilterRule
    letter::Char
    index::Int
    right_spot::Bool
end

struct ExcludeRule <: FilterRule
    letter::Char
end

function parse_filter_argument(argument)
    filter_rules = Vector{FilterRule}()
    # ExcludeRules:
	for m in eachmatch(r"^([a-zA-Z]+)$", argument)
        for c in m.captures[1]
            push!(filter_rules, ExcludeRule(c))
        end
    end

	# IncludeRules: find all letter-number combinations
	for m in eachmatch(r"(\w)((?:[-+]?\d+)+)", argument)

        # Extract initial letter and the position info
		letter = m.captures[1][1]
		numbers_part = m.captures[2]
		
		locations = [String(num.match) for num in eachmatch(r"[-+]?\d+", numbers_part)]

        right_spot = locations[1] != "-"
        for location in locations
            for index in location
                if index == '-'
                    right_spot = false
                elseif index == '+'
                    right_spot = true
                else
                    push!(filter_rules, IncludeRule(letter, parse(Int, index), right_spot))
                end
                
            end
        end
	end
    return filter_rules
end

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--show-all", "-a"
            help = "Show all results and scores"
            action = :store_true
            arg_type = Bool
            default = false
        #"--everything", "-e"
            #help = "Solve every wordle word and present statistics"
            #action = :store_true
            #arg_type = Bool
            #default = false
        #"--target-word", "-t"
            #help = "Solve this word"
            #arg_type = String
        "filters"
            help = "Filters"
            action = :store_arg
            nargs = '*'
    end
    return parse_args(s)
end

function get_words()
    words = Vector{String}()
    for word in eachline("/usr/share/dict/american-english")
        if length(word) == 5
            push!(words, lowercase(word))
        end
    end
    return words
end

# Letter frequency scores
function score_letters(words)
    letter_counts = Dict()
    tot_count = 0
    for word in words
        for letter in word
            tot_count += 1
            if !haskey(letter_counts, letter)
                letter_counts[letter] = 0
            end
            letter_counts[letter] += 1
        end
    end

    letter_scores = Dict()
    for (letter, count) in letter_counts
        letter_scores[letter] = count / tot_count
    end
    return letter_scores
end

function score_words(words)
    # Letter-frequencing scoring:
    letter_scores = score_letters(words)
    top_score = 0
    raw_scores = Dict()
    for word in words
        score = sum(letter_scores[c] for c in word)
        raw_scores[word] = score
        top_score = max(score, top_score)
    end
    # Normalize
    scores = Dict(w => s / top_score for (w, s) in raw_scores)

    # Unique-letter-count scoring:
    ulc_scores = Dict(w => length(Set(w)) / length(w) for w in words)

    # Compbine letter-frequency and unique-letter-count scoring
    final_scores = Dict(w => (s + ulc_scores[w]) / 2.0 for (w, s) in scores)

    return final_scores
end

function apply_filter_rule(scored_words, filter_rule::IncludeRule)
    return filter((word, score)::Pair ->
        filter_rule.letter in word && 
        (word[filter_rule.index] == filter_rule.letter) == filter_rule.right_spot,
        scored_words
    )
end

function apply_filter_rule(scored_words, filter_rule::ExcludeRule)
    return filter((word, score)::Pair -> !(filter_rule.letter in word), scored_words)
end

function load_and_score_words()
    words = get_words()
    words = filter(word -> all(isascii, word), words) # eliminate non-ascii chars, they mess up naive char indexing
    scored_words = score_words(words)
    return scored_words
end

function parse_filter_arguments(filter_args)
    filter_rules = Vector{FilterRule}()
    for filter_arg in filter_args
        loop_filter_rules = parse_filter_argument(filter_arg)
        for filter_rule in loop_filter_rules
            push!(filter_rules, filter_rule)
        end
    end
    return filter_rules
end



args = parse_commandline()
filter_rules = parse_filter_arguments(args["filters"])
scored_words = reduce(apply_filter_rule, filter_rules; init=load_and_score_words())

for (word, score) in sort(collect(scored_words), by=last)
    @printf("%s %.2f\n", word, score)
end


