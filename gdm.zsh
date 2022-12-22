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


REMOVE_UNTRACKED_GLOBS=false

GDM_CMD_DIR=$(dirname -- "${(%):-%N}")
# NOTE ${(%):-%N} is zsh's equivalent to ${BASH_SOURCE[0]} (is is the current script's path)

gdm_conf-template() {
  cat << 'CONFDOC'
#!/usr/bin/env zsh
export GDM_MODULES_DIRNAME="gdm_modules" 

gdm_conf() {
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
# The second parameter (optional - pass empty quotes "" to skip) should
#   be a branch name you want to use. Skipping this parameter by passing
#   "" chooses the default branch, which is usually "main" or "master".
#   
# The third parameter (optional - pass empty quotes "" to skip) is a commit log 
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
# The forth parameter (optional - pass empty quotes "" to skip) can be provided 
#   a (new) directory name within the $GDM_GLOB_STORE_PATH to clone to repository 
#   to instead of the default (which is the name of the repository: 
#   the portion after the last / and before .git in the first parameter).
#   Renaming can be helpful if you are working off of two versions (commit 
#   points or branches) in a given the repository as a dependency as having
#   two copies speeds up switching projects as each downloaded clone will 
#   already be pointing to the branch and commit you need.
#   If you'd like to skip this parameter (so you can pass hook(s))
#   and just use the most current commit (after pull), pass ""
# 
# The fifth parameter (optional - pass empty quotes "" to skip) is the name 
#   of a shell command or function you request to be run after the given 
#   dependency is set up (cloned to $GDM_GLOB_STORE_PATH, and with proper branch 
#   and commit switched to) but before it is linked to the the project depending 
#   on it. This may be useful for any setup you needed per-dependency, such 
#   as building  from source. You can define these commands a functions in this 
#   file or anywhere, so long as it is available in the shell session. 
#   This function expects the following four arguments:
#     $GDM_GLOB_STORE_PATH   $repo_dirname   $project_path   $GDM_MODULES_DIRNAME
#   The linker takes these same arguments copies (as hard links):
#     $GDM_GLOB_STORE_PATH/$repo_dirname/*
#       TO 
#     $project_path/$GDM_MODULES_DIRNAME/$repo_dirname/*
#
# Normally you should not pass a sixth parameter but DOING so bypasses the 
#   call gdm_linker, which links the cloned repository to your 
#   <project-root>/$GDM_MODULES_DIRNAME, where GDM_MODULES_DIRNAME="gdm_modules"
#   by default. Bypasssing the linker by specifying "" as this sixth parameter 
#   is not recommended but you may wish to do something after the linking which, 
#   can be achieved by passing another callable (again, expecting the same arguments 
#   as the fifth parameter) and adding:
#       gdm_linker $@
#   as the first line in your callable so that the linker is called, followed by 
#   your custom actions.
cat << 'HEREDOC'
# Example
juce-framework/JUCE develop "tag: 7.0.0" "JUCE_v7" ""
HEREDOC
}

# place post-hooks here:

no-hooks(){ return 0; } 

CONFDOC
}



git-expand-remote-url() {
  # validate that $remote_url can be cloned:
  local remote_url="$1"
  if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
    local fwslashes=$(echo "$remote_url" | grep -o "/"  | wc -l | xargs)

    if [[ $fwslashes == 1 ]] ; then   # github is assumed...
      remote_url="https://github.com/$remote_url"
    elif [[ $fwslashes == 2 ]] ; then # incomplete url but with domain...
      remote_url="https://$remote_url"
    else
      # DO NOT echo anything (no output also indicates failure)
      return 1  # error: invalid or could not expand to valid url for a clonable git repository.
    fi
    if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
      # DO NOT echo anything (no output also indicates failure)
      return 1 # error: invalid or could not expand to valid url for a clonable git repository.
    fi
  fi
  echo "$remote_url"
  return 0
}



