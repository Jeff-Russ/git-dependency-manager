#!/usr/bin/env zsh

# export GDM_REGISTRY="$HOME/.gdm_registry"
# export GDM_VER='1.0beta'
# export GDM="$GDM_REGISTRY/gdm-$GDM_VER.zsh"

export GDM_REGISTRY="$HOME/.shell_extensions/GIT_REPO_DEPS/git-dependency-manager/test/gdm_required" #TEST
export GDM_VER='1.0beta' #TEST
export GDM="${GDM:=${0:a:h:h}/dist/gdm-test.zsh}" #TEST

# Add any setup functions here

config() {
  # gdm require juce-framework/JUCE#develop
  gdm require juce-framework/JUCE#develop
  gdm require shitmakers/shit#main
}

# DO NOT MODIFY THIS LINE OR BELOW

if ! ("$GDM" --compat="$GDM_VER" >/dev/null 2>&1) ; then
  echo "loading gdm..." ; return #TEST
  mkdir -p "$GDM:h" && curl "https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/dist/$GDM:t" > "$GDM" ;
  if ! ("$GDM" --compat=$GDM_VER >/dev/null 2>&1) ; then echo  "GDM Cannot load version $GDM_VER" >&2 ; return 1 ; fi
fi

config.lock() {

}

(($#)) && source "$GDM" "$@"
