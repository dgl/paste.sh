#!/bin/bash
[[ -f deps/bin/twiggy ]] || \
  cpanm -l deps JSON JSON::XS Tie::LevelDB Web::Simple Plack::Request Twiggy
exec deps/bin/twiggy -Ideps/lib/perl5 --listen 127.0.0.1:5000
