#!/bin/bash

REPO_PREFIX='https://raw.githubusercontent.com/masmu/my-dot/master'
TMP_PREFIX='/tmp'

ZSH_PLUGIN_REPOS=(
    https://github.com/zsh-users/zsh-autosuggestions
    https://github.com/zsh-users/zsh-syntax-highlighting
    https://github.com/zdharma/history-search-multi-word
)
CPU_ARCHITECTURE="$(uname -m)"

function is_url() {
    regex='(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]'
    if [[ $1 =~ $regex ]]
    then
        echo "true"
    else
        echo ""
    fi
}

function update_git_repo() {
    if [ -d "$1" ]; then
        echo "Updating $1:"
        cd "$1"
        git pull
    else
        echo "Repository '$1' not found!"
    fi
}

function install_git_repo() {
    if [ -d "$2" ]; then
        update_git_repo "$2"
    else
        echo "Installing $1 ..."
        git clone "$1" "$2"
    fi
}

function install_symlink() {
    [[ -L "$2" && -d "$1" ]] || {
        echo "Creating symlink $1 ..."
        ln -s "$1" "$2"
    }
}

function download_file() {
    if [[ ! -f "$2" || $FORCE || "$3" ]]; then
        echo "Downloading file $2 ..."
        curl -o "$2" "$1"
    fi
}

function text_append() {
    if [ -f "$1" ]; then
        if [ "$(cat "$1" | grep -F "$2" | wc -l)" -eq 0 ]; then
            echo "patching $1 ..."
            echo "$3" >> "$1"
        fi
    else
        echo "text_append: file '$1' not found!"
    fi
}

function text_replace() {
    if [ -f "$1" ]; then
        echo "patching $1 ..."
        sed -i -e "s/$2/$3/g" "$1"
    else
        echo "text_replace: file '$1' not found!"
    fi
}

function text_remove() {
    if [ -f "$1" ]; then
        sed -i "/$2/d" "$1"
    else
        echo "text_remove: file '$1' not found!"
    fi
}

function text_patch() {
    if [[ -f "$1" ]]; then
        if [[ $(is_url "$2") ]]; then
            TMP_FILE="$TMP_PREFIX/$(basename $2)"
            download_file "$2" "$TMP_FILE" true
            SOURCE="$TMP_FILE"
        else
            SOURCE="$2"
        fi
        echo "patching $1 ..."
        comm -23 <(sort "$SOURCE") <(sort "$1") >> "$1"
    else
        echo "text_patch: file '$1' not found!"
    fi
}


function backup_if_exists() {
    if [[ ! -a "$1.nobackup" && ! -a "$1.original" ]]; then
        if [[ -a "$1" ]]; then
            echo "creating backup of $1 ..."
            cp -R "$1" "$1.original"
        else
            touch "$1.nobackup"
        fi
    fi
}

function restore_backup() {
    if [[ -a "$1.original" ]]; then
        echo "restoring backup of $1 ..."
        rm -rf "$1"
        mv "$1.original" "$1"
    elif [[ -a "$1.nobackup" ]]; then
        echo "removing $1 ..."
        rm -rf "$1"
        rm "$1.nobackup"
    fi
}

function install_pkgs() {
    sudo apt-get -y install curl zsh git byobu sed xclip || {
        echo "Error during installing the dependencies!"
        exit 1
    }
}

function setup_bash() {
    backup_if_exists ~/.bashrc
    [[ -f ~/.bashrc ]] || touch ~/.bashrc
    text_append ~/.bashrc '#DISABLE_FLOW_CONTROL' \
        'stty -ixon #DISABLE_FLOW_CONTROL'
    stty -ixon
}

function setup_local_bin() {
    mkdir -p ~/.local/bin
}

function setup_micro() {
    setup_local_bin

    mkdir -p ~/.config/micro
    download_file "$REPO_PREFIX/micro/settings.json" ~/.config/micro/settings.json

    TMP_DIR="/tmp/micro/"
    EXTRACT_DIR="$TMP_DIR/extract"
    case "$CPU_ARCHITECTURE" in
        i?86) ARCH="linux32";;
        x86_64) ARCH="linux64" ;;
        armv?l) ARCH="linux-arm" ;;
    esac
    VERSION="1.4.0"
    DOWNLOAD_URL="https://github.com/zyedidia/micro/releases/download/v$VERSION/micro-$VERSION-$ARCH.tar.gz"
    mkdir -p "$EXTRACT_DIR"
    curl -o "$TMP_DIR/micro.tar.gz" -L $DOWNLOAD_URL
    tar -xvzf "$TMP_DIR/micro.tar.gz" -C "$EXTRACT_DIR"
    find "$EXTRACT_DIR" -iname "micro" -exec cp "{}" ~/.local/bin \;
}

