#!/usr/bin/env bash
[[ -f deps/bin/twiggy ]] || \
  cpanm -l deps --installdeps .
exec perl -Ideps/lib/perl5 deps/bin/twiggy --listen 127.0.0.1:5000
