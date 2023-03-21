#!/usr/bin/env zsh

# export GDM_REGISTRY="$HOME/.gdm_registry"
# export GDM_VER='1.0beta'
# export GDM="$GDM_REGISTRY/gdm-$GDM_VER.zsh"

export GDM_REGISTRY="$HOME/.shell_extensions/GIT_REPO_DEPS/git-dependency-manager/test/gdm_require" #TEST
export GDM_VER='1.0beta' #TEST
export GDM="${GDM:=${0:a:h:h}/dist/gdm-test.zsh}" #TEST

# Add any setup functions here

require() {
  # Example:
  # gdm require juce-framework/JUCE#develop as=juce-dev setup='rm -rf .git'
  gdm require juce-framework/JUCE#develop
  gdm require shitmakers/shit#main
} 

# DO NOT MODIFY THIS LINE OR BELOW

if ! [[ -f "$GDM" ]] ; then
  mkdir -p "$GDM:h" && curl "https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/dist/$GDM:t" > "$GDM" ;
fi

require.lock() {

}

(($#)) && { source "$GDM" "$@" ; return $? ; }
return 0
