gdm_arrayReorderIdxOLD() {
  # USAGE:    gdm_arrayRmIdx source_array [--to=another] [--allow-empty] [all|any-to-1|any] ordering_array|int...
  # DESCRIPTION: gdm_arrayReorderIdx reorders elements of 
  #   source_array passed by name either by directly mutating the source_array (the default) OR
  #   --to=*         (option) by writing to another array passed by name to --to=another
  #   --allow-empty (option) allows you to insert empty elements by placing out-of-range indices in ordering_array
  #   enforcing one of the following restriction:
  #      any-to-any (default) ALLLOWS  the final array to omit any source_array element,     ALLOWING   duplicates OR
  #      any-to-1             ALLLOWS  the final array to omit any source_array element,     PREVENTING duplicates OR
  #      all-to-any           REQUIRES the final array to contain all source_array elements, ALLOWING   duplicates OR
  #      all-to-1             REQUIRES the final array to contain all source_array elements, PREVENTING duplicates OR
  #   ordering_array, an array passed by name or as all subsquent arguments, defines new sequence (ordering_array indices 
  #     are the final array indices) of indices (ordering_array values are the original indices in source_array)
  # EXAMPLES: (each line starts with ar being equal to ar=(one two three four five) )
  #     gdm_arrayReorderIdx ar --to=to 5 4 3 3 1 # to=(five four three three one) and ar is untouched
  #     order=( 5 4 3 3 1 "")
  #     gdm_arrayReorderIdx ar --to=to order # ERROR in gdm_arrayReorderIdx: ordering array 'ordering' contains a non-integer: ""
  #     gdm_arrayReorderIdx ar ${order[1,-2]} # ar=(five four three three one) and ar is untouched
  #     all_w_dup=( 1 3 5 4 4 2 ) ; # fine with any-to-any or all-to-any 
  #     gdm_arrayReorderIdx ar any-to-1 all_w_dup # ERROR in gdm_arrayReorderIdx: ordering_array 'all_w_dup' has 1 duplicate(s), which isn't allowed in 'any-to-1' mode
  #     # same as above with all-to-1
  #     gdm_arrayReorderIdx ar all-to-1 3 2 # ERROR in gdm_arrayReorderIdx: ordering array ommits 3 element(s) from the source, which isn't allowed in 'all-to-1' mode
  #     # same as above with all-to-any
  # REQUIRES: gdm_isArray gdm_isArrayOrEmpty gdm_intArgsRange gdm_arrayAsSet


  # Get source array and make sure it's an array
  if ! gdm_isArray "$1" ; then echo "ERROR in $0: got source array '$1' is not an array" >&2 ; return 1  ; fi
  local src_arr_name="$1" ; shift
  eval 'local _src_size=$#'$src_arr_name

  local destin_arr_name="$src_arr_name"
  local mode=any-to-any ; 
  local fastmode=false
  local allow_empty=false

  # Parse options:
  while [[ "$1" =~ '^--(fastmode|allow-empty|to=.+)$' ]] || [[ "$1" =~ '^(all|any)-to-(1|any)$' ]] ; do
    if [[ "$1" == '--fastmode' ]] ; then fastmode=true
    elif [[ "$1" == '--allow-empty' ]] ; then allow_empty=true
    elif [[ "$1" =~ '^--to=.+' ]] ; then destin_arr_name="${1#*=}" 
      if ! gdm_isArrayOrEmpty $destin_arr_name  ; then echo "ERROR in $0 --to value: '$destin_arr_name' exists as a non-array data typ a non-empty, non-array data type" >&2 ; return 1 ; fi
    else mode="$1"  
    fi
    shift
  done

  # Get ordering array, make sure it's an array and do basic validation making sure it has only valid integers.
  local _order_arr 
  local show_order_arr="" # for error display

  if (($#==1)) ; then
    if ! $fastmode && ! gdm_isArray "$1" ; then echo "ERROR in $0: ordering array '$1' is not an array" >&2 ; return 2  ; fi
    local order_arr_name="$1"
    eval '_order_arr=("${'$order_arr_name'[@]}")' 
    show_order_arr=" '$order_arr_name'"
  else
    _order_arr=("$@") 
  fi


  if ! $fastmode ; then
    local cap ret_err
    if $allow_empty ; then cap="$(gdm_intArgsRange _order_arr)" ; ret_err=$? # this is just to fail for non numbers
    else cap="$(gdm_intArgsRange --min=1 --max=$_src_size _order_arr)" ; ret_err=$? # ret_err is 0 1 2 or 3
    fi
    
    if ((ret_err)) ; then
      if ((ret_err==1)) ; then echo "ERROR in $0: ordering array$show_order_arr contains a non-integer: $cap" >&2 
      else echo "ERROR in $0: ordering_array$show_order_arr contains an invalid index: $cap" >&2 
      fi
      return $((ret_err+2)) # 3 means non-int, 4 means under, 5 means over
    fi
  fi

  # Advanced validation on ordering array for non-default modes:
  if [[ $mode != any-to-any ]] ; then
    if $allow_empty ; then
      echo "ERROR in $0: '$mode' and '--allow-empty' cannot be combined" >&2 ; return 98
    fi
    local order_as_set=() ; gdm_arrayAsSet _order_arr --to=order_as_set || return 99

    if [[ $mode == *'-to-1' ]] ; then 
      local dups=$(($#_order_arr-$#order_as_set))
      if ((dups)) ; then
        echo "ERROR in $0: ordering_array$show_order_arr has $dups duplicate(s), which isn't allowed in '$mode' mode" >&2 
        return 6
      fi
    fi
    if [[ $mode == 'all-to-'* ]] ; then
      local missings=$((_src_size-$#order_as_set))
      if ((missings)) ; then
        echo "ERROR in $0: ordering array$show_order_arr ommits $missings element(s) from the source, which isn't allowed in '$mode' mode" >&2 ; return 7
      fi
    fi
  fi

    
  # if ! $fastmode ; then
  #   local _temp_ar=()
  #   for old_index in "${_order_arr[@]}" ; do
  #     _temp_ar+=("${${(P)src_arr_name}[$old_index]}")
  #   done
  #   eval $destin_arr_name'=('"${_temp_ar[@]}"')' # this may or may not work in copying empty from source (via _order_arr)
  # else # IS THIS EVEN FASTER?
  local _temp_st=""
  for old_index in "${_order_arr[@]}" ; do
    _temp_st+='"${'$src_arr_name'['$old_index']}" '
  done
  eval $destin_arr_name'=( '"$_temp_st"' )'
  # fi
}


gdm_isArray() {
  [[ "$(eval "print -rl -- \${(t)$1}" 2>/dev/null)" == *array* ]] && return 0 || return 1 ;
}

gdm_isArrayOrEmpty() { # formerly gdm_isNonArray (wihout check for empty)
  # Fails if arg is defined as a datatype that is not an array
  # `gdm_isArrayOrEmpty somename`   is NOT the same as   `! gdm_isArray somename`
  # because gdm_isArrayOrEmpty somename does not fail if somename is not defined.
  local datatype
  datatype="$(gdm_datatype $1)" || return 0 ;
  [[ "$datatype" != *'array'* ]] && ! [[ -z "${(P)1}" ]] && return 1 ;
  return 0 ;
}

gdm_intArgsRange() {
  # Usage: 
  #     gdm_intArgsRange [min=<int>] [max=<int>] int_array_name|int...
  # return: 0 if no max or min is specifed
  #         1 if non integer or empty element is found 
  #         2 if min is exceeded
  #         3 if max is exceeded, without output assigning min to first violation found
  # CAVEATS: 
  # Examples:
  #     gdm_intArgsRange 3 1 12 -10 20 # returns 0 with output: "min=-10 ; max=20 ;"
  #     gdm_intArgsRange 3 "+-ten" 1   # returns 2 with output of the first found non-integer value: "+-ten"
  #     gdm_intArgsRange --min=2 3 1   # returns 2 with output of the first found min-violating value: "1"
  #     ints=(3 1 12 -10 20)
  #     gdm_intArgsRange ints          # returns 0 with output: "min=-10 ; max=10 ;"
  #     gdm_intArgsRange --max=10 ints # returns 3 with output of the first found max-violating value: "12"
  local min max
  local first_int=true
  local enforce_min=false ; local enforce_max=false

  $0.checkint() {
    local i="$1"
    if $enforce_min ; then ((i<min)) && { echo "$i" ; return 2 ; }  # error for min exceeded 
    elif [[ -z "$min" ]] || ((i<min)) then min="$i"
    fi
    if $enforce_max ; then ((i>max)) && { echo "$i" ; return 3 ; } # error for max exceeded 
    elif [[ -z "$max" ]] || ((i>max)) then max="$i"
    fi
    return 0
  }

  for arg in "$@" ; do
    if ! [[ "$arg" =~ '^(-)?[0-9]+$' ]] ; then 
      if   [[ "$arg" =~ '^--min=(-)?[0-9]+$' ]] ; then min="${arg#*=}" ; enforce_min=true
      elif  [[ "$arg" =~ '^--max=(-)?[0-9]+$' ]] ; then  max="${arg#*=}" ; enforce_max=true
      elif gdm_isArray "$arg" ; then
        eval 'local _ints=("${'$arg'[@]}")' 
        for i in "${_ints[@]}" ; do
          if ! [[ "$i" =~ '^(-)?[0-9]+$' ]] ; then echo "\"$i\"" ; return 1 ; fi # non-integer found
          $0.checkint "$i" || return $?
        done
      else echo "\"$arg\"" ; return 1 # 1 non-integer found
      fi
    else $0.checkint "$arg" || return $?
    fi
  done
  echo "min=$min ; max=$max ;"
  return 0
}

gdm_arrayAsSet() { 
  # Assigns a set (array without duplicates) from an array passed by value either by directly  
  # mutating the array (the default) or by writing to another array passed by value to --to=another
  # Usage:
  #    gdm_arrayAsSet arrayname [--to=another]
  # AS AN ASIDE:         foo=(3 1 -4 1 20 3 5)
  #    echo "${(Oa)foo[@]}" # 5 3 20 1 -4 1 3  reverse order of elements (indicies are reverse) 
  #    echo "${(o)foo[@]}"  # -4 1 1 20 3 3 5  sorts by value
  #   NOTE THAT SORTS ARE LEXICOGRAPHICAL:
  #    echo "${(O)foo[@]}"  # 5 3 3 20 1 1 -4  reverse sorts by value
  #    echo "${(u)foo[@]}"  # 3 1 -4 20 5      keeps only first occurrences of unique values
  #    echo "${(ou)foo[@]}" # -4 1 20 3 5      ordered set: (ordered by value with only unique values)
  #    echo "${(Ou)foo[@]}" # 5 3 20 1 -4      reverse ordered set: (reverse ordered by value with only unique values)
  #   Note: "${(oa)foo[@]}" or "${(a)foo[@]}"   do nothing
  #   ALSO: these can be applied to an indirect reference to an array (foo stores an array names) by adding P inside the parenthesis
  #  FOR A BETTER NUMERIC SORT: foo=(3 1 -4 1 20 3 "" 5)
  #   foo_sorted=( $(printf "%s\n" "${foo[@]}" | sort -n) )   # but this looses the empty element (with "$()" quotes, only one bit element is made!)
  
  local arrayname="$1" ; shift
  local as_set_name="$arrayname"
  if [[ "$1" =~ '^--to=.+' ]] ; then as_set_name="${1#*=}" ; shift
    if ! gdm_isArrayOrEmpty $as_set_name  ; then echo "ERROR: $0 got erroneous 2nd arg: '$as_set_name' exists as a non-empty, non-array data type" >&2 ; return 1 ; fi
  fi
  eval $as_set_name'=("${(u)'$arrayname'[@]}")' 
  
}