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

export GDM_SCRIPT="$0"
export GDM_VERSION="1.0beta"
export GDM_VER_COMPAT="1.0"
export GDM_REGISTRY="${GDM_REGISTRY:=$HOME/.gdm_registry}" # might have been defined in environment
export GDM_REQUIRED="${GDM_REQUIRED:=gdm_required}"         # can be overridden by $GDM_REQUIRE_CONF file
export GDM_REQUIRE_CONF="gdm.zsh" 
export GDM_CONFIG_LOCKVARS=(to remote_url hash tag setup_hash) # IN ORDER
# export GDM_REQUIRED_LOCK="${GDM_REQUIRED_LOCK:=gdm_require.lock}"

# environment variables used in require and register:
export GDM_MANIF_EXT="gdm_manifest"
export GDM_MANIF_VARS=(gdm_manifest_inode gdm_version register_path remote_url hash tag setup_hash)
export GDM_MANIF_VALIDATABLES=(register_path remote_url hash tag setup_hash)
# used only in register:
export GDM_SNAP_EXT="gdm_snapshot"

# used only in gdm_parseRequirement:
export GDM_MIN_HASH_LEN=7 

# NOTE: additional exported variables are in *-gdm-project.zsh


declare -Ag GDM_ERRORS=(
  # RENAMED GDM_ERRORS keys:
  #   instance_missing        -> register_instance_missing        AND required_instance_missing
  #   manifest_missing        -> register_manifest_missing        AND required_manifest_missing
  #   lone_instance           -> register_manifest_unlinked       AND required_manifest_unlinked
  #   manifest_inode_mismatch -> register_manifest_inode_mismatch AND required_manifest_inode_mismatch
  #   snapshot_check_failed -> register_snapshot_gitswap_failed   AND required_snapshot_gitswap_failed
  # NOTE: previously snapshot_check_failed was listed under gdm.register errors so it was really just today's register_snapshot_gitswap_failed
  #   gdm_version_outdated    -> register_manifest_version_outdated AND required_manifest_version_outdated
  # NOTE gdm_version_outdated was also retained for user checking against hypothetical 
  #   manifest_requirement_mismatch -> register_manifest_requirement_mismatch AND required_manifest_requirement_mismatch
  #   instance_snaphot_mismatch -> required_was_modified
  #   snapshot_check_mismatch -> register_was_modified  AND required_was_modified
  #   regis_snapshot_missing -> register_snapshot_missing

  [gdm_version_outdated]=5 # retained for user checking (see below in this)

  # gdm_parseRequirement errors:
  [cannot_expand_remote_url]=11
  [cannot_find_revision]=12
  [cannot_find_branch]=13
  [cannot_find_tag]=14
  [cannot_find_hash]=15
  [invalid_argument]=16


  # gdm_validateInstance errors (evaluted in order except for register_snapshot_missing which happens in either mode)
  [register_instance_missing]=21              # $register_path directory does not exist
  [register_manifest_missing]=22              # $register_manifest file does not exist 
  [register_manifest_unlinked]=23             # --disallow-lone (not the default) and $register_manifest has no hardlinks
  [register_manifest_inode_mismatch]=23       # $register_manifest file's inode does not match what the file says it is
  [register_manifest_version_outdated]=25     # $register_manifest gdm_version does not start with GDM_VER_COMPAT
  [register_manifest_requirement_mismatch]=26 # if certain $register_manifest variables mismatch requirement
  [register_snapshot_gitswap_failed]=27       # cannot swap $register_path/.git to or from $register_path.gdm_snapshot/.git
  [register_was_modified]=28                  # if $register_path code mismatches snapshot
  [register_snapshot_missing]=30              # (NO MATTER gdm_validateInstance IS PASSED --register OR --required)
  [required_instance_missing]=31              # $required_path directory does not exist
  [required_manifest_missing]=32              # $required_manifest file does not exist
  [required_manifest_unlinked]=33             # --disallow-lone (not the default) and $required_manifest has no hardlinks
  [required_manifest_inode_mismatch]=34       # $register_manifest file's inode does not match what the file says it is
  [required_manifest_version_outdated]=35     # $required_manifest gdm_version does not start with GDM_VER_COMPAT
  [required_manifest_requirement_mismatch]=36 # certain $required_manifest variables mismatch requirement
  [required_snapshot_gitswap_failed]=37       # cannot swap $required_path/.git to or from $required_path.gdm_snapshot/.git
  [required_was_modified]=38                  # $required_path code mismatches snapshot

  # gdm.register errors:
  [clone_failed]=41 
  [checkout_failed]=42
  [setup_returned_error]=43
  [manifest_creation_failed]=44
  [snapshot_tempdir_failed]=45
  [snapshot_preswap_failed]=46
  [snapshot_mkdir_failed]=47
  [snapshot_mv_git_failed]=48
  [snapshot_postswap_failed]=49

  # gdm.require errors
  [invalid_GDM_REQUIRED_path]=61
  [malformed_config_file]=62
  [cannot_find_proj_root]=63
  [nested_proj_not_called_from_root]=64
  [mkdir_GDM_REQUIRED_failed]=65
  [hardlink_failed]=66
  [no_project_found]=67

  [left_corrupted]=91
  [gdm_error_code_misread]=92
)

