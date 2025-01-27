#!/usr/bin/env bash
# Client for paste.sh - https://paste.sh
#
# ©David Leadbeater <https://dgl.cx/0bsd>, NO WARRANTY
# SPDX-License-Identifier: 0BSD
#
# Install:
#   mkdir -p ~/bin && cd ~/bin && curl -OJ https://paste.sh && chmod +x paste.sh
#
# Usage:
#   Send clipboard:
#     $ paste.sh
#   Send output of command:
#     $ foo 2&>1 | paste.sh
#   Paste file:
#     $ paste.sh some-file
#
#   Add title to paste:
#     $ paste.sh -s "Some cool paste"
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
VERSION=v2

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
  echo -n "${id}${serverkey}${clientkey}https://paste.sh"
}

encrypt() {
  local cmd arg
  cmd="$1"
  arg="$2"
  id="$3"
  clientkey="$4"
  header="$5"

  if [[ -z ${id} ]]; then
    # Generate ID
    id="$(randbase64 6)"
    if [[ $public == 1 ]]; then
      clientkey=
      id="p${id}"
    fi
  fi

  if [[ $public == 0 ]]; then
    if [[ -z $clientkey ]]; then
      # Generate client key (nothing stopping you changing this, this seemed like
      # a reasonable trade off; 144 bits)
      clientkey="$(randbase64 18)"
    fi
  fi

  pasteauth=""
  if [[ -f "$HOME/.config/paste.sh/auth" ]]; then
    pasteauth="$(<$HOME/.config/paste.sh/auth)"
  fi

  file=$(mktemp -t $TMPTMPL)
  trap 'rm -f "${file}"' EXIT
  # The key here is not user controlled, more iterations won't help, but using
  # -iter and therefore PBKBF2 avoids a warning from OpenSSL.
  (echo -n "${header}${header:+$'\n\n'}"; $cmd "$arg") \
    | 3<<<"$(writekey)" openssl enc -aes-256-cbc -md sha512 -pass fd:3 -iter 1 -base64 > "${file}"

  et="\"$(etag <"${file}")\""
  (curl -sS -o /dev/fd/3 -H "X-Server-Key: ${serverkey}" \
    -H "Content-type: text/vnd.paste.sh-${VERSION}" \
    -H "ETag: $et" \
    -T "${file}" "${HOST}/${id}" -b "$pasteauth" -w '%{http_code}' \
    | grep -q 200) 3>&1 || exit $?

  echo "${HOST}/${id}${clientkey:+#}${clientkey}"
}

remove_header() {
  awk 'i == 1 { print }; /^\r?$/ { i=1 }'
}

decrypt() {
  local url
  url="$1"
  id="$2"
  clientkey=$3
  tmpfile=$(mktemp -t $TMPTMPL)
  headfile=$(mktemp -t $TMPTMPL)
  trap 'rm -f "${tmpfile}" "${headfile}"' EXIT
  curl -fsS -o "${tmpfile}" -H "Accept: text/plain, text/vnd.paste.sh-v2, text/vnd-paste.sh-v3" \
    -D "${headfile}" "${url}.txt" || exit $?
  serverkey=$(head -n1 "${tmpfile}")
  ct="$(grep -i '^content-type:' ${headfile} | cut -d':' -f2)"

  et="$(grep -i '^etag:' ${headfile} | cut -d':' -f2 | tr -d '\015 ')"
  if [[ -n "$et" ]]; then
    expected_et="\"$(etag <"${tmpfile}")\""
    if [[ "$et" != "$expected_et" ]]; then
      die "Decryption failed (Invalid decryption key or damaged data)" 1
    fi
  fi

  remove=cat
  ITERS="-iter 1"
  if [[ $ct = *text/plain* ]]; then
    ITERS=""
  elif [[ $ct = *text/vnd.paste.sh-v3* ]]; then
    remove=remove_header
  fi
  tail -n +2 "${tmpfile}" | \
    3<<<"$(writekey)" openssl enc -d -aes-256-cbc -md sha512 -pass fd:3 $ITERS -base64 | \
    $remove
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

etag() {
  # "61757468206b6579" is "auth key"
  openssl base64 -d | hmac "$(writekey | hmac "61757468206b6579")" "-binary" | openssl base64 -A | sed 's/==$//'
}

# Implement HMAC on top of OpenSSL's digest command, as openssl's CLI support
# for generating a HMAC needs the key on the command line.
# These should be identical:
#   echo -n ok | openssl dgst -sha512 -mac hmac -macopt hexkey:61757468206b6579
#   echo -n ok | hmac "61757468206b6579"
#
hmac() {
  local key="$1"
  local opts="$2"
  key="$key" perl -e'print join("", map { chr hex } $ENV{key} =~ /(..)/g)^"\x36"x128; print join "", <>' | openssl sha512 -binary | \
    key="$key" perl -e'print join("", map { chr hex } $ENV{key} =~ /(..)/g)^"\x5c"x128; print join "", <>' | openssl sha512 $opts | hmactext "$opts"
}

hmactext() {
  if [[ $1 = "" ]]; then
    sed 's/^.* //'
  else
    cat
  fi
}

# Try to use memory if we can (Linux, probably) and the user hasn't set TMPDIR
if [ -z "$TMPDIR" -a -w /dev/shm ]; then
  export TMPDIR=/dev/shm
fi

# What are we doing?
public=0
header=""
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
    elif [[ ${1} == "-H" ]]; then
      shift
      HOST=$1
      shift
      main "$@"
    elif [[ ${1} == "-p" ]]; then
      shift
      public=1
      main "$@"
    elif [[ ${1} == "-s" ]]; then
      shift
      VERSION="v3"
      header="$(printf "Subject: %s\n%s" "$1" "$header")"
      shift
      main "$@"
    elif [[ ${1} == "-t" ]]; then
      shift
      VERSION="v3"
      header="$(printf "Content-Type: %s\n%s" "$1" "$header")"
      shift
      main "$@"
    elif [[ ${1} == "-v" ]]; then
      shift
      VERSION="v${1}"
      shift
      main "$@"
    elif [[ ${1} == "--" ]]; then
      shift
      main "$@"
    elif [ -e "${1}" -o "${1}" == "-" ]; then
      # File (also handle "-", via cat)
      if [ "${1}" != "-" ] && [ "$(fsize "${1}")" -gt $[1024 * 1024] ]; then
        die "${1}: File too big"
      fi
      encrypt "cat --" "$1" "$id" "$clientkey" "$header"
    else
      echo "$1: No such file and not a URL"
      exit 1
    fi
  elif ! [ -t 0 ]; then  # Something piped to us, read it
    encrypt cat "-" "$id" "$clientkey" "$header"
  # No input, maybe read clipboard
  elif [[ $(uname) = Darwin ]]; then
    encrypt pbpaste "" "$id" "$clientkey" "$header"
  elif [[ -n $DISPLAY ]]; then
    encrypt xsel "-o" "$id" "$clientkey" "$header"
  else
    echo "paste.sh client -- no clipboard available"
    echo "Try: $0 file"
  fi
}
main "$@"
