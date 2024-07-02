FROM perl:stable

WORKDIR /app
COPY . /app
RUN cpanm --installdeps .

EXPOSE 5000
CMD ["run-docker.sh"]
