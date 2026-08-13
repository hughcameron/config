# Pull subcommands and options out of a CLI's --help output.
# Emits "cmd<TAB>name<TAB>description" / "opt<TAB>flag<TAB>description".
# Run with -v loose=1 for help text that lists flags under no heading at all.
# Used by the _help_generic zsh completer alongside it.

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function emit(t, n, d,   i, k, parts, tok) {
  if (n == "") return
  k = split(n, parts, /[,][ \t]*|[ \t]+/)
  for (i = 1; i <= k; i++) {
    tok = parts[i]
    sub(/=.*$/, "", tok)      # --opt=VALUE -> --opt
    sub(/:$/, "", tok)        # "auth:" (gh style) -> auth
    if (tok ~ /\//) continue  # -e/--regexp, seen in prose lines
    if (t == "opt") {
      if (tok !~ /^--?[A-Za-z0-9]/) continue
    } else {
      if (tok !~ /^[A-Za-z0-9]/) continue
    }
    gsub(/:/, "\\:", tok)
    print t "\t" tok "\t" d
  }
}

function flush() { if (pend != "") { emit(ptype, pend, pdesc); pend = ""; pdesc = "" } }

function split_entry(body) {
  if (match(body, /[ \t][ \t]+/)) {           # name and description on one line
    pend  = trim(substr(body, 1, RSTART - 1))
    pdesc = trim(substr(body, RSTART + RLENGTH))
  } else {                                    # description follows, indented
    pend  = trim(body)
    pdesc = ""
  }
}

BEGIN { sect = ""; base = -1 }

{ line = $0; sub(/\r$/, "", line) }

line ~ /^[ \t]*$/ { flush(); next }

loose {
  match(line, /^[ \t]*/); ind = RLENGTH
  body = substr(line, ind + 1)
  if (body !~ /^-/) {
    if (pend != "" && pdesc == "" && ind > pind) pdesc = trim(body)
    next
  }
  flush()
  split_entry(body)
  ptype = "opt"; pind = ind
  next
}

# "Options:", "Available Commands:", or a bare uppercase "CORE COMMANDS".
line ~ /^[ \t]*[A-Za-z][A-Za-z ]*:[ \t]*$/ || line ~ /^[A-Z][A-Z0-9 ]*$/ {
  flush()
  h = tolower(line)
  gsub(/[ \t]/, "", h)
  sub(/:$/, "", h)
  base = -1
  if (h ~ /(commands|subcommands)$/) sect = "cmd"
  else if (h ~ /(options|flags)$/) sect = "opt"
  else sect = ""
  next
}

sect == "" { next }

{
  match(line, /^[ \t]*/); ind = RLENGTH
  body = substr(line, ind + 1)

  if (base < 0) base = ind

  if (ind > base) {                           # continuation of the entry above
    if (pend != "" && pdesc == "") pdesc = trim(body)
    next
  }

  flush()
  split_entry(body)
  ptype = sect
}

END { flush() }
