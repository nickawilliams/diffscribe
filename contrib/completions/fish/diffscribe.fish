# diffscribe: fish completion hook for "git commit" and "git stash" messages.
# Load this after fish's built-in git completion (fish automatically sources
# files placed in ~/.config/fish/completions/).

function __diffscribe_fish_log --description 'Optional debug log'
    if test -z "$DIFFSCRIBE_DEBUG"
        return
    end
    echo "[diffscribe] $argv" >&2
end

function __diffscribe_fish_clean_prefix --description 'Strip surrounding quotes'
    set -l prefix $argv[1]
    set prefix (string trim --chars='"' -- $prefix)
    set prefix (string trim --chars="'" -- $prefix)
    echo $prefix
end

function __diffscribe_fish_flag_prefix --description 'Detect -m/--message prefixes'
    set -l prev $argv[1]
    set -l current $argv[2]
    switch "$prev"
        case "-m" "--message"
            echo $current
            return 0
    end

    if string match -rq '^--message=' -- "$current"
        echo (string replace --regex '^--message=' '' -- "$current")
        return 0
    else if string match -rq '^-m.+$' -- "$current"
        echo (string replace --regex '^-m' '' -- "$current")
        return 0
    end

    return 1
end

function __diffscribe_fish_should_complete --description 'Detect if cursor is at a diffscribe-able message' --argument-names mode
    set -l tokens (commandline --tokenize --cut-at-cursor)
    set -l current (commandline --current-token)
    set -l count (count $tokens)
    set -l prev ""
    set -l trimmed $tokens
    if test $count -gt 0
        set prev $tokens[-1]
        if test "$prev" = "$current"
            if test $count -gt 1
                set prev $tokens[-2]
            else
                set prev ""
            end
            set -e trimmed[-1]
        end
    end

    set -l prefix
    if test "$mode" = "commit"
        if set prefix (__diffscribe_fish_flag_prefix "$prev" "$current")
            set prefix (__diffscribe_fish_clean_prefix "$prefix")
            set -g __diffscribe_context commit
            set -g __diffscribe_prefix "$prefix"
            __diffscribe_fish_log "commit intercept prefix='$prefix'"
            return 0
        end
        return 1
    end

    if test "$mode" = "stash"
        if set prefix (__diffscribe_fish_detect_stash_push "$prev" "$current" $tokens)
            set prefix (__diffscribe_fish_clean_prefix "$prefix")
            set -g __diffscribe_context stash
            set -g __diffscribe_prefix "$prefix"
            __diffscribe_fish_log "stash push prefix='$prefix'"
            return 0
        end

        if set prefix (__diffscribe_fish_detect_stash_save "$current" $tokens)
            set prefix (__diffscribe_fish_clean_prefix "$prefix")
            set -g __diffscribe_context stash
            set -g __diffscribe_prefix "$prefix"
            __diffscribe_fish_log "stash save prefix='$prefix'"
            return 0
        end
    end

    return 1
end

function __diffscribe_fish_candidates --description 'Call diffscribe for suggestions'
    if not set -q __diffscribe_prefix
        return
    end
    set -l prefix $__diffscribe_prefix
    set -e __diffscribe_prefix

    set -l context "commit"
    if set -q __diffscribe_context
        set context $__diffscribe_context
        set -e __diffscribe_context
    end

    if not type -q diffscribe
        __diffscribe_fish_log "diffscribe not found in PATH"
        return
    end

    set -l output
    if test "$context" = "stash"
        set -l args
        if set -q __diffscribe_stash_args[1]
            set args $__diffscribe_stash_args
        end
        set -e __diffscribe_stash_args
        set -l oid (command git stash create $args 2>/dev/null)
        if test -z "$oid"
            return
        end
        set output (env DIFFSCRIBE_STASH_COMMIT=$oid diffscribe "$prefix" 2>/dev/null)
    else
        set output (command diffscribe "$prefix" 2>/dev/null)
    end

    if test -z "$output"
        return
    end
    printf '%s\n' $output
end

function __diffscribe_fish_find_index --description 'Find index of token' --argument-names needle
    set -l tokens $argv
    set -l count (count $tokens)
    for i in (seq 1 $count)
        if test $tokens[$i] = $needle
            echo $i
            return 0
        end
    end
    return 1
end

function __diffscribe_fish_collect_stash_push_args --description 'Build args for git stash create' --argument-names tokens
    set -l count (count $tokens)
    set -l stash_idx (__diffscribe_fish_find_index stash $tokens)
    or return 1
    set -l push_idx -1
    for i in (seq (math $stash_idx + 1) $count)
        if test $tokens[$i] = 'push'
            set push_idx $i
            break
        end
    end
    if test $push_idx -eq -1
        return 1
    end

    set -l args
    for i in (seq (math $stash_idx + 1) (math $push_idx - 1))
        set args $args $tokens[$i]
    end

    set -l skip_next 0
    set -l after_dd 0
    for i in (seq (math $push_idx + 1) $count)
        set -l token $tokens[$i]
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end
        switch $token
            case '-m' '--message'
                set skip_next 1
                continue
            case '--message=*'
                continue
        end
        if string match -rq '^-m.+$' -- $token
            continue
        end
        if test $token = '--'
            set after_dd 1
            set args $args $token
            continue
        end
        if test $after_dd -eq 1
            set args $args $token
            continue
        end
        if test $token = 'push'
            continue
        end
        set args $args $token
    end

    echo $args
end

function __diffscribe_fish_detect_stash_push --description 'Detect git stash push message' --argument-names prev current
    set -l tokens $argv
    if not set -l prefix (__diffscribe_fish_flag_prefix "$prev" "$current")
        return 1
    end

    set -l args (__diffscribe_fish_collect_stash_push_args $tokens)
    or return 1
    set -g __diffscribe_stash_args $args
    echo $prefix
    return 0
end

function __diffscribe_fish_detect_stash_save --description 'Detect git stash save message' --argument-names current
    set -l tokens $argv
    set -l count (count $tokens)
    if test $count -lt 2
        return 1
    end

    set -l stash_idx (__diffscribe_fish_find_index stash $tokens)
    or return 1
    set -l save_idx -1
    for i in (seq (math $stash_idx + 1) $count)
        if test $tokens[$i] = 'save'
            set save_idx $i
            break
        end
    end
    if test $save_idx -eq -1
        return 1
    end

    set -l args
    for i in (seq (math $save_idx + 1) (math $count - 1))
        set -l token $tokens[$i]
        if string match -rq '^-{1,2}.+' -- $token
            set args $args $token
            continue
        end
        return 1
    end

    if string match -rq '^-{1,2}.+' -- "$current"
        return 1
    end

    set -g __diffscribe_stash_args $args
    printf '%s\n' "$current"
    return 0
end

complete -c git \
    -n '__fish_git_using_command commit; and __diffscribe_fish_should_complete commit' \
    -a '(__diffscribe_fish_candidates)' \
    -f

complete -c git \
    -n '__fish_git_using_command stash; and __diffscribe_fish_should_complete stash' \
    -a '(__diffscribe_fish_candidates)' \
    -f
