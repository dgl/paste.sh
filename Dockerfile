FROM perl:stable AS deps-test

RUN cpanm Carton
COPY cpanfile .
COPY cpanfile.snapshot .
RUN carton install && carton bundle

FROM perl:stable
COPY . .

COPY --from=deps-test /usr/src/app/vendor/ ./vendor
# Use version requirements from above, remove build artifacts after
RUN cpanm --notest --from "$PWD/vendor/cache" --installdeps . && rm -rf ~/.cpanm vendor/

# This image needs a secret of 'serverauth' and a volume mounted at '/db'.
RUN ln -sf /run/secrets/serverauth && ln -sf /db

EXPOSE 5000
CMD ["./run-docker.sh"]
