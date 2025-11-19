# diffscribe: inject git commit/stash message completion via diffscribe complete
# Load after your normal git completion (`autoload -Uz compinit; compinit`).

[[ -z ${ZSH_VERSION-} ]] && return 0

_diffscribe_git_dir=${${(%):-%N}:h}
_diffscribe_git_lib="${_diffscribe_git_dir}/diffscribe.lib.zsh"
if [[ ! -r $_diffscribe_git_lib ]]; then
	_diffscribe_git_lib="${_diffscribe_git_dir}/../diffscribe.lib.zsh"
fi
if [[ ! -r $_diffscribe_git_lib ]]; then
	print -ru2 -- "diffscribe: missing diffscribe.lib.zsh"
	return 0
fi

source "$_diffscribe_git_lib"
diffscribe_wrap_git_completion
unset _diffscribe_git_dir _diffscribe_git_lib
