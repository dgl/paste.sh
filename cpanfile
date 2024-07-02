requires 'JSON';
requires 'JSON::XS';
requires 'Tie::LevelDB';
requires 'Web::Simple';
requires 'Plack::Request';
requires 'Plack::Runner';
requires 'HTML::Entities';
requires 'Twiggy';

# Build dep of other things; somehow carton doesn't figure it out, so depend on it here...
requires 'Module::Build::Tiny';