function setup_byobu() {
    backup_if_exists ~/.byobu
    [[ -d ~/.byobu ]] || mkdir ~/.byobu
    [[ -f ~/.byobu/tmux.conf ]] && rm ~/.byobu/.tmux.conf
    install_symlink ~/.tmux.conf ~/.byobu/.tmux.conf
    byobu-disable-prompt
}

function setup_tmux() {
    backup_if_exists ~/.tmux.conf
    [[ -f ~/.tmux.conf ]] || touch ~/.tmux.conf
    text_patch ~/.tmux.conf "$REPO_PREFIX/tmux/.tmux.conf"
}

function setup_zsh() {
    backup_if_exists ~/.oh-my-zsh
    backup_if_exists ~/.zshrc
    backup_if_exists ~/.zshenv

    install_git_repo git://github.com/robbyrussell/oh-my-zsh.git ~/.oh-my-zsh

    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
    text_replace ~/.zshrc \
        'ZSH_THEME="robbyrussell"' \
        'ZSH_THEME="agnoster"'
    for GIT_URL in ${ZSH_PLUGIN_REPOS[*]}
    do
        GIT_FOLDER="$(basename $GIT_URL)"
        if [ ! -d ~/.zsh/$GIT_FOLDER ]; then
            install_git_repo $GIT_URL ~/.zsh/$GIT_FOLDER
        fi
        LINE="source ~/.zsh/$GIT_FOLDER/$GIT_FOLDER.plugin.zsh"
        text_append ~/.zshrc "$LINE" "$LINE"
    done
    text_append ~/.zshrc '#SOURCE_PROFILE' \
        "[[ -e ~/.profile ]] && emulate sh -c 'source ~/.profile' #SOURCE_PROFILE"
    text_append ~/.zshrc '#KEY-HOME-FIX' \
        'bindkey "^[[1~" beginning-of-line #KEY-HOME-FIX'
    text_append ~/.zshrc '#KEY-END-FIX' \
        'bindkey "^[[4~" end-of-line #KEY-END-FIX'

    [[ -f ~/.zshenv ]] || touch ~/.zshenv
    text_append ~/.zshenv '#DISABLE_FLOW_CONTROL' \
        'stty -ixon #DISABLE_FLOW_CONTROL'
}

function install_all() {
    if [ ! $SKIP_PACKAGES ]; then
        install_pkgs
    fi
    setup_bash
    setup_byobu
    setup_zsh
    setup_tmux
    setup_micro
    echo "Installation done!"
}

function remove() {
    restore_backup ~/.bashrc
    restore_backup ~/.byobu
    restore_backup ~/.zshrc
    restore_backup ~/.zshenv
    restore_backup ~/.tmux.conf
    restore_backup ~/.oh-my-zsh
    echo "Remove done!"
}

function clean() {
    remove
    [[ -d ~/.oh-my-zsh ]] && rm -Rf ~/.oh-my-zsh
    [[ -d ~/.byobu ]] && rm -Rf ~/.byobu
    [[ -d ~/.zsh ]] && rm -Rf ~/.zsh
    [[ -f ~/.zshrc ]] && rm ~/.zshrc
    [[ -f ~/.zshenv ]] && rm ~/.zshenv
    [[ -f ~/.tmux.conf ]] && rm ~/.tmux.conf
    [[ -d ~/.oh-my-zsh ]] && rm -Rf ~/.oh-my-zsh
    [[ -f ~/.local/bin/micro ]] && rm ~/.local/bin/micro
    echo "Clean done!"
}

SKIP_PACKAGES=""
FORCE=""

while [ "$#" -gt "0" ]; do
    case $1 in
    --clean)
        clean
        exit 0
    ;;
    --remove)
        remove
        exit 0
    ;;
    --editor)
        setup_micro
        exit 0
    ;;
    --skip-packages)
        SKIP_PACKAGES="1"
        shift
    ;;
    --force)
        FORCE="1"
        shift
    ;;
    *)
        echo "Unknown option '$1'!"
        exit 1
    ;;
    esac
done

install_all
