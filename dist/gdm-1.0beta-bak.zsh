#!/usr/bin/env zsh

# Copyright (c) 2023, Jeff Russ
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

export GDM_VERSION="1.0beta"
export GDM_VER_COMPAT="1.0"
export GDM_REGISTRY="${GDM_REGISTRY:=$HOME/.gdm_registry}" # might have been defined in environment
export GDM_REQUIRED="${GDM_REQUIRED:=gdm_required}"     # can be overridden by $GDM_CONF file
export GDM_MIN_HASH_LEN=7
export GDM_SCRIPT="$0"

export GDM_SNAP_EXT="gdm_snapshot"
export GDM_MANIF_EXT="gdm_manifest"
export GDM_MANIF_VARS=(gdm_manifest_inode gdm_version regis_instance remote_url hash tag setup_hash) #changed gdm_register_path to regis_instance
export GDM_MANIF_VALIDATABLES=(regis_instance remote_url hash tag setup_hash)

declare -Ag GDM_ERRORS=(
  
  # gdm_parseRequirement errors:
  [cannot_expand_remote_url]=11
  [cannot_find_revision]=12
  [cannot_find_branch]=13
  [cannot_find_tag]=14
  [cannot_find_hash]=15
  [invalid_argument]=16

  # gdm_validateInstance errors: 
  [instance_missing]=21 # required code directory missing, (checked before manifest missing in gdm_validateInstance)
  [manifest_missing]=22 # manifest is within instance so manifest_missing usually means instance not missing
  [lone_instance]=23 # If no other files w same inode as manifest exist, fail.
  [manifest_inode_mismatch]=24 # If manifest inode mismatches actual, fail
  [gdm_version_outdated]=25 # if manifest gdm_version does not start with GDM_VER_COMPAT, fail
  [manifest_requirement_mismatch]=26 # If any manifest vars mismatch evaled vars, fail. 
  [regis_snapshot_missing]=27 # if register snapshot is missing, fail
  [instance_snaphot_mismatch]=28 # if required code mismatches snapshot, fail

  # gdm.register errors:
  [clone_failed]=31
  [checkout_failed]=32
  [setup_returned_error]=33
  [manifest_creation_failed]=34
  [snapshot_tempdir_failed]=35
  [snapshot_preswap_failed]=36
  [snapshot_check_failed]=37
  [snapshot_check_mismatch]=38
  [snapshot_mkdir_failed]=39
  [snapshot_mv_git_failed]=40
  [snapshot_postswap_failed]=41

  # gdm.require errors
  [mkdir_$GDM_REQUIRED]=61
  [hardlink_failed]=62

  [left_corrupted]=91
  [gdm_error_code_misread]=92
)

