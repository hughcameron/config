#!/bin/bash
# GCP Agent VM Startup Script
# Used as --metadata-from-file=startup-script for agent VMs
#
# After VM creation, deploy secrets:
#   gcloud compute instances add-metadata <INSTANCE> \
#     --project=<PROJECT> --zone=<ZONE> \
#     --metadata-from-file=age-key=$HOME/.config/chezmoi/age/keys.txt
#
#   gcloud compute ssh <INSTANCE> --project=<PROJECT> --zone=<ZONE> -- \
#     'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && chezmoi init --apply https://github.com/hughcameron/config.git'

set -e

USERNAME="hugh"
BREW="/home/linuxbrew/.linuxbrew/bin/brew"

echo "=== GCP Agent VM Startup ==="

# Create user
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /usr/bin/zsh "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
    chmod 440 /etc/sudoers.d/$USERNAME
    echo "Created user $USERNAME"
fi

# Timezone
timedatectl set-timezone Australia/Brisbane

# System packages
apt-get update
apt-get install -y \
    zsh git curl wget unzip build-essential \
    nodejs npm age \
    file ffmpeg p7zip-full poppler-utils imagemagick xclip

# Homebrew
if [ ! -f "$BREW" ]; then
    su - $USERNAME -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    su - $USERNAME -c 'echo "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"" >> ~/.profile'
    echo "Homebrew installed"
fi

# Chezmoi
su - $USERNAME -c "eval \"\$($BREW shellenv)\" && brew install chezmoi" || true

# Age key from instance metadata
AGE_DIR="/home/$USERNAME/.config/chezmoi/age"
su - $USERNAME -c "mkdir -p $AGE_DIR"
AGE_KEY=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/age-key" \
    -H "Metadata-Flavor: Google" 2>/dev/null || true)
if [ -n "$AGE_KEY" ]; then
    echo "$AGE_KEY" > "$AGE_DIR/keys.txt"
    chown $USERNAME:$USERNAME "$AGE_DIR/keys.txt"
    chmod 600 "$AGE_DIR/keys.txt"
    echo "Age key deployed from metadata"

    # If age key is present, run chezmoi init
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && chezmoi init --apply https://github.com/hughcameron/config.git" || echo "chezmoi init failed — may need GitHub SSH key"
else
    echo "No age key in metadata — deploy manually after boot"
fi

# Claude Code (native install for Linux)
su - $USERNAME -c 'curl -fsSL https://claude.ai/install.sh | bash' || true

# Clone claude repo (agents, skills, memory)
if [ ! -d "/home/$USERNAME/.claude/.git" ]; then
    su - $USERNAME -c "GIT_SSH_COMMAND='ssh -i ~/.ssh/github_vm_access -o IdentitiesOnly=yes' git clone git@github.com:hughcameron/claude.git ~/.claude" || echo "Claude repo clone failed — may need GitHub SSH key"
    su - $USERNAME -c "cd ~/.claude && git config core.sshCommand 'ssh -i ~/.ssh/github_vm_access -o IdentitiesOnly=yes'"
fi

# MCP SDK
if [ -d "/home/$USERNAME/.claude/mcp-servers" ]; then
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && cd ~/.claude/mcp-servers && npm init -y 2>/dev/null && npm install @modelcontextprotocol/sdk" || true
fi

# Brew bundle (if chezmoi deployed the Brewfile)
BREWFILE="/home/$USERNAME/.config/homebrew/brewfile.txt"
if [ -f "$BREWFILE" ]; then
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && brew bundle install --file $BREWFILE" || true
fi

# Yazi plugins
su - $USERNAME -c "eval \"\$($BREW shellenv)\" && ya pkg install" 2>/dev/null || true

