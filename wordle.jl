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
        "--everything", "-e"
            help = "Solve every wordle word and present statistics"
            action = :store_true
        "--target-word", "-t"
            help = "Solve for this word"
            arg_type = String
        "filters"
            help = "Filters"
            action = :store_arg
            arg_type = String
            nargs = '*'
    end
    return parse_args(s)
end

"""
Parse a single filter argument into FilterRule objects.
Format: letters to exclude (e.g., "abc") and letter-positions (e.g., "a12-3" or "d+34-1")
"""
function parse_filter_argument(argument::AbstractString)::Vector{FilterRule}
    filter_rules = Vector{FilterRule}()
    exclude_regex = r"^([a-zA-Z]+)$"
    include_regex = r"(\w)((?:[-+]?\d+)+)"

    # ExcludeRules:
    for m in eachmatch(exclude_regex, argument)
        filter_rules = mapreduce(c -> ExcludeRule(c), vcat, m.captures[1]; init=filter_rules)
    end

    # IncludeRules: find all letter-number combinations
    for m in eachmatch(include_regex, argument)

        # Extract initial letter and the position info
        letter = m.captures[1][1]
        numbers_part = m.captures[2]

        # A list of letter location specifications,
        # e.g. "+12-3", "45", "-13", # "12-3", "+23", or "1"
        locations = [String(num.match) for num in eachmatch(r"[-+]?\d+", numbers_part)]

        # The default for right_spot is "+" unless explicity specified otherwise
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
                        throw(DomainError(int_index, "wordle indices must be between 1 and $WORD_LENGTH"))
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
function apply_filter_rule(scored_words::Vector{Pair{Float64, String}}, filter_rule::IncludeRule)::Vector{Pair{Float64, String}}
    return filter((score, word)::Pair ->
        filter_rule.letter in word &&
        (word[filter_rule.index] == filter_rule.letter) == filter_rule.right_spot,
        scored_words
    )
end

"""
Multiple dispatch: Apply an IncludeRule filter to the scored words.
"""
function apply_filter_rule(scored_words::Vector{Pair{Float64, String}}, filter_rule::ExcludeRule)::Vector{Pair{Float64, String}}
    return filter((score, word)::Pair -> !(filter_rule.letter in word), scored_words)
end

"""
Load the dictionary and score the Wordle words
"""
function load_and_score_words()::Vector{Pair{Float64, String}}
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
    return unique(words)
end

"""
Score words based on letter frequency and unique letter diversity.
"""
function score_words(words::Vector{String})::Vector{Pair{Float64, String}}
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
    return [Pair((s + ulc_scores[w]) / 2.0, w) for (w, s) in scores]
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

# test the guess, return filters
function get_filters_from_guess(guess::String, target::String)::Vector{FilterRule}
    filter_rules = Vector{FilterRule}()

    for (iguess, guess_char) in enumerate(guess)
        rule = (guess_char in target) ?
            IncludeRule(guess_char, iguess, target[iguess] == guess_char) :
            ExcludeRule(guess_char)
        push!(filter_rules, rule)
    end
    return filter_rules
end

function find_targets(targets::Vector{String}, scored_words::Vector{Pair{Float64, String}}, verbose::Bool=true)
    # Update filters based on guess, apply the filters to eliminate words,
    # and get the new best guess. Works on a vector of 1 or more words.
    #
    scored_words_orig = copy(scored_words)
    for target in targets
        scored_words = copy(scored_words_orig)
        filter_rules = Vector{FilterRule}()
        num_guesses = 0
        is_found = false
        while !is_found
            num_guesses += 1
            guess = scored_words[1][2] # word portion of highest-scoring (score, word) pair
            if verbose
                println("Guess $num_guesses: $guess")
            end
            is_found = guess == target
            filter_rules = vcat(filter_rules, get_filters_from_guess(guess, target))
            scored_words = reduce(apply_filter_rule, filter_rules; init=scored_words)
        end

        if length(scored_words) == 0
            println("no solution found for $target")
        end
        if verbose
            println("found $target in $num_guesses guesses")
        end
    end
end

function main()
    args = parse_commandline()

    # All 3 paths below use scored_words
    scored_words = load_and_score_words()

    solve_one_word::Bool = !isnothing(args["target-word"])
    solve_all_words::Bool = args["everything"]
    if solve_one_word || solve_all_words
        targets::Vector{String} = solve_one_word ? [args["target-word"]] : get_words()
        find_targets(targets, scored_words, solve_one_word)
    else
        # Read in user-specified filters and apply them to the possible wordle words
        # (generate FilterRule items from filter arguments, using mapreduce instead of a loop per Claude.ai)
        filter_rules = mapreduce(parse_filter_argument, vcat, args["filters"]; init=Vector{FilterRule}())
        scored_words = reduce(apply_filter_rule, filter_rules; init=scored_words)

        # Print matching words
        for (word, score) in sort(collect(scored_words), by=last)
            @printf("%s %.2f\n", word, score)
        end
    end

end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
