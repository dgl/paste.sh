FROM perl:stable AS deps-test

RUN cpanm Carton
COPY cpanfile .
# Lock versions by bundling here.
RUN carton install && carton bundle

FROM perl:stable
COPY . .

COPY --from=deps-test vendor/ .
# Use version requirements from above.
RUN cpanm --notest --from "$PWD/vendor/cache" --installdeps .

# This image needs a secret of 'serverauth' and a volume mounted at '/db'.
RUN ln -sf /run/secrets/serverauth && ln -sf /db

EXPOSE 5000
CMD ["./run-docker.sh"]
