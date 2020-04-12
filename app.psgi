package PasteSh;
use JSON;
use Plack::Request;
use Scalar::Util qw(blessed);
use Tie::LevelDB;
use Web::Simple;

tie my %data, 'Tie::LevelDB', 'db';

my $serverauth = do {
  open my $fh, "<", "serverauth" or die "serverauth: $!";
  (<$fh> =~ /(.*)/)[0];
};

my @common_headers = (
  'Strict-Transport-Security' => 'max-age=31536000',
  'Server' => 'paste.sh/' . do { chomp(my $t = `git describe --always`); $t });


sub _error {
  my($message, $code) = @_;
  return [ $code,
    [ 'Content-Type' => 'text/plain', @common_headers ],
    [ $message . "\n" ] ];
}

sub dispatch_request {
  my($self, $env) = @_;
  
  sub (/) {
    my($self) = @_;
    redispatch_to '/index';
  },
  sub (GET + /cryptojs/*.*) {
    my($self, $file) = @_;
    if($file =~ /[^a-z0-9-.]/ || !-f "crypto-js/src/$file") {
      return _error('Not found', 404);
    }
    open my $fh, "<", "crypto-js/src/$file" or return;
    return [ 200,
      [ 'Content-type', 'text/javascript', @common_headers ],
      [ <$fh> ] ];
  },
  sub (GET + /favicon.ico) {
    my($self) = @_;
    open my $fh, "<", "favicon.ico" or return;
    return [ 200,
      [ 'Content-type', 'image/x-icon', @common_headers ],
      [ <$fh> ] ];
  },
  sub (GET + /new + ?id=) {
    my($self, $id) = @_;
    if($data{$id}) {
      return _error('Already exists', 409);
    }

    return [ 200, [ 'Content-type', 'text/plain', @common_headers ],
      [ map chr 32 + rand 96, 1 .. 8 ] ];
  },
  sub (GET + /* + .txt) {
    my($self, $path) = @_;
    my $data = exists $data{$path} ? eval { decode_json $data{$path} } : undef;

    if(!$data) {
      return _error('Not found', 404);
    }

    my $content = $data->{content};
    $content =~ s/\G(.{65})/$1\n/g;

    return [ 200, [
        'Content-type' => 'text/plain',
        @common_headers
      ], [
        $data->{serverkey} . "\n" . $content . "\n"
      ] ];
  },
  sub (GET + /**) {
    my($self, $path) = @_;
    my $req = Plack::Request->new($env);
    my $cookie = $req->cookies->{pasteauth};

    my $data = exists $data{$path} ? eval { decode_json $data{$path} } : undef;

    if(!$data) {
      return _error('Not found', 404);
    }

    open my $fh, "<", "paste.html" or die $!;
    my $template = join "", <$fh>;
    my $public = $path =~ /^p.{8}/;

    $template =~ s/\{\{encrypted\}\}/$public ? "" : "encrypted"/e;
    $template =~ s/\{\{content\}\}/$data->{content}/;
    $template =~ s/\{\{serverkey\}\}/
      to_json($data->{serverkey} || "", { allow_nonref => 1 })/e;
    $template =~ s/\{\{editable\}\}/
      ($cookie && $data->{cookie} && $cookie eq $data->{cookie})
      || $path eq 'index'/e;

    return [ 200, [
        'Content-type' => 'text/html; charset=UTF-8',
        (!$public && $path =~ /.{8}/) ? ('X-Robots-Tag' => 'noindex') : (),
        @common_headers
      ], [ $template ] ];
  },
  sub (PUT + /**) {
    my($self, $path) = @_;
    my $req = Plack::Request->new($env);
    my $content = $req->content;
    my $cookie = $req->cookies->{pasteauth};

    my $sauth = $req->header('X-Server-Auth');
    if($sauth) {
      if($sauth ne $serverauth) {
        return _error("Invalid auth", 403);
      }
      # Authed clients can write anything (for updating about, etc).
    } elsif(length($path) < 8 || length($path) > 12 || $path =~ m{[^A-Za-z0-9_-]}) {
      return _error("Invalid path", 400);
    }

    if(!$sauth && exists $data{$path}) {
      if(my $cur = eval { decode_json $data{$path} }) {
        if(!$cur->{cookie} || $cur->{cookie} ne $cookie) {
          return _error("Invalid cookie", 403);
        }
      }
    }

    $content =~ s/[\r\n]//g;
    if($content =~ m{[^A-Za-z0-9/+=]}) {
      return _error("Content contains non-base64", 403);
    }

    if(length $content > (640 * 1024)) {
      return _error("Content too large", 413);
    }

    my $serverkey = $req->header('X-Server-Key');

    $data{$path} = encode_json {
      content => $content,
      cookie => $cookie,
      timestamp => time,
      serverkey => $serverkey,
    };

    [ 200,
      [ 'Content-type', 'text/plain', @common_headers ],
      [ "Saved " . length($content) . " bytes.\n" ] ]
  },
  sub () {
    _error("Not found", 404);
  }
}

__PACKAGE__->run_if_script;
