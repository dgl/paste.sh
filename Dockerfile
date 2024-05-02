FROM perl:stable

WORKDIR /app

RUN tee cpanfile <<EOF
requires 'JSON';
requires 'JSON::XS';
requires 'Tie::LevelDB';
requires 'Web::Simple';
requires 'Plack::Request';
requires 'Plack::Runner';
requires 'HTML::Entities';
requires 'Twiggy';
EOF

RUN cpanm --installdeps .

COPY . /app

EXPOSE 5000

# twiggy --listen 127.0.0.1:5000
CMD ["bash", "run-docker.sh"]