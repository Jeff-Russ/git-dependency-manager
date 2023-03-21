export GDM_MIN_HASH_LEN=7

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
    elif typeset -f "$setup" >/dev/null 2>&1 ; then
      # setup is FUNCTION: we use it's source code as a string to form the hash
      autoload +X "$setup"  # loads an autoload function without executing it so we can call whence -c on it and see source
      if ! setup_val="$(whence -cx 2 "$setup" 2>/dev/null)" ; then echo "$(_S R S)$orig_setup (setup function) cannot be read!$(_S)" >&2 ; return 1 ; fi
    else
      setup_val="$setup" # and hope for the best when we actually run it!
    fi
    $0.strToHash() { crc32 <(echo "$1") ; }
    if ! setup_hash=$($0.strToHash "$setup_val") ; then echo "$(_S R S)$orig_setup (setup) cannot be hashed!$(_S)" >&2 ; return 1 ; fi

    regis_suffix="_setup-$setup_hash"
  fi


  # echo -n "$requirement\nsetup=\"$setup\"\ndestin_instance=\"$destin_instance[1]\"\nregis_parent_dir=\"$GDM_REGISTRY/${${remote_url#*//}:r}\"\nregis_prefix=\"$regis_prefix\"\nregis_suffix=\"$regis_suffix\"" 
  destin_instance="${destin_instance[1]:a}"
  
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
