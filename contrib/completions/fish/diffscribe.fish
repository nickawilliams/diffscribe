# diffscribe fish completion
set -g __diffscribe_fish_status_text 'reticulating splines…'
set -g __diffscribe_fish_status_mode ''

function __diffscribe_fish_status_enabled
    if set -q DIFFSCRIBE_STATUS
        test "$DIFFSCRIBE_STATUS" != "0"
        return $status
    end
    return 0
end

function __diffscribe_fish_status_start
    if not __diffscribe_fish_status_enabled
        return 1
    end

    if status --is-interactive
        printf '\033[s\033[90m%s\033[0m\033[u' $__diffscribe_fish_status_text >&2
        set -g __diffscribe_fish_status_mode cursor
        return 0
    end

    set -g __diffscribe_fish_status_mode stderr
    printf '\r\033[90m%s\033[0m' $__diffscribe_fish_status_text >&2
    return 0
end

function __diffscribe_fish_status_finish --argument-names rc
    switch "$__diffscribe_fish_status_mode"
        case cursor
            commandline -f repaint 2>/dev/null
            if test "$rc" -ne 0
                printf '[diffscribe] completion failed\n' >&2
            end
        case stderr
            printf '\r\033[K' >&2
            if test "$rc" -ne 0
                printf '[diffscribe] completion failed\n' >&2
            end
    end
    set -g __diffscribe_fish_status_mode ''
end

function __diffscribe_fish_quantity
    if set -q DIFFSCRIBE_QUANTITY
        echo $DIFFSCRIBE_QUANTITY
    else
        echo 5
    end
end

function __diffscribe_fish_call --argument-names prefix
    if not type -q diffscribe
        return
    end
    set -l qty (__diffscribe_fish_quantity)
    set -l status_active 0
    if __diffscribe_fish_status_start
        set status_active 1
    end
    set -l raw (command diffscribe --quantity $qty "$prefix" 2>/dev/null)
    set -l rc $status
    if test $status_active -eq 1
        __diffscribe_fish_status_finish $rc
    end
    if test $rc -ne 0
        return
    end
    printf '%s\n' $raw
end

function __diffscribe_fish_commit
    set -l token (commandline -ct)
    __diffscribe_fish_call $token
end

function __diffscribe_fish_stash --argument-names subcommand
    set -l token (commandline -ct)
    __diffscribe_fish_call $token
end

complete \
  -c git \
  -n '__fish_git_using_command commit; and __fish_seen_argument -s m -l message' \
  -s m -l message \
  -r \
  -a '(__diffscribe_fish_commit)'

complete \
  -c git \
  -n '__fish_git_using_command stash; and __fish_seen_subcommand_from push; and __fish_seen_argument -s m -l message' \
  -s m -l message \
  -r \
  -a '(__diffscribe_fish_stash push)'

complete \
  -c git \
  -n '__fish_git_using_command stash; and __fish_seen_subcommand_from save; and __fish_seen_argument -s m -l message' \
  -s m -l message \
  -r \
  -a '(__diffscribe_fish_stash save)'
