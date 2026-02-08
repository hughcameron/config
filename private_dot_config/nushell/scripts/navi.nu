
export-env {
  if (which navi | is-empty) {
    return
  }

  if not ((navi info config-path) | path exists) {
    if not ((navi info config-path) | path dirname | path exists) {
      mkdir (navi info config-path | path dirname)
    }
    touch (navi info config-path)
  }

  # Get cheats paths from navi config
  let navi_config = (open (navi info config-path))
  let cheats_paths = ($navi_config | get --optional cheats.paths | default [])

  if not ($cheats_paths | is-empty) {
    $env.NAVI_PATH = ($cheats_paths | str join (char esep))
  }

  $env.config.keybindings = ($env.config.keybindings | append {
    name: navi
    modifier: control
    keycode: char_g
    mode: [emacs vi_normal vi_insert]
    event: {
      send: ExecuteHostCommand
      cmd: "_navi_widget"
    }
  })

  $env.config.keybindings = ($env.config.keybindings | append {
    name: navi
    modifier: control
    keycode: char_h
    mode: [emacs vi_normal vi_insert]
    event: {
      send: ExecuteHostCommand
      cmd: "_navi_widget --display"
    }
  })
}

export def _navi_widget [--run, --display] {
  let navi_config = (open (navi info config-path))
  let navi_command = ($navi_config | get --optional 'shell' | default { command: null } | get --optional command | default 'bash')
  let cheats_paths = ($navi_config | get --optional cheats.paths | default [])

  let input = commandline
  if ($env | get --optional NAVI_ORIGINAL_PATH | is-empty) and (not ($cheats_paths | is-empty)) {
    $env.NAVI_PATH = ($cheats_paths | str join (char esep))
  }
  let last_command = ($input | navi fn widget::last_command)
  let result = if ($last_command == "") { navi --print } else { navi --print --query $last_command } | str trim

  if $result == "" {
    return
  }
  if $display {
    commandline edit -r $"^($navi_command) -c '($result)'"
  } else {
    commandline edit -r $result
  }
  ignore
}
