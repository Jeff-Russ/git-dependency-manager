
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
  
  if ! remote_url="$( $0.main "$remote_ref" )" ; then  # if lower casing fails...
    remote_ref="$1" # try original casing
    if ! remote_url="$( $0.main "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
      return $GDM_ERRORS[cannot_expand_remote_url]
    fi
  fi
  echo "$remote_url" ; return 0
  
}


gdm_expandDestination() {
  # INPUT: 
  #     "$destin" (not including tag, only portion after =) WHICH MUST NOT BE EMPTY
  # OUPUT (without error):
  #     if return is 0, assignments of the following: 
  #         destin        # input, possibly reformed to standardized so any given required_path destin_relto combo has one notation.
  #                       # NOTE: If input is empty return will be 0 and output will show 
  #                           destin="" destin_relto=GDM_REQUIRED required_path=""
  #                       #   which signals that destin and required_path should be derived from the repository name.
  #         destin_relto  # value is:
  #             HOME           if destin starts with ~/
  #             GDM_PROJ_ROOT  if destin starts with ./ or ../
  #             SYSTEM_ROOT    if destin starts with /
  #             GDM_REQUIRED   if destin does not start with any of the above or is empty
  #         required_path # absolute path of destin, relative to $destin_relto. Blank if input was empty
  # ERRORS REASONS: Colored stderr message with return of $GDM_ERRORS[invalid_destination_arg] if any of the following...
  #         allow_destin_relto_$destin_relto isn't in GDM_EXPERIMENTAL and destin_relto is GDM_PROJ_ROOT HOME SYSTEM_ROOT
  #         destin regex is '~/*' or only contains: dots . and/or forward slashes / (destin is: / ~/ ../ ./ ~ .. or .)
  #         HOME          but is NOT within or equals: ($HOME)
  #         HOME          but is within or equals: ($GDM_REQUIRED or $GDM_PROJ_ROOT) 
  #         SYSTEM_ROOT   but is within or equals: ($GDM_REQUIRED or $GDM_PROJ_ROOT or $HOME)
  #         GDM_PROJ_ROOT but is within or equals: ($GDM_REQUIRED)
  #         GDM_PROJ_ROOT (starting ../) but is     within or equals: ($GDM_PROJ_ROOT) 
  #         GDM_PROJ_ROOT (starting ./)  but is NOT within or equals: ($GDM_PROJ_ROOT) 
  # IMPORTANT: 
  #        1) The input $destin should never be provided with a value starting with $HOME or unquoted ~/ ../ or ./ as these
  #           would expand to SYSTEM_ROOT paths and then fail for being within $HOME or somewhere else not allowed. 
  #        2) This function isn't fully tested for any GDM_EXPERIMENTAL mode enabled.
  # DEPENDS ON BEING SET AND VALID: 
  #     GDM_PROJ_ROOT (GDM_EXPERIMENTAL GDM_REQUIRED GDM_ERRORS) gdm_echoVars abspath relpath _S
  local INVALID=$GDM_ERRORS[invalid_destination_arg]

  if [[ "$1" =~ '^(~/*|[./]+)$' ]] ; then  # destin is ~/+ or only contains: dots ('.') and/or forward slashes ('/')
    echo "$(_S R)destin='$1' path provided does not contain a directory name$(_S)" >&2 ; return $INVALID 
  fi 

  local outputVars=( destin destin_relto required_path ) ;  local $outputVars
  destin="$1" # should already be extracted from argument after first = sign.
  while [[ "$destin[-1]" == '/' ]] ; do destin="$destin[1,-2]" ; done # remove trailing /

  #TODO: the following requires that GDM_REQUIRED not start with ~/ or be a full path or else gdm_required_abs will be wrong!
  local gdm_required_abs="$GDM_PROJ_ROOT/$GDM_REQUIRED" ; gdm_required_abs="${gdm_required_abs:a}" 
  local gdm_required_is_in_proj=false ; [[ "$gdm_required_abs" == "$GDM_PROJ_ROOT"* ]] && gdm_required_is_in_proj=true
  
  if [[ "$destin" != *'/'*  ]] ; then # A quick return for the most common scenario: 
    destin_relto='GDM_REQUIRED' # And would pass whether we allow allow_nonflat_GDM_REQUIRED or not
    ! [[ -z "$destin" ]] && required_path="$gdm_required_abs/$destin" 
    gdm_echoVars $outputVars ;
    return 0 ;
  fi

  local not_within=()

  0.checkAllow() {
    if ! (($GDM_EXPERIMENTAL[(Ie)allow_destin_relto_$destin_relto])) ; then
      echo "$(_S R)destin='$destin' is a path relative to $destin_relto which is not allowed unless "
      echo "'allow_destin_relto_$destin_relto' is added to the exported GDM_EXPERIMENTAL array.$(_S)" >&2 ; return $INVALID
    else return 0
    fi
  }
  0.err() { echo "$(_S R)$1$(_S)" >&2 ; return $INVALID ; }

  if [[ "$destin" == '~/'* ]] ;           then # destin starts with ~/ (and is not HOME itself due to '^(~/+|[./]+)$' check)
    destin_relto='HOME' ; 0.checkAllow || return $INVALID
    required_path="$HOME${destin[2,-1]}" ; required_path="${temp_destin:a}" # bc zsh :a fails with ~/ (try destin='~/place/../../')

    # RESTRICTIONS: $destin must 1) be in and not equal to $HOME ...
    if [[ "$required_path" != "$HOME/"* ]] ; then 
      0.err "destin='$destin' is a path relative to $destin_relto which must be within HOME directory and not equal to it" ; return $?
    fi # ...and not be within 2) $GDM_PROJ_ROOT ...
    not_within=(GDM_PROJ_ROOT) # ...and 3) not be within $GDM_REQUIRED but all but GDM_REQUIRED will be checked for for that
    

  elif [[ "$destin" =~ '^(\.\.\/|\.\/)' ]] ; then 
    destin_relto='GDM_PROJ_ROOT'  ; 0.checkAllow || return $?
    required_path="$(abspath $destin $GDM_PROJ_ROOT)"

    # RESTRICTIONS: $destin ...
    if [[ "$destin" == './'* ]] ; then # 1) if starting with ./ must be IN and not equal to $GDM_PROJ_ROOT...
      if [[ "$required_path" != "$GDM_PROJ_ROOT/"* ]] ; then 
        0.err "destin='$destin' is a path relative to $destin_relto and starting ./ which must be within and not equal to GDM_PROJ_ROOT" ; return $?
      fi
      destin="./$(relpath $required_path $GDM_PROJ_ROOT)" # REFORM destin 
    fi  
    if [[ "$destin" == '../'* ]] ; then  # ...and 2) if starting with ../ must be NOT be in or equal to $GDM_PROJ_ROOT...
      if [[ "$required_path" == "$GDM_PROJ_ROOT"* ]] ; then 
        0.err "destin='$destin' is a path relative to $destin_relto and starting ../ which must NOT be within or equal to GDM_PROJ_ROOT"  ; return $?
      fi
      destin="$(relpath $required_path $GDM_PROJ_ROOT)"
    fi
    # ...and 3) not be within $GDM_REQUIRED but all but GDM_REQUIRED will be checked for for that
    
  elif [[ "$destin" == '/'* ]] ; then   # destin starts with / (and is not / itself due to '^(~/+|[./]+)$' check)
    destin_relto='SYSTEM_ROOT'  ; 0.checkAllow || return $?
    required_path="${destin:a}"
    destin="$required_path" # REFORM destin 

    # RESTRICTIONS: $destin must not be within 1) $HOME 2) $GDM_PROJ_ROOT
    not_within=(HOME GDM_PROJ_ROOT) # ...and 3) not be within $GDM_REQUIRED but all but GDM_REQUIRED will be checked for for that

  elif (($GDM_EXPERIMENTAL[(Ie)allow_nonflat_GDM_REQUIRED])) ; then
    destin_relto='GDM_REQUIRED'
    required_path="$(abspath $destin $gdm_required_abs)"
    # RESTRICTION: $destin 1) must in IN but not equal to $gdm_required_abs and that's it!
    if [[ "$required_path" != "$gdm_required_abs/"* ]] ; then 
      0.err "destin='$destin' is a path relative to $destin_relto which must be within and not equal to GDM_REQUIRED" ; return $?
    fi
    destin="$(relpath $required_path $gdm_required_abs)" # REFORM destin 
    gdm_echoVars $outputVars ; return 0 ;
    

  else # destin must be dirname or dirname/+ and was not
    destin_relto='GDM_REQUIRED'
    local err="destin='$destin' is a path relative to $destin_relto which must be DIRECT child of the"
    0.err "$err\nGDM_REQUIRED directory unless 'allow_nonflat_GDM_REQUIRED' added to the GDM_EXPERIMENTAL array." ; return $?
  fi

  if [[ "$required_path" == "$gdm_required_abs/"* ]] ; then
    0.err "destin='$destin' is a path relative to $destin_relto which must not be within or equal to GDM_REQUIRED" ; return $?
  fi 

  for location in $not_within ; do  
    if [[ "$required_path" == "${(P)location}"* ]] ; then
      0.err "destin='$destin' is a path relative to $destin_relto which must not be within or equal to $location" ; return $?
    fi
  done

  gdm_echoVars $outputVars ; return 0 ; 
}

tst() {
  [[ "$1" =~ '^([./]+)$' ]] && echo "only dots or only slashes" || echo "has non dot/slash chars"
}



gdm_setupToHash() {
  # POSSIBLE ERRORS invalid_setup (previously also return 1 for $0.strToHash failure)
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
  if ! setup_hash=$($0.strToHash "$setup_target") ; then echo "$(_S R S)$setup (setup) cannot be hashed! $(_S)" >&2 ; return $GDM_ERRORS[invalid_setup]; fi # changed from return 1 (good idea?)
  
  echo $setup_hash
  return 0
}


# TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
gdm_isNonPathStr() {  # used in  helpers: gdm.parseRequirement  
  # if string contains only . and / characters or it contains any /, it's a path so it fails
  # (whether it exists or not) This also fails if passed string with * or ~ because path expansion
  [[ "$1" =~ '^[.]*$' ]] || test "${1//\//}" != "$1" && return 1 || return 0
}



gdm_multiArgError() { echo "$(_S R S)$1 has multiple $2 specified! $(_S)" >&2 ; return $GDM_ERRORS[invalid_argument] ; }

