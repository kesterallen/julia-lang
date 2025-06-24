using ArgParse
using Printf

const DICTIONARY_FILE = "/usr/share/dict/american-english"
const WORD_LENGTH = 5

abstract type
    FilterRule
end

struct IncludeRule <: FilterRule
    letter::Char
    index::Int
    right_spot::Bool
end

struct ExcludeRule <: FilterRule
    letter::Char
end

"""
Read CLI args
"""
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
            #help = "Solve for this word"
            #arg_type = String
        "filters"
            help = "Filters"
            action = :store_arg
            arg_type = String
            nargs = '*'
    end
    return parse_args(s)
end

"""
Generate FilterRule items from user arguments, using mapreduce instead of a loop per Claude.ai
"""
function parse_filter_arguments(filter_args::Vector{String})::Vector{FilterRule}
    return mapreduce(parse_filter_argument, vcat, filter_args; init=FilterRule[])
end

"""
Parse a single filter argument into FilterRule objects.
Format: letters to exclude (e.g., "abc") and letter-positions (e.g., "a12-3" or "d+34-1")
"""
function parse_filter_argument(argument::AbstractString)::Vector{FilterRule}
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
                    int_index = parse(Int, index)
                    if int_index < 1 || int_index > WORD_LENGTH
                        throw(DomainError(int_index, "wordle indices must be between 1 and 5"))
                    end
                    push!(filter_rules, IncludeRule(letter, int_index, right_spot))
                end

            end
        end
    end
    return filter_rules
end


"""
Multiple dispatch: Apply an IncludeRule filter to the scored words.
"""
function apply_filter_rule(scored_words::Dict{String, Float64}, filter_rule::IncludeRule)::Dict{String, Float64}
    return filter((word, score)::Pair ->
        filter_rule.letter in word &&
        (word[filter_rule.index] == filter_rule.letter) == filter_rule.right_spot,
        scored_words
    )
end

"""
Multiple dispatch: Apply an IncludeRule filter to the scored words.
"""
function apply_filter_rule(scored_words::Dict{String, Float64}, filter_rule::ExcludeRule)::Dict{String, Float64}
    return filter((word, score)::Pair -> !(filter_rule.letter in word), scored_words)
end

"""
Load the dictionary and score the Wordle words
"""
function load_and_score_words()::Dict{String, Float64}
    words = get_words()
    scored_words = score_words(words)
    return scored_words
end

"""
Load the dictionary file
"""
function get_words()::Vector{String}
    words = Vector{String}()
    for word in eachline(DICTIONARY_FILE)
        if length(word) == WORD_LENGTH && all(isletter, word) && all(isascii, word)
            push!(words, strip(lowercase(word)))
        end
    end
    return words
end

"""
Score words based on letter frequency and unique letter diversity.
"""
function score_words(words::Vector{String})::Dict{String, Float64}
    # Normalized letter-frequencing scoring:
    letter_scores = score_letters(words)
    top_score = 0
    raw_scores = Dict()
    for word in words
        score = sum(letter_scores[c] for c in word)
        raw_scores[word] = score
        top_score = max(score, top_score)
    end
    scores = Dict(w => s / top_score for (w, s) in raw_scores)

    # Unique-letter-count scoring:
    ulc_scores = Dict(w => length(Set(w)) / length(w) for w in words)

    # Combine scorings
    return Dict(w => (s + ulc_scores[w]) / 2.0 for (w, s) in scores)
end

"""
Letter frequency scores for the list of words
"""
function score_letters(words::Vector{String})::Dict{Char, Float64}
    letter_counts = Dict{Char, Int}()
    tot_count = 0
    for word in words, letter in word
        tot_count += 1
        letter_counts[letter] = get(letter_counts, letter, 0) + 1
    end

    letter_scores = Dict()
    for (letter, count) in letter_counts
        letter_scores[letter] = count / tot_count
    end
    return letter_scores
end

function main()
    args = parse_commandline()
    filter_rules = parse_filter_arguments(args["filters"])
    scored_words = reduce(apply_filter_rule, filter_rules; init=load_and_score_words())

    for (word, score) in sort(collect(scored_words), by=last)
        @printf("%s %.2f\n", word, score)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
