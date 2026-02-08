def --env y [...args] {
	let tmp = (mktemp -t "yazi-cwd.XXXXXX")
	^yazi ...$args --cwd-file $tmp
	let cwd = (open $tmp)
	if $cwd != $env.PWD and ($cwd | path exists) {
		cd $cwd
	}
	rm -fp $tmp
}

$env.config.keybindings = ($env.config.keybindings | append {
  name: yazi
  modifier: control
  keycode: char_e
  mode: [emacs vi_normal vi_insert]
  event: {
    send: ExecuteHostCommand
    cmd: "y"
  }
})

