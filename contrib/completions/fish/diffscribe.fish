# diffscribe: fish completion hook for "git commit -m/--message".
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

function __diffscribe_fish_should_complete --description 'Detect if cursor is at commit message'
    set -l tokens (commandline --tokenize --cut-at-cursor)
    set -l current (commandline --current-token)
    set -l count (count $tokens)
    set -l prev ""
    if test $count -gt 0
        set prev $tokens[-1]
        if test "$prev" = "$current" -a $count -gt 1
            set prev $tokens[-2]
        end
    end

    set -l prefix ""
    switch "$prev"
        case "-m" "--message"
            set prefix $current
    end

    if test -z "$prefix"
        if string match -rq '^--message=' -- "$current"
            set prefix (string replace --regex '^--message=' '' -- "$current")
        else if string match -rq '^-m.+$' -- "$current"
            set prefix (string replace --regex '^-m' '' -- "$current")
        else
            return 1
        end
    end

    set -l clean (__diffscribe_fish_clean_prefix "$prefix")
    set -g __diffscribe_prefix "$clean"
    __diffscribe_fish_log "intercept prefix='$prefix' clean='$clean'"
    return 0
end

function __diffscribe_fish_candidates --description 'Call diffscribe for suggestions'
    if not set -q __diffscribe_prefix
        return
    end
    set -l prefix $__diffscribe_prefix
    set -e __diffscribe_prefix

    if not type -q diffscribe
        __diffscribe_fish_log "diffscribe not found in PATH"
        return
    end

    set -l output (command diffscribe "$prefix" 2>/dev/null)
    if test -z "$output"
        return
    end
    printf '%s\n' $output
end

complete -c git \
    -n '__fish_git_using_command commit; and __diffscribe_fish_should_complete' \
    -a '(__diffscribe_fish_candidates)' \
    -f
