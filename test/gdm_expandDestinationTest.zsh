export GDM_REPO_ROOT="${GDM_REPO_ROOT:=${0:a:h:h}}"

. $GDM_REPO_ROOT/run compile as=test ; . $GDM --source 
export GDM_PROJ_ROOT=$PWD

runTest() {
  
  local _ret=0
  local expr_val exper_arr exper_item
  for arg in "$@" ; do
    
    if [[ "$arg" =~ '--(dis)?allow=' ]] ; then  # SET GDM_EXPERIMENTAL:
      eval "exper_arr=( ${arg#*=} )"
      if [[ "$arg" == '--dis'* ]] ; then 
        GDM_EXPERIMENTAL=(any_GDM_REQUIRED_path allow_destin_relto_HOME allow_destin_relto_SYSTEM_ROOT allow_destin_relto_GDM_PROJ_ROOT allow_nonflat_GDM_REQUIRED)
        for exper_item in "${exper_arr[@]}" ; do GDM_EXPERIMENTAL[$GDM_EXPERIMENTAL[(ie)$exper_item]]=() ; done
      else GDM_EXPERIMENTAL=() ; for exper_item in "${exper_arr[@]}" ; do GDM_EXPERIMENTAL+=($exper_item) ; done
      fi
      
    else # RUN TEST:
      echo "% echo GDM_EXPERIMENTAL=($GDM_EXPERIMENTAL)\n% gdm_expandDestination "$arg""
      gdm_expandDestination "$arg" ; _ret=$?
    fi
  done
  return $_ret
}




runTest "$@"




