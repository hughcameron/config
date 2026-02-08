$env.config.keybindings = ($env.config.keybindings | append {
  name: helix
  modifier: control
  keycode: char_k
  mode: [emacs vi_normal vi_insert]
  event: {
    send: ExecuteHostCommand
    cmd: "hx"
  }
})

