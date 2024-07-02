#!/usr/bin/env bash
[[ -f local/bin/twiggy ]] || carton
exec carton exec twiggy --listen 127.0.0.1:5000
