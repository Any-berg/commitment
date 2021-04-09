staged_files="$1"

[ -z "$staged_files" ] ||
[[ $staged_files =~ [[:space:]]pre-commit.sh([[:space:]]|$) ]] ||
[[ $staged_files =~ [[:space:]]test.sh([[:space:]]|$) ]] || exit 0

basedir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cat_A="git diff --cached --name-status"
cat_B="stat $([ "$(uname -s)" = "Darwin" ] && echo "-f %A" || echo "-c %a") D"
cat_C="cat D"

stage () {
  cd "$basedir"
  rm -fR tmp
  mkdir tmp
  cd tmp
  git init > /dev/null
  echo $cat_A > A
  echo $cat_B > B
  echo $cat_C > C
  chmod u+x A B C
  git add A B C
  git commit -m "initial commit" > /dev/null

  file=$([[ "$1" =~ ^"R" ]] && echo "E" || echo "D")
  printf "%b"\
      "$([ "$1" != "M" ] && echo "$3" || [ ! -z "$3" ] || echo "X")" > "$file"
  [ -z "$2" ] || chmod "$2" "$file"
  git add "$file"
  [[ "$1" =~ ^"A"$ ]] || git commit -m "second commit" > /dev/null
  if [[ "$1" =~ ^"M"$ ]]; then
    printf "%b" "$3" > D
    git add D
  elif [[ "$1" =~ ^"D"$ ]]; then
    git rm D > /dev/null
  elif [[ "$1" =~ ^"R" ]]; then
    git mv E D
  fi

  printf "%b" "$5" > D
  if [ $# -le 3 ]; then
    rm D
  else
    if [ ! -z "$4" ]; then
      chmod "$4" D
    elif [ ! -z ${4+x} ]; then
      rm D
    fi
    [ ! -z "$6" ] && touch "$6"
  fi
  
  #git status
  #ls -l
  #return
}

pass () {
  stage "$1" "$2" "$3" "$4" "$5" "$6" 

  map_A=$($cat_A)
  map_B=$($cat_B 2> /dev/null)
  map_C=$($cat_C 2> /dev/null)

  for file in A B C; do
    j=$(($(printf '%d' "'$file")-64))
    git config hooks.precommit "./$file"

    before="map_$file"
    before=${!before}

    during=$(../pre-commit.sh) || {
      [ "$1" == "D" ] && [ $# -gt 3 ] && break
      [[ "$1" =~ ^"R" ]] && [ "$6" == "E" ] && break
      echo "DURING:$@ $during"
      exit 1
    }
    [ "$1" == "D" ] && break

    [[ "$during" =~ ^"${!j}" ]] || { printf "ERROR1:\n${!j}\n$during\n"; exit 1; }

    [ $# -le 3 ] && {
      [ -f D ] && { echo "WARN: $@ (deleted file returned)"; break; }
      #[ -f F ] && echo "$@: deleted D"
      continue
    }
    
    after="cat_$file"
    after=$(${!after})

    [[ "$before" == "$after" ]] || {
      echo "ERROR2: $@"
      printf "$before\n$after\n"
      exit 1
    }
  done
}

data=(
  A\ 644\ fu\ 755\ bar		# stage added file and then modify it
  A\ 755\ fu			# stage added file and then delete it
  M\ 755\ fu\ 644\ bar		# stage modified file and then modify it
  M\ 644\ X			# stage modified file and then delete it
  R\ 644\ fu\ 755\ bar		# stage renamed file and then modify it
  R\ 755\ fu			# stage renamed file and then delete it
  D\ 644\ fu			# stage deleted file (skip B & C tests)

  # hook must block stash since it "cannot restore untracked files from stash"
  R\ 644\ fu\ 755\ bar\ E       # stage renamed file, modify it & recreate old
  R\ 755\ fu\ \"\"\ \"\"\ E	# stage renamed file, delete it & recreate old
  D\ 755\ fu\ 644\ bar		# stage deleted file & recreate it 

# M\ 755 M			# these are just interesting variants
)

for ((i = 0; i < ${#data[@]}; i++)); do
  eval pass ${data[$i]} || exit 1
  #break
done

exit 0

# https://askubuntu.com/questions/152001/how-can-i-get-octal-file-permissions-from-command-line
# https://stackoverflow.com/questions/3601515/how-to-check-if-a-variable-is-set-in-bash
# https://stackoverflow.com/questions/3466166/how-to-check-if-running-in-cygwin-mac-or-linux
# https://stackoverflow.com/questions/8880603/loop-through-an-array-of-strings-in-bash
# https://superuser.com/questions/597620/how-to-convert-ascii-character-to-integer-in-bash/597624
# https://unix.stackexchange.com/questions/93029/how-can-i-add-subtract-etc-two-numbers-with-bash
# https://stackoverflow.com/questions/40978921/how-to-add-chmod-permissions-to-file-in-git
