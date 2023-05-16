
gdm_arrayReorderIdx() {
  # USAGE:    gdm_arrayRmIdx input_array [--to=output_array] [--allow-empty] [all|any-to-one|any] ordering_array|int...
  # DESCRIPTION: gdm_arrayReorderIdx reorders elements of 
  #   input_array passed by name either by directly mutating the input_array (the default) OR
  #   --to=*         (option) by writing to output_array array passed by name to --to=output_array
  #   --allow-empty (option) allows you to insert empty elements by placing out-of-range indices in ordering_array
  #   enforcing one of the following restriction (be aware that out-of-bounds indices with --allow-empty don't count toward duplicates):
  #      --any-to-any (default) ALLLOWS  the final array to omit any input_array element,     ALLOWING   duplicates OR
  #      --any-to-one           ALLLOWS  the final array to omit any input_array element,     PREVENTING duplicates OR
  #      --all-to-any           REQUIRES the final array to contain all input_array elements, ALLOWING   duplicates OR
  #      --all-to-one           REQUIRES the final array to contain all input_array elements, PREVENTING duplicates OR
  #   ordering_array, an array passed by name or as all subsquent arguments, defines new sequence (ordering_array indices 
  #     are the final array indices) of indices (ordering_array values are the original indices in input_array)
  # EXAMPLES: (each line starts with ar being equal to ar=(one two three four five) )
  #     gdm_arrayReorderIdx ar --to=to 5 4 3 3 1 # to=(five four three three one) and ar is untouched
  #     order=( 5 4 3 3 1 "")
  #     gdm_arrayReorderIdx ar ${order[1,-2]} # ar=(five four three three one) and ar is untouched
  #     all_w_dup=( 1 3 5 4 4 2 ) ; # fine with any-to-any or all-to-any 
  #     gdm_arrayReorderIdx ar any-to-one all_w_dup # ERROR in gdm_arrayReorderIdx with mode=any-to-one: ordering_array 'all_w_dup' has 1 duplicate indices(s)
  #     # same as above with all-to-one
  #     gdm_arrayReorderIdx ar all-to-one 3 2 # ERROR in gdm_arrayReorderIdx with mode=all-to-one: ordering array lacks 3 indices(s)
  #     # same as above with all-to-any
  # REQUIRES: gdm_arrayToInts gdm_arraySortNum and, for now gdm_typeCheck


  # Get source and make sure it's a non-empty array or scalar:
  local a_name_in="$1" ; shift
  ! gdm_typeCheck $a_name_in array scalar && { echo "ERROR in $0: input array '$a_name_in' not an array or scalar" >&2 ; return 1 ; }
  ((${#${(P)a_name_in}}==0)) && { echo "ERROR in $0: input '$a_name_in' is empty" >&2 ; return 2 ; }
  local a_name_out="$a_name_in"

  # Parse options:
  local mode=any-to-any ; 
  local allow_empty=false
  while [[ "$1" =~ '^--(allow-empty|to=.+)$' ]] || [[ "$1" =~ '^--(all|any)-to-(one|1|any)$' ]] ; do
    if [[ "$1" == '--allow-empty' ]] ; then allow_empty=true
    elif [[ "$1" =~ '^--to=.+' ]] ; then a_name_out="${1#*=}" 
    elif [[ "$1" =~ '^--(all|any)-to-(one|1|any)$' ]] ; then mode="${1#*--}" ; [[ $mode[-1] == 1 ]] && mode=$mode[1,-2]one ;
    else echo "ERROR in $0: invalid flag: '$1'" >&2 ; return 3 ;
    fi
    shift
  done 

  # Get ordering array and convert it to ints so the format is sortable
  local _order_arr 
  local show_order_arr="" # for error display
  if (($#==1)) ; then # First, make sure ordering array is a non-empty array
    ! gdm_typeCheck $1 array && { echo "ERROR in $0: ordering array '$1' is not an array" >&2 ; return 4 ;  }
    eval '_order_arr=("${'$1'[@]}")' ; show_order_arr=" '$1'" 
    (($#_order_arr==0)) && { echo "ERROR in $0: ordering array '$1' is empty" >&2 ; return 5 ; } 
  else  _order_arr=("$@")  ;
  fi  
  gdm_arrayToInts _order_arr


  # To some advanced validate of the _order_arr to make sure it doesn't violate any option:
  if ! $allow_empty || [[ $mode != any-to-any ]] ; then
    local _order_sort ; gdm_arraySortNum _order_arr _order_sort # create sorted version of _order_arr

    local _in_bounds_indices=( "${_order_sort[@]}" ) # _order_sort with under and over bounds indices removed:
    while (($_in_bounds_indices[1]<1)) ; do _in_bounds_indices[1]=() ; done
    while (($_in_bounds_indices[-1]>${#${(P)a_name_in}})) ; do _in_bounds_indices[-1]=() ; done

    if ! $allow_empty && (($#_in_bounds_indices!=$#_order_sort)) ; then 
      echo "ERROR in $0: ordering_array$show_order_arr out of bounds index(es)" >&2 ; return 6 ;
    fi

    if [[ $mode != any-to-any ]] ; then 
      local _in_bounds_unique=( "${(u)_in_bounds_indices[@]}" )
      if [[ $mode == *'-to-one' ]] ; then 
        local dups=$(($#_in_bounds_indices-$#_in_bounds_unique))
        ((dups)) && { echo "ERROR in $0 with mode=$mode: ordering_array$show_order_arr has $dups duplicate indices(s)" >&2 ; return 7 ; }
      fi
      if [[ $mode == 'all-to-'* ]] ; then
        local missings=$((${#${(P)a_name_in}}-$#_in_bounds_unique))
        ((missings)) && { echo "ERROR in $0 with mode=$mode: ordering array$show_order_arr lacks $missings indices(s)" >&2 ; return 8 ; }
      fi
    fi
    
  fi

  local _temp_st=""
  for old_index in "${_order_arr[@]}" ; do
    _temp_st+='"${'$a_name_in'['$old_index']}" '
  done
  eval $a_name_out'=( '"$_temp_st"' )'
}




gdm_typeCheck() {
  # Usage cases:
  #  1) Test if a variable is iterable:
  #     gdm_typeCheck a_string scalar array    # returns 0 because a string is a scalar 
  #     gdm_typeCheck assoc_array scalar array # returns 1 because not a scalar or an array
  #  1) Test if a variable is unset:
  #      gdm_typeCheck unset_var '^$'           # returns 0 unset_var has no type, matching ^$'
  #      gdm_typeCheck an_array '^$' array      # returns 0 an_array is an array
  local varname="$1" ; local typetest="" ; local arg
  for arg in $@ ; do typetest+="$arg|" ; done
  [[ "$(eval "print -rl -- \${(t)$1}" 2>/dev/null)" =~ '('"${typetest[1,-2]}"')' ]] && return 0 || return 1 ;
}

gdm_arrayToInts() {
  local _arr_in="$1" ; [[ -z "$_arr_in" ]] && return 1 ;
  local _arr_out="$2" ; [[ -z "$_arr_out" ]] && _arr_out="$_arr_in"
  local i 
  for i in {1..${#${(P)1}}} ; do  eval $_arr_out'['$i']='$(printf "%.0f" ${(P)${_arr_in}[$i]}) ; done
}

gdm_arraySortNum() {
  local a_name_in a_name_out a ; local _sort='-n'
  for a in $@ ; do [[ "$a" =~ '^(-r|--reversed?)$' ]] && _sort='-rn' || { [[ -z $a_name_in ]] && a_name_in=$a || a_name_out=$a ; } ; done
  [[ -z $a_name_in ]] && return 1 ;
  [[ -z $a_name_out ]] && a_name_out=$a_name_in ;
  eval $a_name_out'=( $(printf "%s\n" "${'$a_name_in'[@]}" | sort '$_sort') )'   # 0-1 WORKS!
}


gdm_arrayFlip() {
  local a_name_in a_name_out a ; local _sort='-n'
  for a in $@ ; do [[ "$a" =~ '^(-r|--reversed?)$' ]] && _sort='-rn' || { [[ -z $a_name_in ]] && a_name_in=$a || a_name_out=$a ; } ; done
  [[ -z $a_name_in ]] && return 1 ;
  [[ -z $a_name_out ]] && a_name_out=$a_name_in ;
  eval $a_name_out'=( $(printf "%s\n" "${'$a_name_in'[@]}" | sort '$_sort') )'   # 0-1 WORKS!
}

arrayReorderIdxTest() {
  arr=('1,-5' '2,-4' '3,-3' '4,-2' '5,-1')
  ar=(one two three four five) 
  to=()

  make_order_arr() {
    local qual="$1" # contains up to three digits: E for Empty (out of bounds), I for Incomplete, D for Duplicates
    local original_ar_size="$2" ; [[ -z $original_ar_size ]] && original_ar_size=${#${(P)a_name_in}}
    _order_arr=( $(seq $original_ar_size) )
    [[ ${qual:u} == *I* ]] && _order_arr[1]=() ;
    [[ ${qual:u} == *E* ]] && _order_arr=(11 "${_order_arr[@]}" 0 -1 ) ;
    [[ ${qual:u} == *D* ]] && _order_arr=(4 "${_order_arr[@]}" 1) ; 
    print -l $_order_arr
    return 0
  }
  # echo "before: arr=($arr) to=($to)\n" ; 
  # local ret_code
  # gdm_arrayRmIdx "$@" || ret_code=$?
  # if (($ret_code)); then  echo "FAILED BY RETURNING: $ret_code"
  # else echo "after: arr=($arr) to=($to)" ; 
  # fi
  # echo "arr lost $((5-$#arr)) elements."

  show () {
    if [[ "$1" == ar ]] ; then
      print -n "ar=("
      if (($#ar)) ; then echo 
        for i in {1..$#ar} ; do print "  $ar[$i]" ; done
      fi
    else
      print -n "arr=("
      if (($#arr)) ; then echo 
        for i in {1..$#arr} ; do print "  $arr[$i]" ; done
      fi
    fi
    print -n ")\nto=( "
    if (($#to)) ; then echo
      for i in {1..$#to} ; do print "  $to[$i]" ; done
    fi
    print ")"
  }
  reset () {
    ar=(one two three four five) ; arr=('1,-5' '2,-4' '3,-3' '4,-2' '5,-1') ; to=() ;
    }
  showreset() { show "$1" ; echo "resetting..." ;  reset ; show "$1" ;  }

  testAllowInsert() {
    fake_GDM_PROJ_LOCK_ARRAY=(
      "formerly1"
      "formerly2"
      "formerly3"
    )
    desired_result=(
      "formerly3"
      ""
      "formerly2"
      ""
      "formerly1"
    )
    actual_result=
    config_i_to_lock_i=(3 0 2 0 1)
    gdm_arrayReorderIdx fake_GDM_PROJ_LOCK_ARRAY --to=actual_result --allow-empty --all-to-one config_i_to_lock_i || {
      echo "failed with $? " ; return 1
    }
    print "result:"
    for i in {1..$#actual_result} ; do
      echo "$i->$actual_result[$i]"
    done
  }
}