gdm () {
  local CALLER_DIR=$(pwd)

  declare -A ARGS # all valid argument go here (except --help).
  ARGS[initialize]='^[-]{0,2}init.*$'
  ARGS[configure]='^[-]{0,2}conf.*$'
  ARGS[set_store_path]='^[-]{0,2}(set-)?(-gdm|-GDM)?(glob[-_]store|GLOB[-_]STORE|glob|GLOB|store|STORE)([-_]path|[-_]PATH)?(=.+)?$'
  ARGS[clean_store]='^[-]{0,2}clean([=-]store|[=-]glob|[=-]global)$'
  ARGS[list_modules]='^[-]{0,2}(list|ls)([=-]modules|[=-]local)?$'
  ARGS[list_store]='^[-]{0,2}(list|ls)([=-]store|[=-]glob|[=-]global)$'

  # An anonymous function (self executing) to check for invalid arguments:
  local not_valid_arg='() {
    for f in $ARGS ; do
      [[ "$1" =~ $f ]] && return 1;
    done;
    return 0;
  }'

  if eval ${not_valid_arg} "$1" ; then
    printf "Usage: calling with\n  --init    will generate empty configuration file for your project\n  --conf    will read file and perform configuration.\n"
    printf "By default, dependencies are installed (cloned to) ~/gdm_glob_store/ \nwith hard links to them in your <project-root>/gdm_modules\n"
    printf "You can choose your own location by adding to your ~/.zshrc (for example):\n"
    printf "export GDM_GLOB_STORE_PATH=\"/desired/path/to/directory/\"n"
    return 0
  fi

  gdm-verify-paths() {
    ! (($@[(Ie)--quiet-pass])) && printf "Verifying all required paths...\n"
    local project_path="$1"

    local glob_path_was_unset=false

    if ! (( ${+GDM_GLOB_STORE_PATH} )) ; then
      printf "GDM_GLOB_STORE_PATH is not set\n"
      export GDM_GLOB_STORE_PATH="$HOME/gdm_glob_store"
      glob_path_was_unset=true
    fi

    if ! [ -d "$GDM_GLOB_STORE_PATH" ] ; then # make the directory
      ! (($@[(Ie)--quiet-pass])) && printf "mkdir ${GDM_GLOB_STORE_PATH}\n"
      if ! mkdir "$GDM_GLOB_STORE_PATH" ; then 
        printf "ERROR: mkdir ${GDM_GLOB_STORE_PATH} failed.\n"  >&2 
        unset GDM_GLOB_STORE_PATH
        return 1
      fi
    fi

    if $glob_path_was_unset ; then # write to rc file should be after we know if making it failed
      # https://stackoverflow.com/questions/20572934/get-the-name-of-the-caller-script-in-bash-script
      if ! CALLER_SHELL=$(ps -o comm= $PPID) ; then
        if ! CALLER_SHELL=$(ps $PPID | tail -n 1 | awk "{print \$5}") ; then
          CALLER_SHELL="zsh"
        fi
      fi
      CALLER_SHELL=${CALLER_SHELL:t:r} 
      local rcfile="${HOME}/.${CALLER_SHELL}rc"
      if ! grep -sq '^[^#]*export GDM_GLOB_STORE_PATH=[^#][^#][^#]' "$rcfile" ; then
        printf "$CALLER_SHELL shell detected. Appending to $rcfile \n"
        ! [ -f "$rcfile" ] && touch "$rcfile"
        echo "\\nexport GDM_GLOB_STORE_PATH=\"\$HOME/gdm_glob_store\"" >> "$rcfile"
      fi
      printf "GDM_GLOB_STORE_PATH=${GDM_GLOB_STORE_PATH}\n"
    fi


    if ! (( ${+GDM_MODULES_DIRNAME} )) ; then # when unset? when gdm_config was not read or did not export it.
      ! (($@[(Ie)--quiet-pass])) && printf "setting GDM_MODULES_DIRNAME \n"
      export GDM_MODULES_DIRNAME="gdm_modules"
    fi
    if ! [[ -z  "$project_path" ]] && ! [ -d "${project_path}/${GDM_MODULES_DIRNAME}" ]; then 
      printf "mkdir ${project_path}/${GDM_MODULES_DIRNAME}\n"
      if ! mkdir "${project_path}/${GDM_MODULES_DIRNAME}" ; then
        printf "ERROR: mkdir ${project_path}/${GDM_MODULES_DIRNAME} failed.\n"  >&2 
        return 1;
      fi
    fi
    return 0
  }


  #___________________________________________________________________________________________
  # Generate template of gdm_conf.zsh (although they could just make it themselves)
  if [[ "$1" =~ ${ARGS[initialize]} ]] ; then 
    local gdm_conf_file="${CALLER_DIR}/gdm_conf.zsh"
    [[ -f "$gdm_conf_file" ]] && grep -q '[^[:space:]]' "$gdm_conf_file" && 
      printf "./gdm_conf.zsh already exists and is not empty!\nTo run file's configuration:\n  gdm --conf\n" >&2 && 
      return 1;
    gdm_conf-template > "${CALLER_DIR}/gdm_conf.zsh"
    printf "${CALLER_DIR}/gdm_conf.zsh configuration file generated.\n"
    return 0

  #___________________________________________________________________________________________
  # Read currently existing configuration file and set up all dependencies 
  # (usually for a given project unless they bypass the gdm_linker)
  elif [[ "$1" =~ ${ARGS[configure]} ]] ;then 
    
    ! [[ -f "./gdm_conf.zsh" ]] && printf "Error: No gdm_conf.zsh was found!" >&2 && return 1;
    source ./gdm_conf.zsh

    ! gdm-verify-paths "$CALLER_DIR" "--quiet-pass" && return 1;

    local required_deps=("${(f)$(gdm_conf)}")

    local errors=() # for displaying summary after entire operation is complete.
    LINKED_MODULES=() # keep track of directories in "${CALLER_DIR}/${GDM_MODULES_DIRNAME}/*"
                      # actually required so we can delete unneeded ones aftewards.
    printf "\n"
    for dep in $required_deps ;
    do
      local dep_params=( ${(Q)${(Z+C+)dep}} )
      [[ ${#dep_params[@]} -eq 0 ]] && continue; # empty or commented line in list of deps
      printf "------------------------------------------------------------\n"
      printf "      Found Requirement in gdm_conf.zsh:\n${dep}\n"
      #.... clone repo or cd to it ..................................

      local remote_url=$dep_params[1]
      [[ "$remote_url" != *".git" ]] && remote_url="${remote_url}.git"

      local repo_dirname=$dep_params[4]
      [[ -z "$repo_dirname" ]] && repo_dirname=${remote_url:t:r} 

      ! cd "$GDM_GLOB_STORE_PATH" && printf "FATAL ERROR: cd $GDM_GLOB_STORE_PATH FAILED\n" >&2 && return 1;

      if ! [ -d "${GDM_GLOB_STORE_PATH}/${repo_dirname}" ] ; then 
        # validate that $remote_url can be cloned and clone
        remote_url=$(git-expand-remote-url "$remote_url")

        printf "Cloning ${remote_url} to ${GDM_GLOB_STORE_PATH}/${repo_dirname}\n"
        if [[ -z "$remote_url" ]] || ! git clone "$remote_url" "$repo_dirname" --quiet ; then
          errors+=("  Skipped: ${dep_params}\n   Reason: Cannot clone \"$remote_url\"\n")
          printf "ERROR: Cannot clone \"$remote_url\"\n" >&2 && continue
        fi
      fi
      cd "$repo_dirname"
      
      printf "Finding correct branch...\n"

      local branch=$dep_params[2]
      
      local current_branch=$(git rev-parse --abbrev-ref HEAD) # if head is detached, current_branch will be "HEAD"
      local remote_names=("${(f)$(git remote)}")
      local origin_name=$( (($remote_names[(Ie)origin])) && echo origin || echo "${remote_names[1]}" )

      if [[ -z "$branch" ]] || [[ "$branch" == "HEAD" ]] || [[ "$current_branch" == "HEAD" ]] ; then
        # Set to default branch (usually main or master).
        branch=$(git remote show "$(git config --get remote.origin.url)" | sed -n '/HEAD branch/s/.*: //p')
        #  if we're in detached head state ("$current_branch" == "HEAD"), it will be fixed when we run
        # git checkout "$branch"
        # This if block assumes the default branch was not deleted locally!!! (probably safe though)
      fi
      if [[ "$branch" != "$current_branch" ]] ; then
        local loc_branches=("${(f)$(git branch --format='%(refname:short)')}")
        if ! (($loc_branches[(Ie)$branch])) ; then # If the desired $branch was never pulled to local repo...

          printf "git pull ${origin_name} ${branch}\n"
          if ! git pull "$origin_name" "$branch" -q ; then
            errors+=("  Skipped: ${dep_params}\n   Reason: Execution of the following failed: git pull ${origin_name} ${branch}\n")
            printf "ERROR: Execution of the following failed: git pull ${origin_name} ${branch}\n" >&2 && continue
          fi
        fi
        printf "git checkout ${branch}\n"
        if ! git checkout "$branch" ; then
          errors+=("  Skipped: ${dep_params}\n   Reason: Execution of the following failed: git checkout ${branch}\n")
          printf "ERROR: Execution of the following failed: git checkout ${branch}\n" >&2 && continue
        fi
      else 
        printf "git pull ${origin_name} ${branch}\n"
        if ! git pull "$origin_name" "$branch" -q ; then
          # We still pull even though the branch was found locally. But we can recover if this fails by using local branch.
          errors+=("  Warning: \`git pull ${origin_name} ${branch}\` failed but local branch was found and will be used.\n")
          printf "WARNING: \`git pull ${origin_name} ${branch}\` failed but local branch was found and will be used.\n"
        fi 
      fi

      #.... switch commit, if specifed ..............................

      printf "Finding correct commit...\n"
      local commit=$dep_params[3]

      if ! [[ -z "$commit" ]] ; then 
        local git_log=$(git --no-pager log --tags --pretty='%h%d %as (%an) %s')
        # local curr_hash=$(git rev-parse --short HEAD)
        # local curr_commit=$(echo $git_log | grep $curr_hash)

        # printf "Currently: ${curr_commit} (hash: $curr_hash)\n"
        # if ! echo $curr_commit | grep -q $commit ; then
          commit_target=$(echo $git_log | grep $commit)
          local shorthash=""
          ! [[ -z "$commit_target" ]] && shorthash=$(echo $commit_target | cut -d " " -f1)
          if [[ -z "$shorthash" ]] ; then
            errors+=("  Skipped: ${dep_params}\n   Reason: Commit log search string \"${dep_params[3]}\" not found in git log\n")
            printf "ERROR: Commit log search string \"${dep_params[3]}\" not found in git log! \n" >&2 && continue
          fi
          printf "Requested: ${commit_target}\n"
          git switch "$shorthash" --detach
        # else
        #   printf "No need to switch commits.\n"
        # fi
      fi

      #.... execute hooks, if specifed ..............................

      gdm_linker() {
        local GDM_GLOB_STORE_PATH="$1"
        local repo_dirname="$2"
        local project_path="$3"
        local GDM_MODULES_DIRNAME="$4"

        echo "linking \$GDM_GLOB_STORE_PATH/${repo_dirname} to ./${GDM_MODULES_DIRNAME}/${repo_dirname}"

        if ! [ -d "${project_path}/${GDM_MODULES_DIRNAME}" ] ; then
          if ! mkdir "${project_path}/${GDM_MODULES_DIRNAME}" ; then 
            printf "ERROR gdm_linker could not create ${project_path}/${GDM_MODULES_DIRNAME}! \n" >&2 
            return 1
          fi
        elif [ -d "${project_path}/${GDM_MODULES_DIRNAME}/${repo_dirname}" ] ; then
          rm -rf "${project_path}/${GDM_MODULES_DIRNAME}/${repo_dirname}"
        fi
        # Options for making hard link:
        # cp -al $src $dest # https://unix.stackexchange.com/a/202431
        # cp -lR $src $dest # https://superuser.com/a/1523307
        local result
        if ! result=$(cp -al "${GDM_GLOB_STORE_PATH}/${repo_dirname}" "${project_path}/${GDM_MODULES_DIRNAME}/${repo_dirname}" 2>&1); then
          printf "ERROR (gdm_linker): ${result}\n" >&2
          return 1
        fi
        # Register that the requirement as has been added to GDM_MODULES_DIRNAME so we can clean up (rm un-required) afterward:
        LINKED_MODULES+=("./${GDM_MODULES_DIRNAME}/${repo_dirname}") 
      }
      
      local pre_link_hook=$dep_params[5]
      local linker_bypass_hook=$dep_params[5]

      if ! [[ -z "$pre_link_hook" ]] ; then 
        printf "Executing pre_link_hook (${pre_link_hook}) \n"
        if ! eval ${pre_link_hook} "$GDM_GLOB_STORE_PATH" "$repo_dirname" "$CALLER_DIR" "$GDM_MODULES_DIRNAME" ; then
          errors+=("  Incomplete: ${dep_params}\n   Reason: Execution of provided hook, ${pre_link_hook}, FAILED! Skipping any remaining. \n")
          printf "Execution of provided hook, ${pre_link_hook}, FAILED! Skipping any remaining. \n"  >&2 && continue
        fi
      fi

      if [[ -z "$linker_bypass_hook" ]] ; then 
        printf "Executing gdm_linker\n"
        printf "      source: ${GDM_GLOB_STORE_PATH}/${repo_dirname}\n"
        printf " destination: ${CALLER_DIR}/${GDM_MODULES_DIRNAME}/${repo_dirname}\n"
        if ! gdm_linker "$GDM_GLOB_STORE_PATH" "$repo_dirname" "$CALLER_DIR" "$GDM_MODULES_DIRNAME" ; then
          errors+=("  Incomplete: ${dep_params}\n   Reason: gdm_linker failed! \n")
          printf "gdm_linker FAILED! \n"  >&2 && continue
        fi
      else
        printf "Executing linker_bypass_hook (${linker_bypass_hook}) \n"
        if ! eval ${linker_bypass_hook} "$GDM_GLOB_STORE_PATH" "$repo_dirname" "$CALLER_DIR" "$GDM_MODULES_DIRNAME" ; then
          errors+=("  Incomplete: ${dep_params}\n   Reason: Execution of link-bypassing hook, ${linker_bypass_hook}, FAILED! \n")
          printf "Execution of link-bypassing hook, ${linker_bypass_hook}, FAILED! \n"  >&2 && continue
        fi
      fi
      cd "$CALLER_DIR"
    done

    printf "____________________________________________________________\n"
    
    cd "$CALLER_DIR" # just in case last loop cut out (continue) early


    printf "--- Creating link-tracker(s) -------------------------------\n"   
    for _module in $LINKED_MODULES ; do
      local linked_repo_dirname=${_module:t:r}
      printf "$repo_dirname "
      if [ -d "${GDM_GLOB_STORE_PATH}/${repo_dirname}" ] ; then 
        local src_tracker="${GDM_GLOB_STORE_PATH}/${linked_repo_dirname}-link-tracker"
        local req_tracker="${CALLER_DIR}/${GDM_MODULES_DIRNAME}/${linked_repo_dirname}-link-tracker"
        if ! [ -f "${src_tracker}" ] ; then
          touch $src_tracker
          local inode_num=$(ls -i $src_tracker | awk '{print $1;}')
          echo "\"$inode_num\" \"${GDM_GLOB_STORE_PATH}/${linked_repo_dirname}\"" > $src_tracker
        fi
        [ -f "${req_tracker}" ] && rm "$req_tracker"
        ln "$src_tracker" "$req_tracker"
      fi
    done
    printf "\n"

 
    printf "--- Cleaning out unused dependencies -----------------------\n"  
    printf "Searching ./${GDM_MODULES_DIRNAME}...\n"
    local req_modules_cnt=${#LINKED_MODULES[@]}
    local found_modules=("${(@f)$(gdm --list-modules)}")
    local found_modules_cnt=${#found_modules[@]}
    if [[ $found_modules_cnt -gt $req_modules_cnt ]]; then
      printf "${req_modules_cnt} required modules in ./${GDM_MODULES_DIRNAME}\n"
      printf "${found_modules_cnt} total modules found in ./${GDM_MODULES_DIRNAME}\n"
      printf "  Removing unused from ${GDM_MODULES_DIRNAME}....\n"
      for _module in $found_modules ; do

        if ! (($LINKED_MODULES[(Ie)$_module])) ; then 
          local unreq_loc_repo_dirname=${_module:t:r}

          # Remove only if ${unreq_loc_repo_dirname}-link-tracker is found 
          if ! [ -f "${_module}-link-tracker" ] ; then
            errors+=("  Warning: untracked module \"${_module}\" was found but not removed.\n")
            printf " Warning: untracked module \"${_module}\" was found but not removed.\n"  >&2 && continue
          fi
          # Remove only if ${unreq_loc_repo_dirname} is found in global store
          if ! [ -d  "${GDM_GLOB_STORE_PATH}/${unreq_loc_repo_dirname}" ] ; then
            errors+=("  Warning: unknown module \"${_module}\" was found but not removed.\n")
            printf " Warning: unknown module \"${_module}\" was found but not removed.\n"  >&2 && continue
          fi

          printf "  rm -rf ${_module}"
          if rm -rf "${_module}" ; then printf "...Done.\n"
          else
            printf "...Failed! \n" 
            errors+=("  Unable to remove ${_module}\n")
          fi
          printf "  rm  ${_module}-link-tracker"
          if rm  "${_module}-link-tracker" ; then printf "...Done.\n"
          else
            printf "...Failed! \n"
            errors+=("  Unable to remove ${_module}-link-tracker\n")
          fi  
        fi
      done
    fi
    gdm --clean-store
    
    printf "____________________________________________________________\n"
    printf "---- Result Report -----------------------------------------\n"
    if [ ${#errors[@]} -ne 0 ] ; then
      printf "Completed, with the following errors/warnings:\n"
      printf $errors >&2
    else
      printf "Completed without errors! \n"
    fi


  #___________________________________________________________________________________________
  # List project dependencies found in $GDM_MODULES_DIRNAME
  elif [[ "$1" =~ ${ARGS[list_modules]} ]] ; then
    local gdm_modules_dirpath="${CALLER_DIR}/${GDM_MODULES_DIRNAME}"
    if ! [ -d "${gdm_modules_dirpath}" ] ; then
      echo "${gdm_modules_dirpath} does not exist\n"  >&2
      return 1
    fi
    cd "${gdm_modules_dirpath}"
    for _item in * ; do [ -d "${_item}" ] && printf "./${GDM_MODULES_DIRNAME}/${_item}\n" ; done
    cd "$CALLER_DIR"

  #___________________________________________________________________________________________
  # List original repos found in $GDM_GLOB_STORE_PATH
  elif [[ "$1" =~ ${ARGS[list_store]} ]] ; then
    if ! [ -d "${GDM_GLOB_STORE_PATH}" ] ; then
      echo "${GDM_GLOB_STORE_PATH} (GDM_GLOB_STORE_PATH) does not exist\n"  >&2
      return 1
    fi
    cd "${GDM_GLOB_STORE_PATH}"
    for _item in * ; do [ -d "${_item}" ] && printf "${GDM_GLOB_STORE_PATH}/${_item}\n" ; done
    cd "$CALLER_DIR"

  #___________________________________________________________________________________________
  # remove repos found in $GDM_GLOB_STORE_PATH that are not referenced (using *-link-tracker as proxy)
  elif [[ "$1" =~ ${ARGS[clean_store]} ]] ; then
    ! gdm-verify-paths "$CALLER_DIR" "--quiet-pass" && return 1;
    printf "Searching \$GDM_GLOB_STORE_PATH...\n"
    local stored_repos=("${(@f)$(gdm --list-store)}")

    for _stored_repo_path in $stored_repos ; do
      
      local _stored_repo_name=${_stored_repo_path:t:r}
      local src_tracker="${GDM_GLOB_STORE_PATH}/${_stored_repo_name}-link-tracker"
      
      if [ -f "$src_tracker" ] ; then
        local tracker_details=( ${(Q)${(Z+C+)$(ls -li "$src_tracker")}} )
        local tracker_inode="${tracker_details[1]}"
        local tracker_refcount="${tracker_details[3]}"

        local inode_storepath=( ${(Q)${(Z+C+)$(cat "$src_tracker")}} )
        local inode_num="${inode_storepath[1]}"
        local store_path_tracked="${inode_storepath[2]}"


        if [[ "$store_path_tracked" != "$_stored_repo_path" ]] ; then
          printf "Warning: \`cat \${GDM_GLOB_STORE_PATH}/${_stored_repo_name}-link-tracker\` shows it's tracking ${store_path_tracked}.\n"
        elif [[ $tracker_inode -ne $inode_num ]] ; then
          printf "Warning: \`cat \${GDM_GLOB_STORE_PATH}/${_stored_repo_name}-link-tracker\` shows an inode that is not it's own!\n"
          
        elif [[ $tracker_refcount -eq 1 ]] ; then # REMOVE 
          printf "Removing used: \${GDM_GLOB_STORE_PATH}/${_stored_repo_name}\n"
          rm -rf "$_stored_repo_path" # || we have a tracker not tracking anything, which is fine I guess?
          rm "$src_tracker"
        else printf "Keeping \${GDM_GLOB_STORE_PATH}/${_stored_repo_name} [used in $(( $tracker_refcount - 1))]\n"
        fi
      else 
        if $REMOVE_UNTRACKED_GLOBS ; then
          printf "Removing untracked: \${GDM_GLOB_STORE_PATH}/${_stored_repo_name}\n"
          rm -rf "$_stored_repo_path"
        fi
      fi
    done

  #___________________________________________________________________________________________
  else
    printf "Something went wrong! \n" >&2
    return 1
  fi

}
if [[ $ZSH_EVAL_CONTEXT == 'toplevel' ]]; then
  # We're not being sourced so run this script as a command
  gdm $@
fi

