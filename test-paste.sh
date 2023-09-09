#!/bin/bash
shopt -s extglob

paste="$(echo hello world | ./paste.sh)"
if [[ $[0+$(<<<"$paste" wc -l)] != 2 ]]; then
  echo "Expected 2 lines, got '$paste'"
  exit 1
fi

url="$(<<<"$paste" tail -1)"
if [[ $url != https://paste.sh/*#* ]]; then
  echo "got '$url', expected a paste.sh one"
  exit 1
fi

fetch="$(./paste.sh "$url")"
if [[ $fetch != "hello world" ]]; then
  echo "got '$fetch', expected hello world"
  exit 1
fi

public_url="$(echo hello world | ./paste.sh -p | tail -1)"
if [[ $public_url != https://paste.sh/p+([-_A-Za-z0-9]) ]]; then
  echo "got '$public_url', expected a paste.sh public one"
  exit 1
fi

fetch="$(./paste.sh "$public_url")"
if [[ $fetch != "hello world" ]]; then
  echo "got '$fetch', expected hello world (public)"
  exit 1
fi

echo OK
