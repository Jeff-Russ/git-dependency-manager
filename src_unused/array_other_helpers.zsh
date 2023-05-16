source "${0:a:h:h}/src/8-gdm-helpers.zsh"


# arrElems() { #TODO: This is just a temp function for quick visual testing for empty elements. delete later.
#   local _arrname="$1"
#   eval 'local _the_array=("${'$_arrname'[@]}")' 
#   for idx in {1..$#_the_array} ; do echo $_arrname"[$idx]=$(gdm_quote "$_the_array[$idx]")" ; done
# }


gdm_arrayIsASet() {
  # accepts an array name and returns number of duplicates, so if array=(a a b b b c)
  # gdm_arrayIsASet array    # would return 3 (the 1 extra a + 2 extra b)
  eval 'local actualsize=$#'$1
  eval 'local setsize=${#${(u)'$1'}}'
  return $((actualsize-setsize))
}

gdm_allMatchingIdx() {
  # Examples ( all using ar=(a xo xy xo a) )
  #   gdm_allMatchingIdx 'ar(ie)xo'  # echoes (in order): 2 4
  #   gdm_allMatchingIdx 'ar(Ie)xo'  # echoes (reversed): 4 2
  #   gdm_allMatchingIdx 'ar(ie)x'   # returns 1 (same for (Ie))
  #   gdm_allMatchingIdx 'ar(i)x*'   # echoes (in order): 2 3 4
  #   gdm_allMatchingIdx 'ar(I)x*'   # echoes (reversed): 4 3 2
  # Optionally, pass a variable (by name) as 2nd arg which result will be written to (as an array):
  #  gdm_allMatchingIdx 'ar(i)x*' all_matching_i # no output
  #  echo $all_matching_i # 2 3 4

  local array_name="${1%%'('*}"     # before first )
  local option="${${1#*'('}%%')'*}" # between ( and )
  local patt="${1#*')'}"            # after first )
  local reversed=false ; [[ "$option[1]" == I ]] && reversed=true ;
  local exact=false ; [[ "${option[2]:l}" == e ]] && exact=true ;
  local to_arrayname=""

  if ! [[ -z "$2" ]] ; then 
    to_arrayname="${2#*=}" 
    if ! gdm_isArrayOrEmpty $to_arrayname  ; then echo "ERROR: $0 got erroneous 2nd arg: '$to_arrayname' exists as a non-empty, non-array data type" >&2 ; return 1 ; fi
  fi
  
  eval 'local subarr_cpy=( "${'$array_name'[@]}" )' || return 2 # $1 is array name and $2 is value to search for
  local i_matches=() 
  local left_i   # The left matching index on each subarray tested
  local real_i=0 # Initalize to 0 because we will real_i+=left_i offsets for each subarray to get real index

  while (($#subarr_cpy))  ; do
    # Get left-most matching index or... 
    $exact && left_i=$subarr_cpy[(ie)$patt] || left_i=$subarr_cpy[(i)$patt]
    ((left_i>$#subarr_cpy)) && break  # $#subarr_cpy+1 if none found so break and return.
    i_matches+=($((real_i+=$left_i))) # Match found so ccumlate left_i (offset) to real_i and append to matches
    (($#subarr_cpy==1)) && break      # If we only searched one element, break and return.
    # If not, gets slice of subarr_cpy AFTER $left_i:
    subarr_cpy[1,$left_i]=()  
  done

  $reversed && i_matches=( "${(Oa)i_matches[@]}" ) ;
  [[ -z "$to_arrayname" ]] && echo "$i_matches" || eval $to_arrayname'=("${i_matches[@]}")' ;
  (($#i_matches==0)) && return 1 || return 0 ;
}

gdm_arrayToInts() { 
  # USAGE:  gdm_arrayToInts <array_name> [--sort|--reverse] [--unique] [<output_array_name>]
  #     Note that the flag can be in any position but <array_name> must come before any <output_array_name>
  # gdm_arrayToInts converts each element of an array (passed as the array's name) to an integer (04 becomes 4,
  #       -03 becomes -2, floats are truncated and NON NUMBERS BECOME 0) either by directly mutating the array
  #       (the default) or by writing to another array passed by name. Elements can also be sorted and made unique
  # FLAGS
  #     --sort    # sorts array or output array in numeric order
  #     --reverse # sorts array or output array in reverse numeric order 
  #     --unique  # removes redundant (subsequent occurrences if not also sorted) elements in array or output array
  # EXAMPLES     all start with:        nums=(10 1 '' -03 'one' +100.0 05.4)
  #   gdm_arrayToInts nums                 # now, nums=( 10 1 0 -3 0 100 5 )
  #   gdm_arrayToInts nums --sort          # now, nums=( -3 0 0 1 5 10 100 )
  #   gdm_arrayToInts nums --sort --unique # now, nums=( -3 0 1 5 10 100 )
  #   gdm_arrayToInts nums --reverse       # now, nums=( 100 10 5 1 0 0 -3 )
  #   gdm_arrayToInts nums --sort sorted   # sorted=( -3 0 0 1 5 10 100 ) and nums is untouched

  local _arr_name=''
  local _arr_out_name=''
  local _sort_tag=''
  local _as_unique=false
  
  for arg in $@ ; do
    if [[ "$arg" =~ '^--reverse(d)?(-sort|-sorted)?$' ]] ; then _sort_tag='-rn'
    elif [[ "$arg" =~ '^--sort(ed)?$' ]] ; then _sort_tag='-n'
    elif [[ "$arg" == --unique ]] ; then _as_unique=true
    else [[ -z $_arr_name ]] && _arr_name=$arg || _arr_out_name=$arg ;
    fi
  done

  eval 'local _arr_size=$#'$_arr_name
  local _arr_cpy=()
  for i in {1..$_arr_size} ; do 
    _arr_cpy+=( $(printf "%.0f" ${(P)${_arr_name}[$i]}) ) # https://unix.stackexchange.com/a/89748
  done

  ! [[ -z $_sort_tag ]] && _arr_cpy=( $(printf "%s\n" "${_arr_cpy[@]}" | sort $_sort_tag) ) ;
  
  [[ -z "$_arr_out_name" ]] && _arr_out_name="$_arr_name" ;
  $_as_unique && eval $_arr_out_name'=("${(u)_arr_cpy[@]}")' ||  eval $_arr_out_name'=("${_arr_cpy[@]}")'
  # eval $_arr_out_name'=("${_arr_cpy[@]}")'
}


gdm_arrayInsIdx() {
  # Inserts one or more contiguous element to an array passed by value either by directly  
  # mutating the array (the default) or by writing to another array passed by value to --to=another
  #
  #    gdm_arrayRmIdx arr_name [--to=another] <insert_idx|neg_insert_idx> <insert_scalar_name|insert_val|insert_arr_name> 
  #
  # Elements after the insert index will be incresed in index and elements before will stay at their positions. 
  # NOTE: if the insert is an array (name) and the array is empty, an error will occur.
  # NOTE: this function will error if attempting to insert at an index beyond the last index + 1, thus
  # avoiding skipped indices. 
  # IMPORTANT: Inserting to the index -1 or $#arr (both  the same) is the last place one can insert but this 
  #  IS NOT APPENDING! This will insert at what WAS THE LAST INDEX, pushing the last element up in index.
  
  if ! gdm_isArray "$1" ; then echo "ERROR: $0 got erroneous 1st arg: '$1' is not an array" >&2 ; return 1  ; fi
  local arrayname="$1" ; shift

  local to_arrayname="$arrayname"
  if [[ "$1" =~ '^--to=.+' ]] ; then to_arrayname="${1#*=}" ; shift
    if ! gdm_isArrayOrEmpty $to_arrayname  ; then echo "ERROR: $0 got erroneous 2nd arg: '$to_arrayname' exists as a non-empty, non-array data type" >&2 ; return 1 ; fi
  fi

  if (($#<2)) ; then echo "ERROR: $0 Usage:\n  $0 arr_name [--to=another] <insert_idx|neg_insert_idx> <elem_val|ins_arr_name>" >&2 ; return 1 ; fi

  if ! [[ "$1" =~ '^(-)?[0-9]+$' ]] ; then echo "ERROR: $0 got a non-numeric index arg:'$1'" >&2 ; return 1 ; fi

  local i="$1" ; shift
  local nth ; eval 'nth=$#'$arrayname

  if ((i==0)) ; then echo "ERROR: $0 received a zero index" >&2 ; return 1
  elif ((i<0)) ; then i=$((nth+i+1)) 
    if ((i<1)) ; then echo "ERROR: $0 negative start is out of bounds" >&2 ; return 1 ; fi
  elif ((i>nth+1)) ; then echo "ERROR: $0 positive start is out of bounds" >&2 ; return 1 
  fi


  local data_type
  if ! data_type="$(gdm_datatype $1)" ; then
    echo "ERROR: $0 cannot insert '$1' due to it not being recognized as a data type" >&2 ; return 1 
  fi

  if [[ "$data_type" == scalar ]] ; then
    echo "$1 is a scalar name"
    eval $to_arrayname'=("${(@)'$arrayname'[1',$i'-1]}" "'${(P)1}'" "${(@)'$arrayname'['$i','$nth']}")'
  elif [[ "$data_type" == array ]] ; then
    local size ;  eval "size=\$#$1" 
    if ! (($size)) ; then echo "ERROR: $0 cannot insert '$1' due to it being an empty array" >&2 ; return 1  ; fi
    eval $to_arrayname'=("${(@)'$arrayname'[1',$i'-1]}" "'"${(P)1[@]}"'" "${(@)'$arrayname'['$i','$nth']}")'
  else 
    echo "$1 a scalar value"
    eval $to_arrayname'=("${(@)'$arrayname'[1',$i'-1]}" "'$1'" "${(@)'$arrayname'['$i','$nth']}")'
  fi
}



gdm_arrayDiff() {
  # USAGE:     arrayDiff array1 array2 # returns all elements in array1 not in array2
  # also try:  missing_idx=( $(arrayDiff "$(seq $#array)" indices) )  # to get all indices in array not in indices
  echo ${(P)1[@]} ${(P)2[@]} | tr ' ' '\n' | sort | uniq -u
}

gdm_arrayRmIndices() {
  # USAGE:    gdm_arrayRmIdx source_array [--saved-to=<arrayname>] [--removed-to=<arrayname>] indices_to_extract|int...
  # DESCRIPTION: gdm_arrayRmIndices extracts any number of elements by index from an array by either directly modififying
  #              the source_array or to another arrayname if --saved-to=<arrayname> is provided. The removed elements are output 
  #              line by line, or assigned to another array if --removed-to=<arrayname> is provided.
  #   source_array              passed by name either by directly mutating the source_array (the default) OR
  #   --saved-to=<arrayname>    (option) by assigning to another array, passed by name, all non-removed elements
  #   --removed-to=<arrayname>  (option) provide an arrayname to which extracted elements are APPENDED
  #   indices_to_extract        an array passed by name or as all subsquent arguments where each value is an index to remove
  #                             Note that all invalid value will have no effect.

  # Get source array and make sure it's an array
  if ! gdm_isArray "$1" ; then echo "ERROR in $0: got source array '$1' is not an array" >&2 ; return 1  ; fi
  local src_arr_name="$1" ; shift
  eval 'local _src_size=$#'$src_arr_name

  local saved_to_name="$src_arr_name" # as array name
  local echo_removed=true    # false if we get an array name to append --removed-to
  local removed_elements_name="" # array name to append --removed-to

  # Parse options:
  while [[ "$1" =~ '^--(saved-to=.+|removed-to=.+)$' ]]  ; do
    if [[ "$1" =~ '^--saved-to=.+' ]] ; then saved_to_name="${1#*=}" 
      if ! gdm_isArrayOrEmpty $saved_to_name  ; then echo "ERROR in $0 --saved-to value: '$saved_to_name' exists as a non-array data typ a non-empty, non-array data type" >&2 ; return 1 ; fi
      eval $saved_to_name'=( "${'$src_arr_name'[@]}" )'
    else removed_elements_name="${1#*=}" ; echo_removed=false
      if ! gdm_isArrayOrEmpty $removed_elements_name  ; then echo "ERROR in $0 --removed-to value: '$removed_elements_name' exists as a non-array data typ a non-empty, non-array data type" >&2 ; return 1 ; fi
    fi
    shift
  done

  # echo "saved_to_name=$saved_to_name" >&2 #TEST
  # echo "removed_elements_name=$removed_elements_name" >&2 #TEST

  # Get ordering array, make sure it's an array and do basic validation making sure it has only valid integers.
  local _idx_to_rm 
  local show_idx_to_rm="" # for error display
  if (($#==1)) ; then
    if ! gdm_isArray "$1" ; then echo "ERROR in $0: indices_to_extract array '$1' is not an array" >&2 ; return 2  ; fi
    eval '_idx_to_rm=( "${'$1'[@]}" )'
    show_idx_to_rm=" '$1'"
  else
    _idx_to_rm=("$@") 
  fi

  gdm_arrayToInts _idx_to_rm  --reverse --unique # RE-ASSIGN AS REVERSE ORDERED SET
  # Why? because if we remove in order, each time remove, all subsequent indicies  are off by one...
  # so we do it in reverse. We didn't want duplicates because they are invalid once removed.

  local _out_of_bounds_val=""
  if (($_idx_to_rm[-1]>_src_size)) ; then _out_of_bounds_val=$_idx_to_rm[-1]
  elif (($_idx_to_rm[1]<1)) then _out_of_bounds_val=$_idx_to_rm[1]
  fi
  if ! [[ -z $_out_of_bounds_val ]] ; then
    echo "ERROR in $0 index for removal ($_out_of_bounds_val) is out of bounds " >&2 ; return 1 
  fi

  # local _kept_idx=( $(arrayDiff "$(seq $_src_size)" _idx_to_rm) ) #TEST
  # printArray _idx_to_rm #TEST
  # printArray _kept_idx #TEST

  # local _kept_elements=()
  local _removed_element=()

  for i in {$_src_size..1} ; do
    if (($_idx_to_rm[(Ie)$i])) ; then
      if ! [[ -z  "$removed_elements_name" ]] ; then
        # echo $removed_elements_name'=( "${'$removed_elements_name'[@]}"' \"${(P)${src_arr_name}[$i]}\" ')' ;
        eval $removed_elements_name'=( "${'$removed_elements_name'[@]}"' \"${(P)${src_arr_name}[$i]}\" ')' ;
      fi
      eval $saved_to_name'['$i']=()'
    fi
  done

}

gdm_arrayRmIndicesTest() {
  arrayAsHash() {
    local arr_name="$1" 
    local hash_name="$2" ; [[ -z $hash_name ]] && hash_name=$arr_name
    eval 'local arr_size=$#'$arr_name
    if ! ((arr_size)) then
      echo "$arr_name=()"
      return 0 ;
    fi
    local hash_body=" "
    for i in {1..$arr_size} ; do
      hash_body+="[$i]=\"${(P)${arr_name}[$i]}\" " #IMPORTANT <<<<-THIS: ${(P)${arr_name}[$i]} is how you access elements on an indirectly referenced array 
      #IMPORTANT and by the way... THIS is now how to you get the size>>>> ${#${(P)arr_name}}
    done
    echo "declare -A $hash_name=($hash_body)"
  }
  printArray() {
    local arr_name="$1" 
    eval 'local arr_size=$#'$arr_name
    if ! ((arr_size)) then echo "$arr_name=()" ; return 0 ; fi
    local el_val
    print -n "$arr_name=( "
    for i in {1..$arr_size} ; do
      el_val="${(P)${arr_name}[$i]}"
      [[ -z "$el_val" ]] || [[ "$el_val"  == *' '* ]] && el_val="\"$el_val\"" ;
      print -n "$el_val "
    done
    print ")"
  }
  reset() {
    src_arr=( "$@" )
    keepers=()
    loosers=()
  }
  show() {
    printArray src_arr
    printArray keepers
    printArray loosers
  }

  local original_elements=()
  local extracted_indices=()
  local reading_indices=false

  if (($#)) ; then
    for arg in "$@" ; do
      if [[ "$arg" == --indices ]] ; then reading_indices=true
      elif $reading_indices ; then extracted_indices+=("$arg")
      else original_elements+=("$arg")
      fi
    done
  else
    original_elements=(one "two (skip three)" "" "four (skip five)" "")
    extracted_indices=(1 4)
  fi



  echo "BEFORE:"
  reset "${original_elements[@]}" 
  show

  echo "gdm_arrayRmIndices src_arr --saved-to=keepers --removed-to=loosers extracted_indices # $(printArray extracted_indices)"
  gdm_arrayRmIndices src_arr --saved-to=keepers --removed-to=loosers extracted_indices
  echo "AFTER:"
  show

  reset "${original_elements[@]}" 

}
# gdm_arrayRmIndicesTest $@



gdm_arrayRmIndices() {
  # USAGE:    gdm_arrayRmIdx source_array [--saved-to=<arrayname>] [--removed-to=<arrayname>] indices_to_extract|int...
  # DESCRIPTION: gdm_arrayRmIndices extracts any number of elements by index from an array by either directly modififying
  #              the source_array or to another arrayname if --saved-to=<arrayname> is provided. The removed elements are output 
  #              line by line, or assigned to another array if --removed-to=<arrayname> is provided.
  #   source_array              passed by name either by directly mutating the source_array (the default) OR
  #   --saved-to=<arrayname>    (option) by assigning to another array, passed by name, all non-removed elements
  #   --removed-to=<arrayname>  (option) provide an arrayname to which extracted elements are APPENDED
  #   indices_to_extract        an array passed by name or as all subsquent arguments where each value is an index to remove
  #                             Note that all invalid value will have no effect.

  # Get source array and make sure it's an array
  if ! gdm_isArray "$1" ; then echo "ERROR in $0: got source array '$1' is not an array" >&2 ; return 1  ; fi
  local src_arr_name="$1" ; shift
  eval 'local _src_size=$#'$src_arr_name

  local saved_to_name="$src_arr_name" # as array name
  local echo_removed=true    # false if we get an array name to append --removed-to
  local removed_elements_name="" # array name to append --removed-to

  # Parse options:
  while [[ "$1" =~ '^--(saved-to=.+|removed-to=.+)$' ]]  ; do
    if [[ "$1" =~ '^--saved-to=.+' ]] ; then saved_to_name="${1#*=}" 
      if ! gdm_isArrayOrEmpty $saved_to_name  ; then echo "ERROR in $0 --saved-to value: '$saved_to_name' exists as a non-array data typ a non-empty, non-array data type" >&2 ; return 1 ; fi
      eval $saved_to_name'=( "${'$src_arr_name'[@]}" )'
    else removed_elements_name="${1#*=}" ; echo_removed=false
      if ! gdm_isArrayOrEmpty $removed_elements_name  ; then echo "ERROR in $0 --removed-to value: '$removed_elements_name' exists as a non-array data typ a non-empty, non-array data type" >&2 ; return 1 ; fi
    fi
    shift
  done

  # echo "saved_to_name=$saved_to_name" >&2 #TEST
  # echo "removed_elements_name=$removed_elements_name" >&2 #TEST

  # Get ordering array, make sure it's an array and do basic validation making sure it has only valid integers.
  local _idx_to_rm 
  local show_idx_to_rm="" # for error display
  if (($#==1)) ; then
    if ! gdm_isArray "$1" ; then echo "ERROR in $0: indices_to_extract array '$1' is not an array" >&2 ; return 2  ; fi
    eval '_idx_to_rm=( "${'$1'[@]}" )'
    show_idx_to_rm=" '$1'"
  else
    _idx_to_rm=("$@") 
  fi

  gdm_arrayToInts _idx_to_rm  --reverse --unique # RE-ASSIGN AS REVERSE ORDERED SET
  # Why? because if we remove in order, each time remove, all subsequent indicies  are off by one...
  # so we do it in reverse. We didn't want duplicates because they are invalid once removed.

  local _out_of_bounds_val=""
  if (($_idx_to_rm[-1]>_src_size)) ; then _out_of_bounds_val=$_idx_to_rm[-1]
  elif (($_idx_to_rm[1]<1)) then _out_of_bounds_val=$_idx_to_rm[1]
  fi
  if ! [[ -z $_out_of_bounds_val ]] ; then
    echo "ERROR in $0 index for removal ($_out_of_bounds_val) is out of bounds " >&2 ; return 1 
  fi

  # local _kept_idx=( $(arrayDiff "$(seq $_src_size)" _idx_to_rm) ) #TEST
  # printArray _idx_to_rm #TEST
  # printArray _kept_idx #TEST

  # local _kept_elements=()
  local _removed_element=()

  for i in {$_src_size..1} ; do
    if (($_idx_to_rm[(Ie)$i])) ; then
      if ! [[ -z  "$removed_elements_name" ]] ; then
        # echo $removed_elements_name'=( "${'$removed_elements_name'[@]}"' \"${(P)${src_arr_name}[$i]}\" ')' ;
        eval $removed_elements_name'=( "${'$removed_elements_name'[@]}"' \"${(P)${src_arr_name}[$i]}\" ')' ;
      fi
      eval $saved_to_name'['$i']=()'
    fi
  done

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


