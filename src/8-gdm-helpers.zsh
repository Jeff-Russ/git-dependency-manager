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

gdm_getInode() {
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


gdm_typeof() {
  if [[ -z "$1" ]] || [[ "$1" == --help ]] ; then
    cat << 'USAGEDOC'
getType accepts a string which could be something executable, a file, variable, reserved word or hash
and outputs what it is. The output could be:
    'executable:builtin'
    'executable:command'
    'executable:function' 
    'executable:file'
    'file'                 # not executable but still could be source(able) code of some sort
    'hashed'               # assumed to not be executable
    'reserved'             # assumed to not be executable
    'variable:scalar'*     
    'variable:array'*
    'variable:association'*
                            # (no output) indicates input is not any of the above
NOTE that there are more variable types than those listed above (as hinted at with the * wildcard)
Beside the 'file' 'hashed' and 'reserved' outputs, 
  all executable types are prepended with 'executable:' and 
  all that are variables with 'variable:scalar' 
Checks for non-variable types are performed first and the checks for variable are performed, even if the first check
had a result. Therefore it is possible to have MORE THAN ONE RESULT, such as 'executable:function variable:scalar-export'
USAGEDOC
    if [[ "$1" == --help ]] ; then return 0 ; else return 1 ; fi
  fi

  local result=""
	local cap="$(whence -w "$1" 2>/dev/null)"  # `-w` show if alias,  builtin,  command,  function, hashed, reserved or none
  local whenceType="$(echo "$cap" | awk '{print $NF}')"
  case $whenceType in
    function|builtin) 
      result="executable:$whenceType"
      ;;
    command)
      if [[ -f "$1" ]] && [[ -x "$1" ]] ; then result="executable:file" ; else result="executable:command" ; fi
      ;;
    alias)
      local verbose first_word_of_alias_val
      verbose="$(whence -v "$1")"
      first_word_of_alias_val="$(echo  ${verbose#* alias for } | head -n1 | awk '{print $1;}')"
      if [[ "$first_word_of_alias_val" == "$verbose" ]] ; then result=alias
      elif [[ "$(getType $first_word_of_alias_val 2>/dev/null)" =~ ^'executable' ]] ; then result='executable:alias'
      else result=alias
      fi
      ;;
    *)  # hashed, reserved or none
      if [[ "$whenceType" == 'none' ]] ; then
        if [[ -f "$1" ]] ; then 
          if [[ -x "$1" ]] ; then result='executable:file' ; else result='file' ; fi
        fi
      else result="$whenceType"
      fi
      ;; 
  esac

  if eval "(( \${+$1} ))" 2>/dev/null ; then  # if a variable... get type
    local operand='${(t)'"$1"'}'
    local vartype="$(eval "print -rl -- $operand" 2>/dev/null)"
    if ! [[ -z "$vartype" ]] ; then
      if [[ -z "$result" ]] ; then result="variable:$vartype"
      else result="$result variable:$vartype"
      fi
    fi
  fi
  [[ -z "$result" ]] && return 1
  echo "$result"
  return 0
}

