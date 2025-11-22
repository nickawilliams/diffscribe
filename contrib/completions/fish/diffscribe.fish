# diffscribe fish completion
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
    command diffscribe --quantity $qty "$prefix" 2>/dev/null
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
