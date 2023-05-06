
gdm_expandRemoteRef() {
  # expected arg: a repo_identifier: [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  # NEW: is expanded to set output, which sets: remote_url rev rev_is hash tag branch
  #   remote_ref=<before # in repo_identifier>         (never blank)
  #   rev=[<value after # in repo_identifier]          (may be blank)
  #   remote_url=<full_remote_url> (from remote_ref)   (never blank)
  #   rev_is="hash|tag|tag_pattern|branch"             (never blank)
  #   hash=<full_hash>                                 (never blank)
  #   tag=[<full_tag>]                                 (may be blank)
  #   branch=[<branch_name>]                           (may be blank)

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


  local outputVars=(remote_ref rev remote_url rev_is hash tag branch)
  local remote_ref="${1%#*}"
  local remote_url
  
  if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
    echo "$(_S R)Cannot expand Remote Url from $remote_ref$(_S)" >&2 ; return $GDM_ERRORS[cannot_expand_remote_url]
  fi
  
  local rev="${1##*#}" ;  [[ "$1" == "$rev" ]] && rev="" # ${1##*#}" is everything after #
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
    echo "$(_S R S)Cannot expand \"$1\". Found remote but no matches found for \"$provided\"$(_S)" >&2 ; return $GDM_ERRORS[cannot_find_revision]
  fi

  local hash="$(echo $hits[1] | awk '{ print $1 }')"  # ; local branch='' ; local tag=''

  [[ $rev_is == tag_pattern ]] && hits=("${hits[1]}") # we allow multiple hits (taking first) if rev was tag pattern
  # But other multiple hash hits are not allowed so if hits contains any other hash, return error:
  if (($#hits>1)) && (($(print -l $hits | grep -vE "^$hash" | grep "" -c)>0)) ; then  # branch tag or hash had too many matches so:

    $0.echoErr() { echo "$(_S R S)Cannot expand \"$1\". Found remote but multiple $2 matching \"$3\" found.$(_S)" >&2 ; }

    if   [[ $rev_is == 'branch' ]] ; then $0.echoErr $1 branches $provided ; return $GDM_ERRORS[cannot_find_branch]
    elif [[ $rev_is == 'tag'* ]]   ; then $0.echoErr $1 tags $provided ; return $GDM_ERRORS[cannot_find_tag]
    elif [[ $rev_is == 'hash' ]]   ; then $0.echoErr $1 hashes $provided ; return $GDM_ERRORS[cannot_find_hash]
    else  echo "$(_S R S)Cannot expand \"$1\". Found remote but no matches found for \"$provided\"$(_S)" >&2 ; return $GDM_ERRORS[cannot_find_revision]
    fi
  fi
  [[ -z $branch ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/heads/")}") && (($#hits>0)) && branch="${hits[1]##*refs/heads/}"
  [[ -z $tag ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/tags/")}") && (($#hits>0)) && tag="${hits[1]##*refs/tags/}"
  rev="$provided"

  gdm_echoVars $outputVars
  return 0
}

gdm_gitExpandRemoteUrl() { 
  [[ -z "$1" ]] && return 3 # none provided

  $0.main() {
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
  
  remote_ref="${1:l}" # we try lowercased first to avoid multiple registrations
  local remote_url
  
  if ! remote_url="$( $0.main "$remote_ref" )" ; then
    remote_ref="$1" # try original casing
    if ! remote_url="$( $0.main "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
      return $GDM_ERRORS[cannot_expand_remote_url]
    fi
  fi
  echo "$remote_url" ; return 0
  
}

gdm_setupToHash() {
  local setup="$1" # value after = in setup=
  # Here we resolve value of $setup to something that doesn't change and then form a $hash from that
  local setup_target="" # this is cat of file if setup is script, source of function if typeset -f "$setup" else just setup copied
  if [[ -f "${setup:a}" ]] ; then # setup is SCRIPT: we use the cat value to form the hash
    setup_is=script 
    local setup_a="${setup:a}" # we resolve to full path so we can call from anywhere
    if [[ "$setup_a" != "$GDM_PROJ_ROOT"* ]] ; then echo "$(_S R S)$setup (setup script) is not contained withing project root! $(_S)" >&2 ; return $GDM_ERRORS[invalid_setup]  ; fi
    ! [[ -x "$setup_a" ]] && chmod +x "$setup_a"
    if ! setup_target="$(cat "$setup_a" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup script) cannot be read! $(_S)" >&2 ; return $GDM_ERRORS[invalid_setup]  ; fi
  elif typeset -f "$setup" >/dev/null 2>&1 ; then # setup is FUNCTION: we use it's source code as a string to form the hash
    setup_is=function  
    autoload +X "$setup"  # loads an autoload function without executing it so we can call whence -c on it and see source
    if ! setup_target="$(whence -cx 2 "$setup" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup function) cannot be read! $(_S)" >&2 ; return $GDM_ERRORS[invalid_setup] ; fi
  else
    echo "$(_S R S)$setup (setup) is not a script or function! $(_S)" >&2 ; return $GDM_ERRORS[invalid_setup] ;
  fi
  $0.strToHash() { crc32 <(echo "$1") ; }
  if ! setup_hash=$($0.strToHash "$setup_target") ; then echo "$(_S R S)$setup (setup) cannot be hashed! $(_S)" >&2 ; return 1 ; fi
  
  echo $setup_hash
  return 0
}


# TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
gdm_isNonPathStr() {  # used in  helpers: gdm.parseRequirement  
  # if string contains only . and / characters or it contains any /, it's a path so it fails
  # (whether it exists or not) This also fails if passed string with * or ~ because path expansion
  [[ "$1" =~ '^[.]*$' ]] || test "${1//\//}" != "$1" && return 1 || return 0
}

gdm_pathNotation() {
  # possible outputs:
  #     "relative to /"    "equivalent to /" 
  #     "relative to ../"  "equivalent to ../"
  #     "relative to ./"   "equivalent to ./"
  #     "relative to ~/"   "equivalent to ~/"
  #     "relative to name" "empty"
  if [[ "$1" == '/'* ]] ; then 
    [[ "$1" =~ '^[\/]+$' ]] && echo "equivalent to /" || echo "relative to /"
  elif [[ "$1" == '..'* ]] && [[ "$1" != '...'* ]] ; then
    if [[ "$1" =~ '^\.\.[\/]*$' ]] ;        then echo "equivalent to ../"
    elif [[ "$1" =~ '^\.\.[\/]+[^\/]+' ]] ; then echo "relative to ../" 
    else                                         echo "relative to name"
    fi
  elif [[ "$1" == '.'* ]] ; then
    [[ "$1" =~ '^\.[\/]*$' ]] && echo "equivalent to ./" || echo "relative to ./"
  elif [[ "$1" == '~'* ]] ; then 
    [[ "$1" =~ '^~[\/]*$' ]] && echo "equivalent to ~/" || echo "relative to ~/"
  elif ! [[ -z "$1" ]] ; then  echo "relative to name"
  else echo 'empty'
  fi
}

gdm_multiArgError() { echo "$(_S R S)$1 has multiple $2 specified! $(_S)" >&2 ; return $GDM_ERRORS[invalid_argument] ; }

