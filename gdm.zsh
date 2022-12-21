#!/usr/bin/env zsh

# Copyright (c) 2022, Jeff Russ
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted (subject to the limitations in the
# disclaimer below) provided that the following conditions are met:
# 
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.

#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the
#    distribution.
#
#  * Neither the name of <Owner Organization> nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# NO EXPRESS OR IMPLIED LICENSES TO ANY PARTY'S PATENT RIGHTS ARE
# GRANTED BY THIS LICENSE.  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT
# HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 


GDM_CMD_DIR=$(dirname -- "${(%):-%N}")
# NOTE ${(%):-%N} is zsh's equivalent to ${BASH_SOURCE[0]} (is is the current script's path)

gdm-conf-template() {
  cat << 'CONFDOC'
gdm-conf() {
# Each line in HEREDOC is parameterized by same rules as arguments
#   to shell command (the delimiter is any non-quoted space(s)) 
#   with comments removed (any string with # before it-including inlined).
#   
# The first parameter is the remote url of the repository dependency.
#   It should be the argument to `git clone` AND, should also match 
#   (after cloning and cd'ing to it), the value returned from:
#      git config --get remote.origin.url
#   However, if "user/repo" is supplied, "https://github.com/user/repo.git"
#   is assumed. ".git" will always be appended if not found. Likewise 
#   "domain.com/repo" becomes "https://domain.com/repo.git".
#   
# The second parameter (optional - pass "#" in quotes to skip) should
#   be a branch name you want to use. Skipping this parameter by passing
#   "#" chooses the default branch, which is usually "main" or "master".
#   
# The third parameter (optional - pass "#" to skip) is a commit log 
#   search string, meaning what you pass as this argument will be 
#   searched for in the commit log and the first match will be the commit
#   you need. The log format being searched is the return from this:
#     git --no-pager log --tags --pretty='%h%d %as (%an) %s'
#   If the repository commit pushed a tag "7.0.3", this should appear
#   in the log as "tag: 7.0.3". This log format uses short hashes so 
#   you can target them instead (for commits between tagged releases).
#   If the search string is not found, git pull is run on the branch 
#   and the search is run. If the search fails again, the most recent 
#   is used. If you skip this parameter the most current commit 
#   (after pull) will be used.
#   
# The forth parameter (optional - pass "#" to skip) can be provided 
#   a (new) directory name within the $GDM_STORE_DIR to clone to repository 
#   to instead of the default (which is the name of the repository: 
#   the portion after the last / and before .git in the first parameter).
#   Renaming can be helpful if you are working off of two versions (commit 
#   points or branches) in a given the repository as a dependency as having
#   two copies speeds up switching projects as each downloaded clone will 
#   already be pointing to the branch and commit you need.
#   If you'd like to skip this parameter (so you can pass hook(s))
#   and just use the most current commit (after pull), pass "#"
#   
# The fifth and subsequent parameters (all optional) are shell commands
#   that will be run after each dependency is set up These hooks are
#   useful for any setup you needed per-dependency, such as building  
#   dependency's source. You can define these commands a function in this 
#   file or anywhere, so long as it is available in the shell session. 
#   Each is executed in the directory (within $GDM_STORE_DIR) where the 
#   repository lives. This directory path is also passed as $1 to the 
#   command and the path to this config file's parent directory is passed 
#   as $2.
#   IMPORTANT: There is a build-in hook called gdm-linker which places a
#   link to the dependency in your <project-root>/GDM_MODULES/ directory
#   (which is created if not present). This hook is only run if you 
#   provide no hook but, if you do provide hooks and you still want this
#   linking, you can pass "gdm-linker" as a hook or call it from within a
#   provided hook. Likewise, If you want no hooks and no linking, pass 
#   "no-hooks" as defined below.
cat << 'HEREDOC'
# Example
juce-framework/JUCE develop "(tag: 7.0.0)" "JUCE_v7" "#"
HEREDOC
}

# place post-hooks here:

no-hooks(){ return 0; } 

CONFDOC
}


gdm-linker() {
  local repo_dep_path="$1"
  local requester_path="$2"
  local repo_dirname=${repo_dep_path:t:r}
  local requester_modules_path="${requester_path}/$GDM_MODULES_DIRNAME"
  if ! [ -d "$requester_modules_path" ] ; then
    if ! mkdir "$requester_modules_path" ; then 
      printf "ERROR gdm-linker could not create ${requester_modules_path}! \n" >&2 
      return 1
    fi
  elif [ -d "${requester_modules_path}/${repo_dirname}" ] ; then
    rm -rf "${requester_modules_path}/${repo_dirname}"
  fi
  echo "sourrce: $repo_dep_path"
  echo "destin: ${requester_modules_path}/${repo_dirname}"

  # Options to hard link:
  # cp -al $src $dest # https://unix.stackexchange.com/a/202431
  # cp -lR $src $dest # https://superuser.com/a/1523307
  local result
  if ! result=$(cp -al "$repo_dep_path" "${requester_modules_path}/${repo_dirname}" 2>&1); then
    printf "ERROR (gdm-linker): ${result}\n" >&2
    return 1
  fi
}

gdm () {
  local CALLER_DIR=$(pwd)

  declare -A ARGS # all valid argument go here (except --help).
  ARGS[initialize]='^[-]{0,2}init.*$'
  ARGS[configure]='^[-]{0,2}conf.*$'
  # ARGS[clean_modules]='^[-]{0,2}clean([=-]modules|[=-]local)?$'
  # ARGS[clean_store]='^[-]{0,2}clean([=-]store|[=-]glob|[=-]global)$'
  ARGS[list_modules]='^[-]{0,2}(list|ls)([=-]modules|[=-]local)?$'
  # ARGS[list_store]='^[-]{0,2}(list|ls)([=-]store|[=-]glob|[=-]global)$'


  # An anonymous function (self executing) to check for invalid arguments:
  local not_valid_arg='() {
    for f in $ARGS ; do
      [[ "$1" =~ $f ]] && return 1;
    done;
    return 0;
  }'

  if eval ${not_valid_arg} "$1" ; then
    printf "Usage: call with\n  --init    to generate empty configuration file or with\n  --conf    to read existing configuration\n"
    printf "By default, dependencies installed will be placed in ~/GDM_STORE/ but\n"
    printf "you can choose your own location by adding to your ~/.zshrc the following:\n  export GDM_STORE_DIR=\"/desired/path/to/directory/\"\n"
    return 0
  fi

  local gdm_verify='() {
    if ! (( ${+GDM_STORE_DIR} )) ; then
      export GDM_STORE_DIR="$HOME/GDM_STORE"
    fi
    if ! [ -d "$GDM_STORE_DIR" ] ; then
      if ! mkdir "$GDM_STORE_DIR" ; then 
        ! (($@[(Ie)--quiet-fail])) && printf "ERROR in ${GDM_CMD_DIR}: mkdir ${GDM_STORE_DIR} failed.\n"  >&2 
        unset GDM_STORE_DIR
        return 1
      fi
    else
      ! (($@[(Ie)--quiet-pass])) && printf "GDM_STORE_DIR=${GDM_STORE_DIR}\n"
    fi
    if ! (( ${+GDM_MODULES_DIRNAME} )) ; then
      ! (($@[(Ie)--quiet-pass])) && printf "setting GDM_MODULES_DIRNAME \n"
      export GDM_MODULES_DIRNAME="GDM_MODULES"
    fi
    ! (($@[(Ie)--quiet-pass])) && printf "GDM_MODULES_DIRNAME=${GDM_MODULES_DIRNAME}\n"
    return 0
  }'

  if ! eval ${gdm_verify} "--quiet-pass" && return 1;

  #-------------------------------------------------------------------------------------------
  # Generate template of gdm-conf.zsh (although they could just make it themselves)
  if [[ "$1" =~ ${ARGS[initialize]} ]] ; then 
    local gdm_conf_file="${CALLER_DIR}/gdm-conf.zsh"
    [[ -f "$gdm_conf_file" ]] && grep -q '[^[:space:]]' "$gdm_conf_file" && 
      printf "./gdm-conf.zsh already exists and is not empty!\nTo run file's configuration:\n  gdm --conf\n" >&2 && 
      return 1;
    gdm-conf-template > "${CALLER_DIR}/gdm-conf.zsh"
    printf "${CALLER_DIR}/gdm-conf.zsh configuration file generated.\n"
    return 0

  #-------------------------------------------------------------------------------------------
  # Read currently existing configuration file and set up all dependencies 
  # (usually for a given project unless they bypass the gdm-linker)
  elif [[ "$1" =~ ${ARGS[configure]} ]] ;then 
    
    ! [[ -f "./gdm-conf.zsh" ]] && printf "Error: No gdm-conf.zsh was found!" >&2 && return 1;
    source ./gdm-conf.zsh

    local required_deps=("${(f)$(gdm-conf)}")
    printf "${#required_deps[@]} requirements read.\n"

    local errors=()
    for dep in $required_deps ;
    do
      local dep_params=( ${(Q)${(Z+C+)dep}} )
      [[ ${#dep_params[@]} -eq 0 ]] && continue; # empty or commented line in list of deps
      printf "------------------------------------------------------------\n${dep_params}\n"

      #.... clone repo or cd to it ..................................

      local remote_url=$dep_params[1]
      [[ "$remote_url" != *".git" ]] && remote_url="${remote_url}.git"

      local repo_dirname=$dep_params[4]
      [[ -z "$repo_dirname" ]] || [[ "$repo_dirname" == "#" ]] && repo_dirname=${remote_url:t:r} 

      cd "$GDM_STORE_DIR"

      if ! [ -d "${GDM_STORE_DIR}/${repo_dirname}" ] ; then 
        # validate that $remote_url can be cloned:
        if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
          local fwslashes=$(echo "$remote_url" | grep -o "/"  | wc -l | xargs)

          if [[ $fwslashes == 1 ]] ; then   # github is assumed...
            remote_url="https://github.com/$remote_url"
          elif [[ $fwslashes == 2 ]] ; then # incomplete url but with domain...
            remote_url="https://$remote_url"
          else
            errors+=("  Skipped: ${dep_params}\n   Reason: Cannot clone \"$remote_url\"\n")
            printf "ERROR: Cannot clone \"$remote_url\"\n" >&2
            continue
          fi

          if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
            errors+=("  Skipped: ${dep_params}\n   Reason: Cannot clone \"$remote_url\"\n")
            printf "ERROR: Cannot clone \"$remote_url\"\n" >&2
            continue
          fi
        fi
        if ! git clone "$remote_url" "$repo_dirname" ; then
          errors+=("  Skipped: ${dep_params}\n   Reason: Cannot clone \"$remote_url\"\n")
          printf "ERROR: Cannot clone \"$remote_url\"\n" >&2
          continue
        fi
      fi
      cd "$repo_dirname"
      
      #.... switch to branch, if specifed ...........................

      local branch=$dep_params[2]
      local current_branch=$(git rev-parse --abbrev-ref HEAD) # if head is detached, current_branch will be "HEAD"
      local remote_names=("${(f)$(git remote)}")
      local origin_name=$( (($remote_names[(Ie)origin])) && echo origin || echo "${remote_names[1]}" )
      local pull_warning=""

      if [[ -z "$branch" ]] || [[ "$branch" == "#" ]] || [[ "$branch" == "HEAD" ]] || [[ "$current_branch" == "HEAD" ]] ; then
        # Set to default branch (usually main or master).
        branch=$(git remote show "$(git config --get remote.origin.url)" | sed -n '/HEAD branch/s/.*: //p')
        #  if we're in detached head state ("$current_branch" == "HEAD"), it will be fixed when we run
        # git checkout "$branch"
        # This if block assumes the default branch was not deleted locally!!! (probably safe though)
      fi
      if [[ "$branch" != "$current_branch" ]] ; then
        local loc_branches=("${(f)$(git branch --format='%(refname:short)')}")
        if ! (($loc_branches[(Ie)$branch])) ; then # If the desired $branch was never pulled to local repo...
          if ! git pull "$origin_name" "$branch" ; then
            errors+=("  Skipped: ${dep_params}\n   Reason: Execution of the following failed: git pull ${origin_name} ${branch}\n")
            printf "ERROR: Execution of the following failed: git pull ${origin_name} ${branch}\n" >&2
            continue
          fi
        fi
        if ! git checkout "$branch" ; then
          errors+=("  Skipped: ${dep_params}\n   Reason:  Execution of the following failed: git checkout ${branch}\n")
          printf "ERROR: Execution of the following failed: git checkout ${branch}\n" >&2
          continue
        fi
      elif ! git pull "$origin_name" "$branch" ; then
        # We still pull even though the branch was found locally. But we can recover if this fails by using local branch.
        errors+=("  Warning: \`git pull ${origin_name} ${branch}\` failed but local branch was found and will be used.\n")
        printf "WARNING: \`git pull ${origin_name} ${branch}\` failed but local branch was found and will be used.\n"
      fi

      #.... switch commit, if specifed ..............................

      local commit=$dep_params[3]

      if ! [[ -z "$commit" ]] && [[ "$commit" != "#" ]] ; then 
        local git_log=$(git --no-pager log --tags --pretty='%h%d %as (%an) %s')
        local curr_commit=$(echo $git_log | grep $(git rev-parse --short HEAD))
        echo "Currently: $curr_commit"
        if ! echo $curr_commit | grep -q $commit ; then
          local commit_target=$(echo $git_log | grep $commit)
          local shorthash=""
          ! [[ -z "$commit_target" ]] && shorthash=$(echo $commit_target | cut -d " " -f1)
          if [[ -z "$shorthash" ]] ; then
            errors+=("  Skipped: ${dep_params}\n   Reason: commit log search string ($commit) not found in git log\n")
            printf "ERROR: Commit log search string (${commit}) not found in git log! \n" >&2
            continue
          fi
          echo "Requested: $commit_target"
          git switch "$shorthash" --detach
        else
          echo "No need to switch commits."
        fi
      fi

      #.... execute hooks, if specifed ..............................
      
      if [ ${#dep_params[@]} -lt 5 ] ; then 
        printf "Executing gdm-linker...\n"
        if gdm-linker "${GDM_STORE_DIR}/${repo_dirname}" "$CALLER_DIR"; then
          printf "done."
        else
          printf "gdm-linker FAILED! \n"  >&2
          errors+=("  Incomplete: ${dep_params}\n   Reason: gdm-linker failed\n")
          continue
        fi
      else 
        printf "Executing provided hooks..."
        for i in {5..$#dep_params}; do
          printf " ${dep_params[$i]}()..."
          if $dep_params[$i] "${GDM_STORE_DIR}/${repo_dirname}" "$CALLER_DIR"; then
            printf "done."
          else
            printf "${dep_params[$i]} execution FAILED! Skipping remaining hooks\n"  >&2
            errors+=("  Incomplete: ${dep_params}\n   Reason: ${dep_params[$i]} returned error any remaining were skipped\n")
            continue
          fi
        done
      fi
      cd "$CALLER_DIR"
    done
    cd "$CALLER_DIR"
    
    printf "------------------------------------------------------------\n"

    if [ ${#errors[@]} -ne 0 ] ; then
      printf "Completed, with the following errors:\n"
      printf $errors >&2
    else
      printf "Completed without errors! \n"
    fi

  # elif [[ "$1" =~ ${ARGS[list]} ]] ; then ...; fi

  elif [[ "$1" =~ ${ARGS[list_modules]} ]] ; then
    if ! [ -d "${CALLER_DIR}/${GDM_MODULES_DIRNAME}" ] ; then
      echo "${CALLER_DIR}/${GDM_MODULES_DIRNAME} does not exist! \n"  >&2
      return 1
    fi
    # local module_dir
    echo  "${CALLER_DIR}/${GDM_MODULES_DIRNAME}"
    for module_dir in "${CALLER_DIR}/${GDM_MODULES_DIRNAME}/*" ; do
      if [ -d "${$module_dir}/.git" ] ; then
        
        
        # cd "${CALLER_DIR}/${GDM_MODULES_DIRNAME}/${module_dir}"
        # local origin=$(git config --get remote.origin.url)
        # local repo_name=${origin:t:r} 
        # local current_branch=$(git rev-parse --abbrev-ref HEAD)
        # local msg="$module_dir"
        # [[ "$repo_name" !=  "$module_dir" ]] && msg="$message ($repo_name)"

        # if [[ $current_branch == HEAD ]]; then
        #   local curr_commit=$(echo $git_log | grep $(git rev-parse --short HEAD))
        #   msg="$msg $curr_commit"
        #   echo "${GDM_MODULES_DIRNAME}/${module_dir} ()"
        # fi

      fi
      echo "$module_dir"
    done
  else
    printf "Something went wrong! \n" >&2
    return 1
  fi

  

}
if [[ $ZSH_EVAL_CONTEXT == 'toplevel' ]]; then
  # We're not being sourced so run this script as a command
  gdm $@
fi

