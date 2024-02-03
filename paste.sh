#!/usr/bin/env bash
# Client for paste.sh - https://paste.sh/client
#
# Install:
#   cd ~/bin
#   curl -O https://raw.github.com/dgl/paste.sh/master/paste.sh
#   chmod +x paste.sh
#
# Usage:
#   Send clipboard:
#     $ paste.sh
#   Send output of command:
#     $ foo 2&>1 | paste.sh
#   File:
#     $ paste.sh some-file
#
#   Public paste (shorter URL, as no encryption, limited to command line client
#   for now):
#     $ paste.sh -p [same usage as above]
#
#   Print paste:
#     $ paste.sh 'https://paste.sh/xxxxx#xxxx'
#     (You need to quote or escape the URL due to the #)
#
#   The command line client by default does not store an identifiable cookie
#   with pastes, you can run "paste.sh -i" to initialise a cookie, which means
#   you can then update pastes:
#
#     paste.sh 'https://paste.sh/xxxxx#xxxx' some-file
#

HOST=https://paste.sh
TMPTMPL=paste.XXXXXXXX


die() {
  echo "${1}" >&2
  exit ${2:-1}
}

# Generate x bytes of randomness, then base64 encode and make URL safe
randbase64() {
  openssl rand -base64 $1 2>/dev/null | tr '+/' '-_'
}

writekey() {
  # The full key includes some extras for more entropy. (OpenSSL adds a salt
  # too, so the ID isn't really needed, but won't hurt).
  echo "${id}${serverkey}${clientkey}${HOST}"
}

encrypt() {
  local cmd arg
  cmd="$1"
  arg="$2"
  id="$3"
  clientkey="$4"

  if [[ -z ${id} ]]; then
    # Generate ID
    id="$(randbase64 6)"
    if [[ $public == 1 ]]; then
      clientkey=
      id="p${id}"
    fi
    # Get serverkey
    # TODO: Retry if the error is the id is already taken
    serverkey=$(curl -fsS "$HOST/new?id=$id")
    # Yes, this is essentially another salt
    [[ -n ${serverkey} ]] || die "Failed getting server salt"
  else
    tmpfile=$(mktemp -t $TMPTMPL)
    trap 'rm -f "${tmpfile}"' EXIT
    curl -fsS -o "${tmpfile}" "${url}.txt" || exit $?
    serverkey=$(head -n1 "${tmpfile}")
  fi

  if [[ $public == 0 ]]; then
    if [[ -z $clientkey ]]; then
      # Generate client key (nothing stopping you changing this, this seemed like
      # a reasonable trade off; 144 bits)
      clientkey="$(randbase64 18)"
    fi
  fi

  file=$(mktemp -t $TMPTMPL)
  trap 'rm -f "${file}"' EXIT
  # The key here is not user controlled, more iterations won't help, but using
  # -iter and therefore PBKBF2 avoids a warning from OpenSSL.
  $cmd "$arg" \
    | 3<<<"$(writekey)" openssl enc -aes-256-cbc -md sha512 -pass fd:3 -iter 1 -base64 > "${file}"

  pasteauth=""
  if [[ -f "$HOME/.config/paste.sh/auth" ]]; then
    pasteauth="$(<$HOME/.config/paste.sh/auth)"
  fi

  # Get rid of the temp file once server supports HTTP/1.1 chunked uploads
  # correctly.
  curl -sS -0 -H "X-Server-Key: ${serverkey}" \
    -H "Content-type: text/vnd.paste.sh-v2" \
    -T "${file}" "$HOST/${id}" -b "$pasteauth" \
    || die "Failed pasting data"

  echo -n "$HOST/${id}"
  if [[ -n $clientkey ]]; then
    echo "#${clientkey}"
  else
    echo
  fi
}

decrypt() {
  local url
  url="$1"
  id="$2"
  clientkey=$3
  tmpfile=$(mktemp -t $TMPTMPL)
  trap 'rm -f "${tmpfile}"' EXIT
  curl -fsS -o "${tmpfile}" "${url}.txt" || exit $?
  serverkey=$(head -n1 "${tmpfile}")
  tail -n +2 "${tmpfile}" | \
    3<<<"$(writekey)" openssl enc -d -aes-256-cbc -md sha512 -pass fd:3 -iter 1 -base64
  exit $?
}


openssl version &>/dev/null || die "Please install OpenSSL" 127
curl --version &>/dev/null || die "Please install curl" 127

fsize() {
  local file="$1"
  stat --version 2>/dev/null | grep -q GNU
  local gnu=$[!$?]

  if [[ $gnu = 1 ]]; then
    stat -c "%s" "$file"
  else
    stat -f "%z" "$file"
  fi
}

# Try to use memory if we can (Linux, probably) and the user hasn't set TMPDIR
if [ -z "$TMPDIR" -a -w /dev/shm ]; then
  export TMPDIR=/dev/shm
fi

# What are we doing?
public=0
main() {
  if [[ $# -gt 0 ]]; then
    if [[ ${1:0:8} = https:// ]] || [[ ${1:0:17} = http://localhost: ]]; then
      url=$(cut -d# -f1 <<<"$1")
      id=$(cut -d/ -f4 <<<"${url}")
      clientkey=$(cut -sd# -f2 <<<"$1")
      if [[ $# -eq 1 ]]; then
        decrypt "$url" "$id" "$clientkey"
      else
        shift
        main "$@"
      fi
    elif [[ ${1} == "-i" ]]; then
      mkdir -p "$HOME/.config/paste.sh"
      umask 0277
      (echo -n pasteauth=; randbase64 18) > "$HOME/.config/paste.sh/auth"
    elif [[ ${1} == "-h" ]] || [[ ${1} == "--help" ]]; then
      awk '/^# Usage:/{ p=1 } /^$/{ p=0 } p' "$0" | sed 's/^#//'
    elif [[ ${1} == "-p" ]]; then
      shift
      public=1
      main "$@"
    elif [[ ${1} == "--" ]]; then
      shift
      main "$@"
    elif [ -e "${1}" -o "${1}" == "-" ]; then
      # File (also handle "-", via cat)
      if [ "${1}" != "-" ] && [ "$(fsize "${1}")" -gt $[640 * 1024] ]; then
        die "${1}: File too big"
      fi
      encrypt "cat --" "$1" "$id" "$clientkey"
    else
      echo "$1: No such file and not a URL"
      exit 1
    fi
  elif ! [ -t 0 ]; then  # Something piped to us, read it
    encrypt cat "-" "$id" "$clientkey"
  # No input, maybe read clipboard
  elif [[ $(uname) = Darwin ]]; then
    encrypt pbpaste "" "$id" "$clientkey"
  elif [[ -n $DISPLAY ]]; then
    encrypt xsel "-o" "$id" "$clientkey"
  else
    echo "paste.sh client -- no clipboard available"
    echo "Try: $0 file"
  fi
}
main "$@"
