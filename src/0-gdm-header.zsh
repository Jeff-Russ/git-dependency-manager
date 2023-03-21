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
export GDM_REQUIRED="${GDM_REQUIRED:=gdm_required}"         # can be overridden by $GDM_CONF file
export GDM_REQUIRE_CONF="gdm.zsh" 
export GDM_REQUIRED_LOCK="${GDM_REQUIRED_LOCK:=gdm_require.lock}"

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
  [malformed_config_file]=61
  [cannot_find_proj_root]=62
  [nested_proj_not_called_from_root]=63
  [mkdir_$GDM_REQUIRED]=65
  [hardlink_failed]=66

  [left_corrupted]=91
  [gdm_error_code_misread]=92
)

gdm.error() {
  echo "${(k)GDM_ERRORS[(r)$1]}"
}


if (($#==1)) && [[ "$1" =~ '^-' ]] ; then
  if [[ "$1" =~ '^(--version|-v)$' ]] ; then
    echo "$GDM_VERSION" ; return 0
  elif [[ "$1" =~ '^--compat=.+' ]] ; then
    ! [[ "${1[10,-1]}" =~ "^$GDM_VER_COMPAT.*" ]] && return $GDM_ERRORS[gdm_version_outdated]
    return 0
  fi
fi
# echo "GDM header got $# args: $@"