gdm.error() { echo "${(k)GDM_ERRORS[(r)$1]}" ; } # reverse lookup return error codes (GDM_ERRORS)

# currently accepted GDM_EXPERIMENTAL element values: (NOTE: ALL ARE VERY DANGEROUS TO FILESYSTEM)
# flexible_required_paths     (allow require installation destinations outside of project's GDM_REQUIRED dir)
# any_required_path     (allow project's GDM_REQUIRED dir to be in any location)
if [[ "$(gdm_typeof GDM_EXPERIMENTAL)" =~ 'array' ]] ; then
    export GDM_EXPERIMENTAL # user has provided so just export to be safe
else export GDM_EXPERIMENTAL=() # add experiemental modes to always enable if use did not specify
fi

# echo "GDM header got $# args: $@"

# PRE-FULLY-SOURCING EXECUTION SHORTCUT:
if (($#==1)) && [[ "$1" =~ '^-' ]] ; then
  if [[ "$1" =~ '^(--version|-v)$' ]] ; then
    echo "$GDM_VERSION" ; return 0
  elif [[ "$1" =~ '^--compat=.+' ]] ; then
    ! [[ "${1[10,-1]}" =~ "^$GDM_VER_COMPAT.*" ]] && return $GDM_ERRORS[gdm_version_outdated]
    return 0
  fi
fi

# CALLED AFTER EVERYTHING IS SOURCED:
gdm() {
  echo "$(_S B)$0 $@$(_S)" #TEST

  (($#==0)) && { echo "$(_S Y)gdm called without arguments$(_S)" >&2 ; return 127 ; }

  local operation="$1"
  shift

  if [[ "$operation" == 'config' ]] ||  [[ "$operation" == 'install' ]] ; then
    echo "$operation called"  #TEST
    if [[ -z "$PROJ_ROOT" ]] ; then
      local err_code
      echo "calling gdm.project" #TEST
      # DO NOT execute gdm.project in subshell i.e. capture
      gdm.project --traverse-parents #FUNCTION CALL: gdm.register
      err_code=$?
      echo "gdm.project returned $err_code" #TEST
      ((err_code)) && return $? 
    else echo "$(_S Y)PROJ_ROOT was not empty!$(_S)"  #TEST
    fi
    # gdm_echoProjVars #TEST

    if (($#)) ; then
      echo "$(_S G)HERE$(_S)" #TEST
      if [[ "$operation" == 'config' ]] ; then echo "$(_S R)Unexpected additional argument(s):$@$(_S)" >&2 ; return 1
      else # "$operation" == 'install'
        gdm.require "${@}"
        return $?
      fi

    
    elif (($#PROJ_CONFIG_ARRAY==0)) ; then
      if (($#PROJ_LOCK_ARRAY>0)) ; then
        echo "TO BE IMPLEMENTED: removal of project requirements with user check" ; return 0
      else echo "$(_S Y)Nothing to install!$(_S)" >&2 ; return 1
      fi
      
    # NORMAL PROJECT 'install'/'config' MODE: iterating over config array to require each:
    else
      echo "NORMAL MODE" #TEST
      # PROJ_CONFIG_IDX=0
      # for requirement in "${PROJ_CONFIG_ARRAY[@]}" ; do
      #   ((++PROJ_CONFIG_IDX))
      #   local require_args ; eval "require_args=( $requirement )" ; gdm.require "${require_args[@]}" 
      # done
    fi
  
  # METHOD CALL MODE:
  elif [[ "$(gdm_typeof gdm.$operation)" =~ 'function' ]] ; then
    echo "gdm is executing gdm.$operation $@"
    gdm.$operation "$@" 
    return $?

  # UNKNOWN OPERATION
  else
    echo "$(_S R)gdm failed due to unknown option: $(_S G)$operation$(_S)" ; return 127
  fi
  return $?

}