gdm() {
  which _S
  (($#==0)) && { echo "$(_S Y)gdm called without arguments$(_S)" >&2 ; return 127 ; }

  local config_fn_def=""

  if config_fn_def="$(typeset -f "$1" 2>/dev/null)" ; then
    echo "got function"
    local fn="$1" ; shift
    $fn $@
    return $?
  fi
  (($#<2)) && { echo "$(_S Y)gdm only got $# arguments$(_S)" >&2 ; return 127 ; }
  local method="$1" ; shift

  if ! (type gdm.$method >/dev/null 2>&1) ; then
    echo "$(_S R)gdm failed due to unknown option: $(_S G)$method$(_S)" ; return 127
  else
    gdm.$method $@ 
    return $?
  fi
}





gdm.require() {

  # --reset-unused-register --reset-lone-instance --reset-lone-instance 

  # while [[ "$1" =~ '^' ]] ; do
  #   if [[ "$1" =~ '^(-r|--refresh)$' ]] ; then force_re_require=true ; shift 
  #   elif [[ "$1" =~ '$(-f|--force)$' ]] ; then force_re_register=true ; shift 
  #   else break
  #   fi
  # done
  if ! (($#)) ; then
    echo "$(_S Y)$gdm.require received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
  fi

  # $force_re_register && force_re_require=true

  eval "$(gdm_fromMap GDM_ERRORS --local --all)" || { echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread] }
  
  local registration ; local reg_error=0
  registration="$(gdm.register $@)" || reg_error=$?
  # if $force_re_register ; then registration="$(gdm.register --force $@)" || error=$?
  # else registration="$(gdm.register $@)" || error=$?
  # fi
  if ((reg_error)) ; then 
    echo "$(_S R E)Registration of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 

    # TODO: add suggested fix
    return $reg_error
  fi

  # variables assigned in registration string:
  local remote_url rev rev_is hash tag branch setup_hash regis_parent_dir regis_prev_valix regis_suffix 
  local previously_registered register_created regis_instance regis_manifest regis_snapshot destin_instance 
  eval "$registration"
  
  local destin_manifest="$destin_instance/$regis_prefix$regis_suffix.$GDM_MANIF_EXT"
  local allow_orphan=true #TODO make this an argument option?
  local lone_allow='--disallow-lone' ; $allow_orphan && lone_allow='--allow-lone'
  local assignments="$(gdm_echoVars $GDM_MANIF_VALIDATABLES)" 
  local prev_inst_error
  gdm_validateInstance $lone_allow $destin_manifest $destin_instance $regis_snapshot "$assignments" $GDM_MANIF_VALIDATABLES ; prev_inst_error=$? #changed gdm_register_path to regis_instance
  

  if ! ((prev_inst_error)) ; then echo "$(_S G)Previous valid installation found at \"${destin_instance//$PWD/.}\"$(_S)" ; return 0 ; fi

  local reinistall_msg="remove current installation (first backing up if desired) by running\n\n  $(_S B)rm -rf \"${destin_instance//$PWD/.}\"$(_S)\n\nthen require again."
  
  local retry_ables=($manifest_inode_mismatch $manifest_missing) 

  if (($retry_ables[(Ie)$prev_inst_error])) ; then  #TODO test
    gdm_echoAndExec "cp -al \"$regis_manifest\" \"$destin_manifest\"" || {
      echo "Suggested fix: $reinistall_msg"
      return $GDM_ERRORS[hardlink_failed]
    }
    gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup ; prev_inst_error=$?
  fi

  local backup_ables=($gdm_version_outdated $lone_instance $manifest_requirement_mismatch $instance_snaphot_mismatch) 

  if (($backup_ables[(Ie)$prev_inst_error])) ; then 
    if ((prev_inst_error==gdm_version_outdated)) ; then #TODO test
      echo "$(_S Y S)Previous installation from an earlier version of gdm was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==lone_instance)) ; then #TODO test
      echo "$(_S Y S)Previous installation not tracked by gdm was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==manifest_requirement_mismatch)) ; then #TODO test
      echo "$(_S Y S)Previous installation with incorrect requirements was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==instance_snaphot_mismatch)) ; then #TODO test
      echo "$(_S Y S)Previous installation with files that have since been modified was found at \"${destin_instance//$PWD/.}\"$(_S)"
    fi

    local destin_instance_backup
    destin_instance_backup="$(_renameDir $destin_instance)" || 
      { echo "$(_S R) attempt to backup \"${destin_instance//$PWD/.}\" failed" ; return $left_corrupted }
    echo "$(_S Y S)Previous installation was backed up to \"${destin_instance_backup//$PWD/.}\"\nYou may want to delete this if it is not needed."
    prev_inst_error=$instance_missing
  fi

  if ((prev_inst_error==instance_missing)) ; then # destin_instance is missing
    echo "$(_S D S E)Installing to \"${destin_instance//$PWD/.}\" from \"${regis_instance//$GDM_REGISTRY/\$GDM_REGISTRY}\"$(_S)"
    gdm_echoAndExec "mkdir -p \"$destin_instance:h\"" || return $GDM_ERRORS[mkdir_$GDM_REQUIRED]
    cp -al "$regis_instance" "$destin_instance" >/dev/null 2>&1 || return $GDM_ERRORS[hardlink_failed]
    echo "$(_S G)Installation complete.$(_S)" ; return 0
  fi

  if ((prev_inst_error)) ; then 
    echo "$(_S R E)Installation of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 
    # TODO: add suggested fix
    return $reg_error
  fi

  # now we have all but regis_snapshot_missing covered, but that was checked with gdm_validateInstance of regis_instance
}

gdm.register() {
  # Input is the following arguments:
  #     [https://][domain]<vendor>/<repo>[.git][#<hash>|<tag>|<branch>] [ setup=<function>|<script_path>|cmd> ] [ to=<path> | as=<dirname> ]
  local outputVars=(remote_url rev rev_is hash tag branch setup_hash regis_parent_dir regis_prefix regis_suffix 
      previously_registered register_created regis_instance regis_manifest regis_snapshot destin_instance requirement_lock) 
  
  local force_re_register=false
  local allow_lone_registry=true
  local dry_run=false

  if ! (($#)) ; then
    echo "$(_S Y)$gdm.require received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
  fi

  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--(force-re-register|force)$' ]] ; then allow_lone=true ; shift 
    elif  [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone_registry=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone_registry=false ; shift 
    elif [[ "$1" =~ '^--dry-run$' ]] ; then dry_run=true ; shift 
    # possibly add more options here, later on
    else break
    fi
  done

  local requirement error 
  requirement="$(gdm_parseRequirement $@)" || return $? # FUNCTION CALL
  local remote_url rev rev_is hash tag branch setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
  
  # The above are requirement vars set by eval of output from gdm_parseRequirement:
  #   remote_url=<expanded from repo_identifier, usualy lowercased)
  #   rev=[<value after # in repo_identifier]
  #   rev_is="hash|tag|tag_pattern|branch"
  #   hash=<full_hash (lowercased) from repo_identifier>
  #   tag=[<full_tag not lowercased>]
  #   branch=[<branch_name not lowercased>]
  #   setup_hash=[hash of setup if passed] 
  #   regis_parent_dir="$GDM_REGISTRY/domain/vendor/repo"
  #   regis_prefix="<tag if found>|<estim. short hash if no tag>"
  #   regis_suffix="_setup-<setup hash>"
  #   regis_instance="$regis_parent_dir/$regis_prefix$regis_suffix"
  #   destin_instance="<full abs path to location where required>"
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.

  local repo_name="${remote_url:t:r}" # Needed??
  local manifest_found=false
  local regis_id="$regis_prefix$regis_suffix"

  if [[ -d "$regis_parent_dir" ]] ; then
    if [[ -z $tag ]] ; then
    local hash_backup="$hash"
    local found_hash
      for len in {$#regis_prefix..$#hash} ; do
        regis_prefix="$hash[1,$len]"
        regis_id="$regis_prefix$regis_suffix"
        
        if [[ -f "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" ]] ; then 
          found_hash=$(source "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" && echo "$hash") || break
          if [[ $found_hash == $hash ]] ; then  manifest_found=true ; break ; fi
          # else # doesn't match so we need a longer short hash (regis_prefix)
        else  break # missing, so we can use this short hash (regis_prefix)
        fi
      done
      hash="$hash_backup"
    elif [[ -f "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" ]] ; then manifest_found=true
    fi
  fi

  # local regis_instance="$regis_parent_dir/$regis_id" #changed gdm_register_path to regis_instance
  local regis_manifest="$regis_instance/$regis_id.$GDM_MANIF_EXT" #changed gdm_register_path to regis_instance
  local regis_snapshot="$regis_instance.$GDM_SNAP_EXT" #changed gdm_register_path to regis_instance

  local previously_registered=false
  local register_created=false

  eval "$(gdm_fromMap GDM_ERRORS --local --all)" || { echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread] }

  if $manifest_found ; then
    local prev_reg_error=0
    local assignments="$(gdm_echoVars $GDM_MANIF_VALIDATABLES)" #changed gdm_register_path to regis_instance
    ! $dry_run && echo "$(_S D S E)Validating previous registration of ${regis_instance//$GDM_REGISTRY\//} ...$(_S)" >&2
    local lone_allow='--disallow-lone' ; $allow_lone_registry && lone_allow='--allow-lone'
    gdm_validateInstance $lone_allow $regis_manifest $regis_instance $regis_snapshot "$assignments" $GDM_MANIF_VALIDATABLES ; prev_reg_error=$? #changed gdm_register_path to regis_instance

    if ! ((prev_reg_error)) ; then 
      previously_registered=true
      ! $dry_run && echo "$(_S G)Previous registration is valid!$(_S) Location: \$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" >&2
      if ! $force_re_register || $dry_run ; then 
        gdm_echoVars $outputVars #TODO?
        return 0
      fi
    else
      if $dry_run ; then
        echoVars $outputVars #TODO?
        return $prev_reg_error
      fi
      echo "$(_S M)Re-generating registration.$(_S) Reason: $(gdm_keyOfMapWithVal GDM_ERRORS $prev_reg_error)" >&2
    fi
  elif [[ -d "$regis_instance" ]] ; then #changed gdm_register_path to regis_instance
    if $dry_run ; then gdm_echoVars $outputVars ; return $manifest_missing ; fi
    echo "$(_S M)Generating new registration for $@$(_S) Reason: previous regis_manifest not found in \$GDM_REGISTRY" >&2
  else
    if $dry_run ; then gdm_echoVars $outputVars ; return $instance_missing ; fi
    echo "$(_S M)Generating new registration for $@$(_S) Reason: not previously registerd." >&2
  fi

  # if $dry_run && gdm_echoVars $outputVars ; return 1 ; fi
  
  # remote_url rev rev_is hash tag branch  setup destin_instance regis_parent_dir regis_prefix regis_suffix previously_registered register_created regis_instance regis_manifest regis_snapshot #changed gdm_register_path to regis_instance
  if $force_re_register ; then  echo "$(_S M)Generating new registration for $@$(_S) Reason: --force-re-register" >&2 ; fi

  # REMOVE OLD BEFORE (RE)CREATING REGISTER:
  [[ -d "$regis_instance" ]] && rm -rf "$regis_instance" ; #NEW
  # [[ -f "$regis_manifest" ]] && rm -rf "$regis_manifest" ; #NEW (commented out since regis_manifest is inside regis_instance)
  [[ -d "$regis_snapshot" ]] && rm -rf "$regis_snapshot" ; #NEW
  mkdir -p "$regis_parent_dir"

  local gdm_version="$GDM_VERSION"
  local regis_instance="\$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" #changed gdm_register_path to regis_instance
  local manifest_contents gdm_manifest_inode

  # CLONE:
  gdm_echoAndExec "cd \"$regis_parent_dir\" && git clone --filter=blob:none --no-checkout \"$remote_url\" \"$regis_id\"" || return $clone_failed
  # CHECKOUT:
  gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && git checkout \"$hash\"" || return $checkout_failed
  # SETUP:
  if ! [[ -z "$setup" ]] ; then gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && $setup \"$destin_instance\"" || return $setup_returned_error ; fi
  # MAKE MANIFEST:
  touch "$regis_manifest" || return $manifest_creation_failed
  gdm_manifest_inode="$(gdm_getInode "$regis_manifest")" || return $manifest_creation_failed
  manifest_contents="$(gdm_echoVars $GDM_MANIF_VARS)" # GDM_MANIF_VARS is a global
  echo -n "$manifest_contents" > "$regis_manifest" || return $manifest_creation_failed
  # MAKE A SNAPSHOT of the requirement (init a new repo and store .git as the snapshot): 
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir') || return $snapshot_tempdir_failed # But first...
  gdm_mvSubdirsTo "$regis_parent_dir/$regis_id" '.git' "$tempdir"  || return $snapshot_preswap_failed # move out all current .git/
  gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && git init && git add . && git commit -m \"$manifest_contents\"" || return $snapshot_failed
  mkdir "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $snapshot_mkdir_failed # we'll move snapshot's .git/ to this directory
  mv "$regis_parent_dir/$regis_id/.git" "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $?
  gdm_mvSubdirsTo "$tempdir" '.git' "$regis_parent_dir/$regis_id" || return $snapshot_postswap_failed
  rm -rf "$tempdir"

  register_created=true
  echo "$(_S M)Done Registering$(_S)" >&2
  gdm_echoVars $outputVars #TODO?
  return 0
}

gdm_validateInstance() {
  # Input: after any optional flags pass an eval-able declaration of local vars as the next argument
  #        followed by optional flags and the remaining args are var names that should be defined in manifest 
  # Output: no output... only a returned error from GDM_ERRORS or a return of 0
  # NOTE: $assignments as show below must define, at minimum: manifest instance snapshot and, in addition,
  #       any of the remaining args that are variable names to be checked in the manifest.
  # Example 1: #changed gdm_register_path to regis_instance
  #   local assignments="$(gdm_echoVars manifest instance snapshot regis_instance remote_url hash tag setup)" #changed gdm_register_path to regis_instance
  #   gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup #changed gdm_register_path to regis_instance
  # Example 2: #changed gdm_register_path to regis_instance
  #   gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup #changed gdm_register_path to regis_instance

  local allow_lone=true
  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone=false ; shift 
    # possibly add more options here, later on
    else break
    fi
  done
  local manifest="$1" 
  local instance="$2"
  local snapshot="$3"
  local local_assignments="$4"
  shift 4
  # local_assignments ets values for each "local $@"
  local $@ ; eval "$local_assignments" || return $?

  eval "$(gdm_fromMap GDM_ERRORS --local --all)" || return $?

  ! [[ -d "$instance" ]] && return $instance_missing
  ! [[ -f "$manifest" ]] && return $manifest_missing
  
  ! $allow_lone && [[ $(gdm_hardLinkCount "$manifest") -eq 0 ]] && return $lone_instance # no other files w same inode as manifest exist
  
  local manifest_vars=("${(@f)"$(<$manifest)"}") ; manifest_vars=($manifest_vars) # remove empty element
  manifest_vars=("local _"$^manifest_vars) # prepend each with "local _" so var are local and start with _
  eval "$(print -l $manifest_vars)"

  [[ "$_gdm_manifest_inode" != $(gdm_getInode "$manifest") ]] && return $manifest_inode_mismatch
  # manifest gdm_version must start with GDM_VER_COMPAT:
  ! [[ "$_gdm_version" =~ "^$GDM_VER_COMPAT.*" ]] && return $gdm_version_outdated 

  
  for var_name in $@ ; do # If any manifest vars mismatch evaled vars, fail. 
    manifest_var_name="_$var_name"
    [[ "${(P)var_name}" != "${(P)manifest_var_name}" ]] && return $manifest_requirement_mismatch
  done

  gdm_snapshotDiff "$(gdm_echoVars instance snapshot)" || return $?
  return 0
}

gdm_snapshotDiff() {
  local show_diff=false
  if [[ "$1" == '--show-diff' ]] ; then show_diff=true ; shift ; fi

  local instance snapshot # instance can not be missing!
  eval "$1" # sets: instance snapshot
  # ! [[ -d "$instance" ]] && return $GDM_ERRORS[instance_missing]
  ! [[ -d "$snapshot" ]] && return $GDM_ERRORS[regis_snapshot_missing]

  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[snapshot_check_failed]
  local output error ; output=$(cd "$instance" && git status --porcelain) ; error=$?
  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[snapshot_check_failed]
  ((error)) && return $GDM_ERRORS[snapshot_check_failed]
  [[ -z "$output" ]] && return 0
  $show_diff && echo 
  return $GDM_ERRORS[snapshot_check_mismatch]
}

gdm_parseRequirement() {
  # expected args: [domain/]vendor/repo[.git][#<hash>|#<tag or tag_patt>|#<branch>] [setup] [to=<path>|as=<dir_name>]
  #                which are the same arguments as expected by gdm.require
  #                 (1st arg is referred to here as $repo_identifier)
  # output sets: remote_url rev rev_is hash tag branch setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
  #              which are the following (only line's value will be in \"\" and ending with semicolons):
  #   remote_url=<expanded from repo_identifier, usualy lowercased)  (never blank)
  #   rev=[<revision specfied after # in repo_identifier]            (may be blank)
  #   rev_is=hash|tag|tag_pattern|branch                             (never blank)
  #   hash=<full_hash (lowercased) from repo_identifier>             (never blank)
  #   tag=[<full_tag not lowercased>]                                (may be blank)
  #   branch=[<branch_name not lowercased>]                          (may be blank)
  #   setup_hash=[hash of setup if passed]                           (may be blank)
  #   regis_parent_dir=$GDM_REGISTRY/domain/vendor/repo              (never blank)
  #   regis_prefix=<tag if found>|<estim. short hash if no tag>      (never blank)
  #   regis_suffix=_setup-<setup hash>"                              (never blank)
  #   regis_instance=$regis_parent_dir/$regis_prefix$regis_suffix    (never blank)
  #   destin_instance=<full abs path to location where required>     (never blank)
  # NOTE "<estim. short hash if no tag>" is estimate that may need elongation (not done in this function)

  local repo_identifier="$1" # [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  local requirement  
  ! requirement="$(gdm_expandRemoteRef "$repo_identifier")" && return $?

  local remote_url rev rev_is hash tag branch # these are gdm_expandRemoteRef vars:
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.

  local repo_name="${remote_url:t:r}"
  local setup ; local destin_instance=() # temporarily an array to detect erroneous double assignment
  shift
  for arg in $@ ; do
    if [[ "${arg:l}" =~ '^-{0,2}(s|setup)[=]' ]] ; then setup="${arg#*=}" 
    elif [[ "${arg:l}" =~ '^-{0,2}to[=]' ]] ; then destin_instance+="${${arg#*=}:a}" # ${rel:a} converts rel to abs path (works even if does not exist)
    elif [[ "${arg:l}" =~ '^-{0,2}as[=]' ]] ; then
      # TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
      $0_isNonPathStr() {  # used in  helpers: gdm_parseRequirement  
        # if string contains only . and / characters or it contains any /, it's a path so it fails
        # (whether it exists or not) This also fails if passed string with * or ~ because path expansion
        [[ "$1" =~ '^[.]*$' ]] || test "${1//\//}" != "$1" && return 1 || return 0
      }
      if ! $0_isNonPathStr "${arg#*=}" ; then
        echo "$(_S R S)$1 \`as\` parameter must be a directory name and not a path!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
      fi
      destin_instance+="$PWD/$GDM_REQUIRED/${arg#*=}"
    else echo "Invalid argument: $arg" >&2 ; return $GDM_ERRORS[invalid_argument]
    fi
  done
  
  if (($#destin_instance>1)) ; then echo "$(_S R S)$1 has multiple \`to\` and/or \`as\` destinations specified!$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
  elif (($#destin_instance==0)) ; then destin_instance+="$PWD/$GDM_REQUIRED/$repo_name" # set to repo name, within required dir
  fi

  local regis_parent_dir="$GDM_REGISTRY/${${remote_url#*//}:r}"
  local regis_prefix="$tag" ;  [[ -z "$regis_prefix" ]] && regis_prefix=$hash[1,$GDM_MIN_HASH_LEN] # changed mind: no short hashes
  [[ -z "$regis_prefix" ]] && return 64

  ###### get value and type of setup command ##################################

  local regis_suffix="" # empty unless there is a setup, in which case it will be: _setup-<setup_hash>
  # registry_id="${regis_prefix}${regis_suffix}" which is <tag>|<shorthash>[_setup-<setup_hash>]
  # $regis_parent_dir/${registry_id}/ was/will the repo+checkout 
  # $regis_parent_dir/${registry_id}.$GDM_ARCH_EXT is this archive of repo+checkout  
  # $regis_parent_dir/${registry_id}.$GDM_TRACK_EXT is the inode tracker
  local setup_hash=""
  if ! [[ -z "$setup" ]] ; then
    # $setup and $hash are the only variables output by $0 so the only job here is to 
    # resolve value of $setup to something that doesn't change and form a $hash from it
    # 
    
    # elif setup is a function, we use it's source (whence -cx 2 $setup) as a string to form the hash
    # else we simply $hash the value of $setup as is
    
    local setup_val # setup_is all but exec_error are output from $0
    local orig_setup="$setup"


    if [[ -f "${setup:a}" ]] ; then 
      # setup is SCRIPT: we use the cat value to form the hash
      setup="${setup:a}" # we resolve to full path so we can call from anywhere
      ! [[ -x "$setup" ]] && chmod +x "$setup"
      if ! setup_val="$(cat "$setup" 2>/dev/null)" ; then echo "$(_S R S)$orig_setup (setup script) cannot be read!$(_S)" >&2 ; return 1 ; fi
    elif typeset -f "$setup" > /dev/null ; then
      # setup is FUNCTION: we use it's source code as a string to form the hash
      autoload +X ls-A  # loads an autoload function without executing it so we can call whence -c on it and see source
      if ! setup_val="$(whence -cx 2 "$setup" 2>/dev/null)" ; then echo "$(_S R S)$orig_setup (setup function) cannot be read!$(_S)" >&2 ; return 1 ; fi
    else
      setup_val="$setup" # and hope for the best when we actually run it!
    fi
    $0.strToHash() { crc32 <(echo "$1") ; }
    if ! setup_hash=$($0.strToHash "$setup_val") ; then echo "$(_S R S)$orig_setup (setup) cannot be hashed!$(_S)" >&2 ; return 1 ; fi

    regis_suffix="_setup-$setup_hash"
  fi


  # echo -n "$requirement\nsetup=\"$setup\"\ndestin_instance=\"$destin_instance[1]\"\nregis_parent_dir=\"$GDM_REGISTRY/${${remote_url#*//}:r}\"\nregis_prefix=\"$regis_prefix\"\nregis_suffix=\"$regis_suffix\"" 
  destin_instance="$destin_instance[1]"
  
  regis_parent_dir="$GDM_REGISTRY/${${remote_url#*//}:r}"
  regis_instance="$regis_parent_dir/$regis_prefix$regis_suffix"
  # echo "$requirement" ; gdm_echoVars setup destin_instance registry_repo_dir registry_prefix registry_suffix #OLD
  gdm_echoVars remote_url rev rev_is hash tag branch setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
}

gdm_expandRemoteRef() {
  # expected arg: [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  # NEW: is expanded to set output, which sets: remote_url rev rev_is hash tag branch
  #   remote_url=<full_remote_url> (from [domain/]vendor/repo[.git])   (never blank)
  #   rev=[<value after # which is after [domain/]vendor/repo[.git]]   (may be blank)
  #   rev_is="hash|tag|tag_pattern|branch"                             (never blank)
  #   hash=<full_hash>                                                 (never blank)
  #   tag=[<full_tag>]                                                 (may be blank)
  #   branch=[<branch_name>]                                           (may be blank)

  # Multiple hits are only allowed when tag_pattern is provided, which is in grep -E regex format.
  # In the case of no hits or (unallowed) multiple hits, an error is returned without output.
  # output includes as rev=$ref_by:ref_val where $ref_val is portion after '#' in input
  # and ref_by is branch tag tag_pattern or hash. When ref_by is not branch, the branch value output
  # may differ depending on when gdm_expandRemoteRef is called (tag/hash combinations don't change
  # but the hash of a branch differs depepending in the most recent commit at the time)
  # if vendor/repo#HEAD ; then rev=branch:HEAD BUT
  # if vendor/repo ; then rev=branch: even though the two are effectively the same.

    # expands remote_url hash and tag information from short remote, hash branch tag or tag pattern.
    # defaulting to HEAD (default branche's most recent hash) if only remote is provided.
    # usage:
    #   gdm_expandRemoteRef vendor/repo#<short_or_long_hash>
    #   gdm_expandRemoteRef vendor/repo#<branch>
    #   gdm_expandRemoteRef vendor/repo#<tag>
    #   gdm_expandRemoteRef vendor/repo#<tag_pattern>
    #   gdm_expandRemoteRef vendor/repo              (same as gdm_expandRemoteRef vendor/repo#HEAD)

  
  local remote_ref="${${1%#*}:l}" # we try lowercased first to avoid multiple registrations
  local remote_url

  if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" ; then
    remote_ref="${1%#*}"
    if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
      echo "$(_S R)Cannot expand Remote Url from $remote_ref$(_S)" >&2 ; return $GDM_ERRORS[cannot_expand_remote_url]
    fi
  fi
  # FUNCTION CALL  ${1%#*} is abbrev. remote_url (everytihng before #<hash>|#<tag>)
  local rev="${1##*#}" ;  [[ "$1" == "$rev" ]] && rev=""
  local provided="$rev" # backup before possibly setting to default branch (next line).

  [[ -z $rev ]] || [[ $rev == 'HEAD' ]] && rev="$(git remote show $remote_url | sed -n '/HEAD branch/s/.*: //p')" # default branch

  local t_and_b=("${(f)$(git ls-remote --sort=-version:refname -th $remote_url | grep -vE 'refs/tags/.*\^{}$')}") # 90
  local rev_is='?' ; local hits ; local ls_all_hash=("ls-remote"  "--sort=-version:refname" "--refs" "$remote_url")
  local branch='' ; local tag=''

  if   hits=("${(f)$(print -l $t_and_b | grep "refs/heads/${rev}$")}")   && (($#hits==1)) ; then rev_is="branch" ; branch="${hits[1]##*refs/heads/}"
  elif hits=("${(f)$(print -l $t_and_b | grep "refs/tags/${rev}$")}")    && (($#hits==1)) ; then rev_is="tag" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -E "refs/tags/${rev}$")}") && (($#hits>0)) ; then rev_is="tag_pattern" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(git $ls_all_hash | grep "^${rev:l}")}") && (($#hits>0)) ; then rev_is="hash"  # (hashes are always lowercase)
  # try case-insensitive:
  elif hits=("${(f)$(print -l $t_and_b | grep -i "refs/heads/${rev}$")}") && (($#hits>0)) ; then rev_is="branch" ; branch="${hits[1]##*refs/heads/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -i "refs/tags/${rev}$")}")  && (($#hits>0)) ; then rev_is="tag" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -iE "refs/tags/${rev}$")}") && (($#hits>0)) ; then rev_is="tag_pattern" ; tag="${hits[1]##*refs/tags/}"
  else 
  fi

  local hash="$(echo $hits[1] | awk '{ print $1 }')"  # ; local branch='' ; local tag=''

  [[ $rev_is == tag_pattern ]] && hits=("${hits[1]}") # we allow multiple hits (taking first) if rev was tag pattern
  # But other multiple hash hits are not allowed so if hits contains any other hash, return error:
  if (($#hits>1)) && (($(print -l $hits | grep -vE "^$hash" | grep "" -c)>0)) ; then  # branch tag or hash had to many matches so:
    $0.echoErr() { echo "$(_S R S)Cannot expand \"$1\". Multiple $2 matching \"$3\" found.$(_S)" >&2 }
    if   [[ $rev_is == 'branch' ]] ; then $0.echoErr $1 branches $rev ; return $GDM_ERRORS[cannot_find_branch]
    elif [[ $rev_is == 'tag'* ]]   ; then $0.echoErr $1 tags $rev ; return $GDM_ERRORS[cannot_find_tag]
    elif [[ $rev_is == 'hash' ]]   ; then $0.echoErr $1 hashes $rev ; return $GDM_ERRORS[cannot_find_hash]
    else  echo "$(_S R S)Cannot expand \"$1\". No matches found for \"$rev\"$(_S)" >&2 ; return $GDM_ERRORS[cannot_find_revision]
    fi
  fi
  [[ -z $branch ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/heads/")}") && (($#hits>0)) && branch="${hits[1]##*refs/heads/}"
  [[ -z $tag ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/tags/")}") && (($#hits>0)) && tag="${hits[1]##*refs/tags/}"
  rev="$provided"
  gdm_echoVars remote_url rev rev_is hash tag branch
  # echo -n "remote_url=\"$remote_url\"\nref=\"$provided\"\nrev_is=\"$rev_is\"\nhash=\"$hash\"\ntag=\"$tag\"\nbranch=\"$branch\""; 
  return 0
}

gdm_swapDotGits() {
  local parentdir_A="${1:a}"
  local parentdir_B="${2:a}"
  local tempdir_A=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')
  gdm_mvSubdirsTo "$parentdir_A" '.git' "$tempdir_A" 
  gdm_mvSubdirsTo "$parentdir_B" '.git' "$parentdir_A"
  gdm_mvSubdirsTo "$tempdir_A" '.git' "$parentdir_B"
  rm -rf "$tempdir_A"
}

gdm_mvSubdirsTo() {
  # Description
  #   Moves subdirectories with a given name at any depth within some directory to another, 
  #   creating any intermediary directories if needed. By default any subdirectory matching the provided
  #   name of any depth will be moved. This can be changed by passing find options: -mindepth -maxdepth.
  # Usage
  #  gdm_mvSubdirsTo <current_parent_dir> <subdir_name> <new_parent_dir> 
  #    where options for find command with integers (which preceed integer arguments) can be passed anywhere
  #    and additional find option may be passed after the final required argument: <new_parent_dir>.
  local cur_parent subdir_name new_parent
  local ordered_argvars=(cur_parent subdir_name new_parent) ; local next_argvar_i=1
  local find_flags_w_n=( -mindepth -maxdepth -depth -links -inum -Bmin) local find_args=()
  local arg_i=1
  while ((arg_i<=$#@)) ; do
    if ((arg_i<$#@)) && [[ "$@[((arg_i+1))]" =~ '^[0-9]$' ]] && (($find_flags_w_n[(Ie)$@[$arg_i]])) ; then
      find_args+=("$@[$arg_i]" "$@[((arg_i+1))]") ; ((arg_i+=1)) # an extra increment
    elif ((next_argvar_i<=$#ordered_argvars)) ; then
      eval "$ordered_argvars[$next_argvar_i]=\"$@[$arg_i]\"" ; ((next_argvar_i++))
    else find_args+=("$@[$arg_i]") # interpret args beyond required as args for find
    fi
    ((arg_i++))
  done

  local subdirs_rel_parent=("${(@f)$(cd "$cur_parent" && find . -type d $find_args -name "$subdir_name")}")
  subdirs_rel_parent=($subdirs_rel_parent) # remove empty element

  for i in {1..$#subdirs_rel_parent} ; do
    if ! [[ -z "$subdirs_rel_parent[$i]" ]] ; then
      local intermediary_path="${subdirs_rel_parent[$i]:h}"
      if ! [[ -z "$intermediary_path" ]] ; then
        mkdir -p "$new_parent/$intermediary_path"
        mv "$cur_parent/$subdirs_rel_parent[$i]" "$new_parent/$intermediary_path"
      else
        mv "$cur_parent/$subdirs_rel_parent[$i]" "$new_parent" 
      fi
    fi
  done
}

gdm_gitExpandRemoteUrl() { 
  [[ -z "$1" ]] && return 3 # none provided
  local remote_url="$1" ; [[ "$remote_url" != *".git" ]] && remote_url="${remote_url}.git"
  if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
    local fwslashes=$(echo "$remote_url" | grep -o "/"  | wc -l | xargs)
    if [[ $fwslashes == 1 ]] ; then  remote_url="https://github.com/$remote_url"  # github is assumed...
    elif [[ $fwslashes == 2 ]] ; then remote_url="https://$remote_url" # incomplete url but with domain...
    else return 2 ; fi  # error: invalid or could not expand to valid url for a clonable git repository.
    if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then return 1 ; fi # error: could not expand
  fi
  echo "$remote_url" ; return 0
}

gdm_getInode() { # used in gdm
  local cap
  if [[ -d "$1" ]] ; then cap="$(ls -id $1)" || return $?
  else                    cap="$(ls -i $1)"  || return $?
  fi
  echo $cap | awk '{print $1;}' || return $?
}

gdm_hardLinkCount() { echo $(($(ls -liUT "$1" | awk '{print $3}')-1)) ; }

function _S() { # S for STYLE
  # EXAMPLES: echo -e "$(_S R E)red italics$(_S)" ; echo -e "$(_S R E)ERROR: $(_S E)just italics\!$(_S)"
  # [S]trong(bold), [D]im, [E]mphasis(italic), [U]nderline, [F]Flash(blink). [6]?, 
  # [I]nvertFG/BG-colors, [R]ed, [G]reen, [Y]ellow, [G]reen, [B]lue, [M]agenta, [C]yan
  declare -A cLU=( [S]=1 [D]=2 [E]=3 [U]=4 [F]=5 [6]=6 [I]=7 [R]=31 [G]=32 [Y]=33 [B]=34 [M]=35 [C]=36 ) # codeLookUp
  local seq="\e[0m"
  [ $# -eq 0 ] && print "$seq" && return 0;
  seq="${seq}\e["
  for var in "$@" ; do seq="${seq}${cLU[$var]};" ; done
  print "${seq[1,-2]}m" # remove last ; and append m
}

gdm_echoVars() {
  for var_name in $@ ; do
    if [[ "$var_name" =~ '^[ ]*#' ]] ; then echo  "$var_name ;" # echo comment
    elif [[ "$var_name" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]*=.+' ]] ; then 
      print -- "${var_name} ; " ; # custom variable name with assignment
    else
      print -- "${var_name}=\"${(P)var_name}\" ; " ;
    fi
  done
}

gdm_echoAndExec() {
  local err_code err_cap 
  local newline_patt="$(echo '.*'; echo '.*')"
  local cmd="$@"
  local append="" ; [[ "$cmd" =~ "$newline_patt$" ]] && append="#..."
  print -- "$(_S B)$(echo "${cmd//$GDM_REGISTRY/\$GDM_REGISTRY}" | head -1)$(_S)$append" >&2
  
  err_cap="$(eval "$@" 1>/dev/null 2>&1)" ; err_code=$?
  if ((err_code)) ; then echo "$cap\n$(_S R S)Terminating due to error code $err_code$(_S)" >&2 ; return $err_code ; fi
}

gdm_mapDecl() { local result ; result="$(typeset -p "$1")" || return $? ; }

# $1 is name of associative array, $1 is key found in it
gdm_keyOfMapWithVal() { local evalable="\${(k)$1[(r)$2]}" ; eval "echo $evalable" || return $? ; }

gdm_mapVal() { echo -n "(${"$(typeset -p "$1" 2>/dev/null)"#*'=('}" ; }

gdm_fromMap() {
  if (($#<3)) ; then echo "$0 requires at least 3 args: name of associative array, --get.*, --all-a|<key>..." >&2 ; return 3 ; fi

  # local map_decl="$(typeset -p "$1")" ; shift #old
  local map_decl ; ! map_decl="$(typeset -p "$1")" 2>/dev/null && map_decl="$1" ; shift #new
  
  local valdelim='=('
  local map ; eval "${$(echo "${map_decl%%$valdelim*}" | xargs)% *} map$valdelim${map_decl#*$valdelim}"
  local prepend=""
  if [[ "$1" == '--get' ]] ; then 
  elif [[ "$1" =~ '^(--get-local|--local)$' ]] ; then prepend="local " ; 
  elif [[ "$1" =~ '^--local=.+' ]] ; then prepend="local ${1[9,-1]}" ; 
  elif [[ "$1" == '--get' ]] ; then prepend="" ;
  elif [[ "$1" =~ '^--get=.+' ]] ; then prepend="${1[7,-1]}" ;
  else echo "$0 got invalid 2nd arg: \"$1\"" >&2 ; return 2
  fi
  # echo "prepend is \"$prepend\""
  shift
  if [[ "$1" =~ '^(-a|--all)$' ]] ; then
    for k v in ${(kv)map} ; do echo "$prepend$k=\"$v\"" ; done
  else for k in $@ ; do  echo "$prepend$k=\"$map[$k]\"" ; done
  fi
}


gdm.quoteElem() {
  local find replace
  while [[ "$1" == '-f='* ]] || [[ "$1" == '-r='* ]] ; do
    [[ "$1" == '-f='* ]] && find="${1[4,-1]}" || replace="${1[4,-1]}" ; shift
  done
  if [[ -z "$find" ]] ; then for item in $@ ; do echo -n "\"$item\" " ; done ; echo 
  else  for item in $@ ; do echo -n "\"${item//$find/$replace}\" " ; done ; echo 
  fi
}

# replace="$(_S M)/FULLPATHTO$(_S)"

# print "$(_S D)ZSH_EVAL_CONTEXT:$(_S) \"$ZSH_EVAL_CONTEXT\"" # toplevel:file:file

# echo "$(_S D)funcfiletrace:$(_S)   $(gdm.quoteElem -f="$PWD" -r=$replace $funcfiletrace)"   
# echo "$(_S D)funcsourcetrace:$(_S) $(gdm.quoteElem -f="$PWD" -r=$replace $funcsourcetrace)" 
# echo "$(_S D)funcstack:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $funcstack)"
# echo "$(_S D)functrace:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $functrace)"

# ZSH_EVAL_CONTEXT: "toplevel:file:file"
# funcfiletrace:   "./[pathto/]gdm.conf.zsh:23" "zsh:603" 
# functrace:       "./[pathto/]gdm.conf.zsh:23" "zsh:603" 
# funcsourcetrace: "/FULLPATHTO/dist/gdm-1.0beta.zsh:0" "./[pathto/]gdm.conf.zsh:0" 
# funcstack:       "/FULLPATHTO/dist/gdm-1.0beta.zsh" "./[pathto/]gdm.conf.zsh" 


gdm._callDetails() {
  echo "$(_S B)$0$(_S)"
  local replace="$(_S M)/FULLPATHTO$(_S)"
  # ZSH_EVAL_CONTEXT equals 'toplevel:file:file' if a file is sourced which sources this file
  # ZSH_EVAL_CONTEXT equals 'toplevel:file'      if a file is executed which sources this file
  # ZSH_EVAL_CONTEXT equals 'toplevel'           if a file is sourced which executes this file
  # ZSH_EVAL_CONTEXT equals 'toplevel'           if a file is executed which executes this file
  # ZSH_EVAL_CONTEXT end with ':shfunc'          if ZSH_EVAL_CONTEXT is finally read from within a function

  print "$(_S D)ZSH_EVAL_CONTEXT:$(_S) \"$ZSH_EVAL_CONTEXT\"" # toplevel:file:file:shfunc

  echo "$(_S D)funcfiletrace:$(_S)   $(gdm.quoteElem -f="$PWD" -r=$replace $funcfiletrace)" 
  echo "$(_S D)funcsourcetrace:$(_S) $(gdm.quoteElem -f="$PWD" -r=$replace $funcsourcetrace)" 
  echo "$(_S D)funcstack:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $funcstack)"
  echo "$(_S D)functrace:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $functrace)"

  # ZSH_EVAL_CONTEXT: "toplevel:file:file:shfunc"
  # funcfiletrace:   "/FULLPATHTO/dist/gdm-1.0beta.zsh:792" "./[pathto/]gdm.conf.zsh:23" "zsh:607" 
  # functrace:       "/FULLPATHTO/dist/gdm-1.0beta.zsh:792" "./[pathto/]gdm.conf.zsh:23" "zsh:607" 
  # funcsourcetrace: "/FULLPATHTO/dist/gdm-1.0beta.zsh:776" "/FULLPATHTO/dist/gdm-1.0beta.zsh:0" "./[pathto/]gdm.conf.zsh:0" 
  # funcstack:       "gdm._callDetails" "/FULLPATHTO/dist/gdm-1.0beta.zsh" "./[pathto/]gdm.conf.zsh" 
}

# gdm._callDetails

export GDM_CONF_NAME="gdm.conf.zsh"

gdm.callerDetails() {
  local replace="$(_S M)/FULLPATHTO$(_S)"
  
  local sourced=false ; [[ "$ZSH_EVAL_CONTEXT" =~ ':file' ]] && sourced=true
  
  local immediate_caller_is_conf=false
  local shell_in_project_dir=false
  local gdm_conf_calling_linenum=""
  local prev_was=''
  for item in $funcfiletrace ; do
    if [[ $prev_was == this ]] ; then
      if [[ $item =~ $GDM_CONF_NAME ]] ; then
        immediate_caller_is_conf=true
        prev_was=conf
      fi
    elif [[ $item == $GDM_SCRIPT* ]] ; then
      echo "found this"
      prev_was=this
    else echo "else: $item"
    fi
    
  done
  echo "sourced=$sourced ; immediate_caller_is_conf=$immediate_caller_is_conf"
  # echo "$(_S D)funcfiletrace:$(_S)   $(gdm.quoteElem -f="$PWD" -r=$replace $funcfiletrace)" 
  # echo "$(_S D)funcsourcetrace:$(_S) $(gdm.quoteElem -f="$PWD" -r=$replace $funcsourcetrace)" 
  # echo "$(_S D)funcstack:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $funcstack)"
  # echo "$(_S D)functrace:$(_S)       $(gdm.quoteElem -f="$PWD" -r=$replace $functrace)"

}
callcall() {
  gdm.callerDetails
}
callcall




# ! [[ $ZSH_EVAL_CONTEXT =~ ':file$' ]] && gdm $@