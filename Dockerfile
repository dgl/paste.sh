# These should correspond to the same Debian release so the distroless base
# image matches the Debian used to build the perl image.
ARG DEBIAN_VERSION=12
ARG DEBIAN_CODENAME=bookworm

# This is a tag from https://hub.docker.com/_/perl, with -DEBIAN_CODENAME
# appended.
ARG PERL_VERSION=5.40

FROM perl:${PERL_VERSION}-${DEBIAN_CODENAME} AS deps-test

RUN cpanm Carton
COPY cpanfile* .
RUN carton install && carton bundle

FROM perl:${PERL_VERSION}-${DEBIAN_CODENAME} AS build-deps
SHELL ["/bin/bash", "-c"]
COPY cpanfile* .
COPY --from=deps-test /usr/src/app/vendor/ ./vendor
# Use version requirements from above
RUN cpanm --notest --from "$PWD/vendor/cache" --installdeps . && rm -rf ~/.cpanm ./vendor

COPY . .

# Get actual dependencies of twiggy and app
RUN <<EOF
set -xeo pipefail
# XXX: Config... is loaded on demand in some cases
(PERL5OPT="-I$(pwd) -Mdumpdeps" perl -c /usr/local/bin/twiggy; PERL5OPT="-I$(pwd) -Mdumpdeps" perl -c $(pwd)/app.psgi; echo $(pwd); echo /usr/local/lib/perl5/site_perl; echo /usr/local/lib/perl5/5.40.1/x86_64-linux-gnu/Config*) | xargs tar cvfz /dist.tgz
EOF

# "uclibc" is statically linked.
FROM busybox:stable-uclibc AS busybox

# Add a single busybox binary to scratch, to extract the tarball of perl and the app together.
FROM scratch AS build-tar
COPY --from=busybox /bin/busybox /bin/busybox
COPY --from=build-deps /dist.tgz /
SHELL ["/bin/busybox", "sh", "-c"]
RUN busybox tar xvf /dist.tgz && \
  # This image needs a secret of 'serverauth' and a volume mounted at '/db'.
  (cd /usr/src/app && busybox rm -f serverauth && busybox ln -sf /run/secrets/serverauth && busybox ln -sf /db) && \
  busybox mkdir /db && busybox chown 65532:65532 /db && \
  busybox rm /usr/src/app/dumpdeps.pm /dist.tgz /bin/busybox

#FROM gcr.io/distroless/static-debian${DEBIAN_VERSION}:debug-nonroot AS distroless-debug
FROM gcr.io/distroless/static-debian${DEBIAN_VERSION}:nonroot
COPY --from=busybox /bin/busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-c"]
USER root
RUN /bin/busybox rmdir /lib && /bin/busybox rm /bin/busybox
USER nonroot
COPY --link --from=build-tar / /
# debug: docker run -it --entrypoint /busybox/sh ...
#COPY --link --from=distroless-debug /busybox /busybox
WORKDIR /usr/src/app
SHELL ["/bin/sh", "-c"]
EXPOSE 5000
ENTRYPOINT ["/usr/local/bin/perl"]
VOLUME /db
CMD ["/usr/local/bin/twiggy", "--listen", ":5000"]
