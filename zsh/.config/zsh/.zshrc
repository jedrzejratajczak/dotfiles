# --- Powerlevel10k instant prompt ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Zinit ---
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# --- Powerlevel10k (sync — instant prompt needs it immediately) ---
zinit ice depth=1
zinit light romkatv/powerlevel10k
[[ -f ${ZDOTDIR}/.p10k.zsh ]] && source ${ZDOTDIR}/.p10k.zsh

# --- Plugins (turbo — loaded async after prompt appears) ---
zinit ice wait"0a" lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait"0b" lucid
zinit light zsh-users/zsh-completions

zinit ice wait"0c" lucid atinit"zicompinit; zicdreplay"
zinit light zsh-users/zsh-syntax-highlighting

zinit ice wait"0d" lucid
zinit snippet /usr/share/fzf/key-bindings.zsh

zinit ice wait"0d" lucid
zinit snippet /usr/share/fzf/completion.zsh

zinit ice wait"0e" lucid
zinit light Aloxaf/fzf-tab

# --- History (XDG-compliant) ---
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p ${HISTFILE:h}
HISTSIZE=50000
SAVEHIST=50000
setopt appendhistory sharehistory hist_ignore_all_dups hist_ignore_space hist_reduce_blanks
setopt extended_glob interactive_comments no_beep

# --- Key bindings ---
bindkey -e
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

# --- Completions ---
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# --- Aliases ---
alias ls='eza --icons'
alias ll='eza -lah --icons'
alias cat='bat --plain --paging=never'
alias grep='grep --color=auto'
alias v='nvim'
alias y='yazi'

# --- Path ---
typeset -U path
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim

# --- Local overrides (machine-specific, not tracked in git) ---
[[ -f ${ZDOTDIR}/local.zsh ]] && source ${ZDOTDIR}/local.zsh
