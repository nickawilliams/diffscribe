# diffscribe Oh-My-Zsh Plugin

This plugin wraps the existing `git` completion shipped by Oh-My-Zsh (gitfast or stock) so that
`git commit -m/--message` and `git stash` message suggestions flow through `diffscribe complete`.

## Installation

1. Copy the plugin script **and** shared helper into your custom OMZ plugins directory:

   ```sh
   mkdir -p ~/.oh-my-zsh/custom/plugins/diffscribe
   cp contrib/oh-my-zsh/diffscribe.plugin.zsh ~/.oh-my-zsh/custom/plugins/diffscribe/
   cp contrib/completions/zsh/diffscribe.lib.zsh ~/.oh-my-zsh/custom/plugins/diffscribe/
   ```

2. Add `diffscribe` to the `plugins=(...)` list in `~/.zshrc`, ideally after other git-related plugins
   (e.g. `git`, `gitfast`).
3. Reload your shell (`exec zsh`) or run `source ~/.zshrc` to pick up the new plugin.

## Notes

- The plugin assumes `diffscribe` is already on your `PATH`.
- Because it wraps `_git`, ensure the plugin loads after whichever OMZ git plugin you use so it sees
  the final completion function.
- To remove the plugin, delete the custom plugin directory and remove `diffscribe` from the `plugins`
  list.