# Ghostty terminfo (fixes Delete key over SSH from Ghostty terminal)
cat > /tmp/xterm-ghostty.terminfo << 'TERMINFO'
xterm-ghostty|ghostty|Ghostty,
	am, bce, ccc, hs, km, mc5i, mir, msgr, npc, xenl,
	colors#256, cols#80, it#8, lines#24, pairs#32767,
	acsc=++\,\,--..00``aaffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~,
	bel=^G, blink=\E[5m, bold=\E[1m, cbt=\E[Z, civis=\E[?25l,
	clear=\E[H\E[2J, cnorm=\E[?12l\E[?25h, cr=^M,
	csr=\E[%i%p1%d;%p2%dr, cub=\E[%p1%dD, cub1=^H,
	cud=\E[%p1%dB, cud1=^J, cuf=\E[%p1%dC, cuf1=\E[C,
	cup=\E[%i%p1%d;%p2%dH, cuu=\E[%p1%dA, cuu1=\E[A,
	cvvis=\E[?12;25h, dch=\E[%p1%dP, dch1=\E[P, dim=\E[2m,
	dl=\E[%p1%dM, dl1=\E[M, dsl=\E]2;\007, ech=\E[%p1%dX,
	ed=\E[J, el=\E[K, el1=\E[1K, flash=\E[?5h$<100/>\E[?5l,
	fsl=^G, home=\E[H, hpa=\E[%i%p1%dG, ht=^I, hts=\EH,
	ich=\E[%p1%d@, ich1=\E[@, il=\E[%p1%dL, il1=\E[L, ind=^J,
	indn=\E[%p1%dS,
	initc=\E]4;%p1%d;rgb\:%p2%{255}%*%{1000}%/%2.2X/%p3%{255}%*%{1000}%/%2.2X/%p4%{255}%*%{1000}%/%2.2X\E\\,
	invis=\E[8m, kDC=\E[3;2~, kEND=\E[1;2F, kHOM=\E[1;2H,
	kIC=\E[2;2~, kLFT=\E[1;2D, kNXT=\E[6;2~, kPRV=\E[5;2~,
	kRIT=\E[1;2C, kbs=\177, kcbt=\E[Z, kcub1=\EOD, kcud1=\EOB,
	kcuf1=\EOC, kcuu1=\EOA, kdch1=\E[3~, kend=\EOF, kent=\EOM,
	kf1=\EOP, kf10=\E[21~, kf11=\E[23~, kf12=\E[24~,
	kf13=\E[1;2P, kf14=\E[1;2Q, kf15=\E[1;2R, kf16=\E[1;2S,
	kf17=\E[15;2~, kf18=\E[17;2~, kf19=\E[18;2~, kf2=\EOQ,
	kf20=\E[19;2~, kf21=\E[20;2~, kf22=\E[21;2~,
	kf23=\E[23;2~, kf24=\E[24;2~, kf25=\E[1;5P, kf26=\E[1;5Q,
	kf27=\E[1;5R, kf28=\E[1;5S, kf29=\E[15;5~, kf3=\EOR,
	kf30=\E[17;5~, kf31=\E[18;5~, kf32=\E[19;5~,
	kf33=\E[20;5~, kf34=\E[21;5~, kf35=\E[23;5~,
	kf36=\E[24;5~, kf37=\E[1;6P, kf38=\E[1;6Q, kf39=\E[1;6R,
	kf4=\EOS, kf40=\E[1;6S, kf41=\E[15;6~, kf42=\E[17;6~,
	kf43=\E[18;6~, kf44=\E[19;6~, kf45=\E[20;6~,
	kf46=\E[21;6~, kf47=\E[23;6~, kf48=\E[24;6~,
	kf49=\E[1;3P, kf5=\E[15~, kf50=\E[1;3Q, kf51=\E[1;3R,
	kf52=\E[1;3S, kf53=\E[15;3~, kf54=\E[17;3~,
	kf55=\E[18;3~, kf56=\E[19;3~, kf57=\E[20;3~,
	kf58=\E[21;3~, kf59=\E[23;3~, kf6=\E[17~, kf60=\E[24;3~,
	kf61=\E[1;4P, kf62=\E[1;4Q, kf63=\E[1;4R, kf7=\E[18~,
	kf8=\E[19~, kf9=\E[20~, khome=\EOH, kich1=\E[2~,
	kind=\E[1;2B, kmous=\E[<, knp=\E[6~, kpp=\E[5~,
	kri=\E[1;2A, oc=\E]104\007, op=\E[39;49m, rc=\E8,
	rep=%p1%c\E[%p2%{1}%-%db, rev=\E[7m, ri=\EM,
	rin=\E[%p1%dT, ritm=\E[23m, rmacs=\E(B, rmam=\E[?7l,
	rmcup=\E[?1049l, rmir=\E[4l, rmkx=\E[?1l\E>, rmso=\E[27m,
	rmul=\E[24m, rs1=\E]\E\\\Ec, sc=\E7,
	setab=\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m,
	setaf=\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m,
	sgr=%?%p9%t\E(0%e\E(B%;\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;%?%p7%t;8%;m,
	sgr0=\E(B\E[m, sitm=\E[3m, smacs=\E(0, smam=\E[?7h,
	smcup=\E[?1049h, smir=\E[4h, smkx=\E[?1h\E=, smso=\E[7m,
	smul=\E[4m, tbc=\E[3g, tsl=\E]2;, u6=\E[%i%d;%dR, u7=\E[6n,
	u8=\E[?%[;0123456789]c, u9=\E[c, vpa=\E[%i%p1%dd,
TERMINFO
tic -x /tmp/xterm-ghostty.terminfo
rm -f /tmp/xterm-ghostty.terminfo

# Create repo directory
su - $USERNAME -c 'mkdir -p ~/github'

echo "=== GCP Agent VM startup complete ==="