gdm_echoVars() {
  local declare_local=false
  if [[ "$1" == --declare-local ]] ; then declare_local=true ;  shift ; fi
  
  for var_name in $@ ; do
    if [[ "$var_name" =~ '^[ ]*#' ]] ; then echo  "$var_name ;" # echo comment
    elif [[ "$var_name" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]*=.+' ]] ; then  # custom variable name with assignment
      if $declare_local && ! [[ "$var_name" =~ '^(local|typeset|declare) ' ]] ; then 
        print -- "local ${var_name} ; " 
      else print -- "${var_name} ; " ; fi
    elif [[ "$(gdm_typeof $var_name)" =~ 'array' ]] ; then 
      if $declare_local ; then  print -- "local $var_name=($(print -- \"${^${(P)var_name}}\")) ; " 
      else # For arrays we aren't declaring as local...
        # ...we append (helpful if evaled from place with array already existing. 
        # If echoer has that array empty, this causes no issues (nothing is appended).
        print -- "$var_name+=($(print -- \"${^${(P)var_name}}\")) ; "  ; fi
    elif [[ "$(gdm_typeof $var_name)" =~ 'association' ]] ; then
      if $declare_local ; then print -- "declare -A $var_name=$(gdm_mapVal $var_name) ;"
      else print -- "$(typeset -p $var_name) ; "
      fi
    else
      if $declare_local ; then print -- "local ${var_name}=\"${(P)var_name}\" ; "
      else print -- "${var_name}=\"${(P)var_name}\" ; "
      fi
      
    fi
  done
}

# gdm_echoVars() {
#   local declare_local=false
#   local inline=false
#   local no_semi=false
#   local shifts=0
#   for arg in $@ ; do 
#     if   [[ "$arg" == --declare-local ]] ; then  declare_local=true ;  ((shifts++)) ;
#     elif [[ "$arg" == --inline ]] ; then inline=true ; ((shifts++)) ;
#     elif [[ "$arg" == --no-semi ]] ; then no_semi=true ; ((shifts++)) ;
#     else break
#     fi
    
#   done
#   ((shifts)) && shift $shifts

#   local append=" "
#   ! $no_semi && append+="; "
#   $inline && append+="\n"


#   for var_name in $@ ; do
#     if [[ "$var_name" =~ '^[ ]*#' ]] ; then echo  "$var_name ;" # echo comment
#     elif [[ "$var_name" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]*=.+' ]] ; then  # custom variable name with assignment
#       if $declare_local && ! [[ "$var_name" =~ '^(local|typeset|declare) ' ]] ; then 
#         print -- "local ${var_name} ; " 
#       else print -- "${var_name} ; " ; fi
#     elif [[ "$(gdm_typeof $var_name)" =~ 'array' ]] ; then 
#       if $declare_local ; then  print -- "local $var_name=($(print -- \"${^${(P)var_name}}\")) ; " 
#       else # For arrays we aren't declaring as local...
#         # ...we append (helpful if evaled from place with array already existing. 
#         # If echoer has that array empty, this causes no issues (nothing is appended).
#         print -- "$var_name+=($(print -- \"${^${(P)var_name}}\")) ; "  ; fi
#     elif [[ "$(gdm_typeof $var_name)" =~ 'association' ]] ; then
#       if $declare_local ; then print -- "declare -A $var_name=$(gdm_mapVal $var_name) ;"
#       else print -- "$(typeset -p $var_name) ; "
#       fi
#     else
#       if $declare_local ; then print -- "local ${var_name}=\"${(P)var_name}\" ; "
#       else print -- "${var_name}=\"${(P)var_name}\" ; "
#       fi
      
#     fi
#   done
# }

gdm_echoAndExec() {
  local err_code err_cap 
  local newline_patt="$(echo '.*'; echo '.*')"
  local cmd="$@"
  local append="" ; [[ "$cmd" =~ "$newline_patt$" ]] && append="#..."
  print -- "$(_S B)$(echo "${cmd//$GDM_REGISTRY/\$GDM_REGISTRY}" | head -1)$(_S)$append" >&2
  
  err_cap="$(eval "$@" 1>/dev/null 2>&1)" ; err_code=$?
  if ((err_code)) ; then echo "$cap\n$(_S R S)Terminating due to error code $err_code$(_S)" >&2 ; return $err_code ; fi
}

gdm_mapDecl() { local result ; result="$(typeset -p "$1")" || return $? ; } # unused

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


! which abspath 2>/dev/null 1>&2 && 
function abspath(){ 
  if [[ -z "$1" ]] || (($#>2)) || [[ "$1" == --help ]] ; then
    print "abspath outputs an absolute path from \$1, relative path (which need not exist)" >&2
    print "        that is relative to a path \$2 (which also need not exist).\nUsage:" >&2
    print "  abspath \$relpath [\$wd_of_relpath] # where the 2nd argument defaults to \$PWD\nCaveats:" >&2
    print "  If the second argument is a relative path, it is assumed to be relative to \$PWD." >&2
    print "  If the second argument does not exist, it cannot contain and path segments that:" >&2
    print "    1) exist but are not directories or" >&2
    print "    2) exist as directories which cannot be modified." >&2
    [[ "$1" != --help ]] && return 1 || return 0
  fi

  local target="$1"
  local wd="${2:a}" # local wd="$2" ; [[ "${wd[-1]}" == '/' ]] && wd="${2[1,-2]}"

  if [[ -z "$wd" ]] || [[ "$wd" == "$PWD" ]] || [[ "$wd" == '/' ]]  ; then print "${target:a}" ; return $?  # make absolute path via $PWD or /
  elif [[ -e "$wd" ]] ; then
    ! [[ -d "$wd" ]] && { print "$0 provided second arguments cannot exist as non-directories (got '$2')" >&2 ; return 1 ; }
    (cd $wd && print $target) || return $? # output absolute path from path relative to existing path
    return 0
  fi
  # else make absolute path from a path relative to a non-existing working dir by temporarily creating the working dir
  local path_segs=( ${(s:/:)wd} )    # split by '/' delimiter (lack of quotes around expansion prevents empty elements).
  local nonexist="/${path_segs[1]}"  # This will be the top (containing) directory to not exist i.e. the one to delete when 
  local i=2                          # cleaning up. Additional segments beyond nonexist, if any, won't exist either.
  while [[ -d "$nonexist" ]] && ((i<=$#path_segs)) ; do nonexist+="/${path_segs[$((i++))]}" ; done # accum up to non-existent segment
  [[ -e "$nonexist" ]] && { print "$0 provided second arguments cannot contain non-directories (contained '$nonexist')." >&2 ; return 1 ; }
  mkdir -p "$wd" || return $?        # Make temp directory(s). This will fail if, for example, making the path effectively adds a new user $HOME
  print "$(cd $wd && print ${target:a})" # Make absolute path from path relative to existing path
  rm -rf "$nonexist"                 # Clean up temp directory(s) by removing them.
}


! which relpath 2>/dev/null 1>&2 && 
function relpath(){
  # based on: https://stackoverflow.com/a/14914070
  # NOTE: requires abspath
  if [[ -z "$1" ]] || (($#>2)) || [[ "$1" == --help ]] ; then
    echo "$0 requires one or two arguments: a path string to be converted to a path" >&2
    echo "relative to the second argument or relative to \$PWD if no second argument given." >&2
    [[ "$1" != --help ]] && return 1 || return 0
  fi

  local target="$1"
  local current="$2"
  if [[ -z "$current" ]] ; then current="$PWD"
  elif [[ -e "$current" ]] ; then current="${current:a}"
  else
    # NOTE: ${1:a} would give erronous results if $current is not actually $PWD or if our
    current="$(abspath $current)" || return $? # non-existent absolute path from current assuming current is relative to $PWD
    target="$(abspath $target $current)" || return $? # non-existent absolute path from target assuming current is relative non-existent current
  fi

  local appendix=${target#/} # set appendix is target without any leading /
  local relative=''

  while appendix=${target#$current/} # (do always) appendix is set to target w/o any $current/ prepended to it
    [[ $current != '/' ]] && [[ $appendix = $target ]] ; do 
    if [[ $current = $appendix ]]; then
      relative=${relative:-.} # if relative is null, set it to '.'
      print ${relative#/} # relative without any leading /
      return 0
    fi
    current=${current%/*} # remove the last /* from current
    relative="$relative${relative:+/}.." # append to relative: '/' but only if relative is non-null + '..'
  done
  relative+=${relative:+${appendix:+/}}${appendix#/} # append to relative: '/' if relative AND appendix are non-null + $appendix w/o any leading /
  print $relative
}

# gdm_relpath() {

#   while [[ "$relative[-1]" == '/' ]] ; do relative="$relative[1,-2]" ; done # remove trailing / (we may put back)
#   if [[ $relative != *'/'* ]] ; then relative="./$relative" # prepend if no / anywhere or empty string
#   elif [[ $relative =~ '^(\.\.|\.)$' ]] ; then  relative+=/  # .. to  ../    . to ./ 
#   else 
#     [[ $relative == *'/..' ]] && relative+=/ ; # */.. to */../
#     [[ $relative =~ '^[^\.]+\/' ]] && relative="./$relative" ;
#   fi
#   echo $relative
# }

