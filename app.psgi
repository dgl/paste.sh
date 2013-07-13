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


sub dispatch_request {
  my($self, $env) = @_;
  
  sub (/) {
    my($self) = @_;
    redispatch_to '/index';
  },
  # For devel, in production this is served by another sever.
  sub (GET + /cryptojs/*.*) {
    my($self, $file) = @_;
    if($file =~ /[^a-z0-9-.]/ || !-f "crypto-js/src/$file") {
      return [ 404, [ 'Content-type', 'text/plain' ], [ 'Not found' ] ]
    }
    open my $fh, "<", "crypto-js/src/$file" or return;
    return [ 200, [ 'Content-type', 'text/javascript' ], [ <$fh> ] ]
  },
  sub (GET + /new + ?id=) {
    my($self, $id) = @_;
    if($data{$id}) {
      return [ 409, [ 'Content-type', 'text/plain' ], [ 'Already exists' ] ]
    }

    return [ 200, [ 'Content-type', 'text/plain' ],
      [ map chr 32 + rand 96, 1 .. 8 ] ];
  },
  sub (GET + /**) {
    my($self, $path) = @_;
    my $req = Plack::Request->new($env);
    my $cookie = $req->cookies->{pasteauth};

    my $data = exists $data{$path} ? eval { decode_json $data{$path} } : undef;

    if(!$data) {
      return [ 404, [ 'Content-type', 'text/plain' ], [ 'Not found' ] ];
    }

    open my $fh, "<", "paste.html" or die $!;
    my $template = join "", <$fh>;

    $template =~ s/\{\{content\}\}/$data->{content}/;
    $template =~ s/\{\{serverkey\}\}/
      to_json($data->{serverkey} || "", { allow_nonref => 1 })/e;
    $template =~ s/\{\{editable\}\}/
      ($cookie && $data->{cookie} && $cookie eq $data->{cookie})
      || $path eq 'index'/e;

    return [ 200, ['Content-type' => 'text/html; charset=UTF-8'], [ $template ] ];
  },
  sub (PUT + /**) {
    my($self, $path) = @_;
    my $req = Plack::Request->new($env);
    my $content = $req->content;
    my $cookie = $req->cookies->{pasteauth};

    my $sauth = $req->header('X-Server-Auth');
    if($sauth) {
      if($sauth ne $serverauth) {
        return [ 403, [ 'Content-type', 'text/plain' ], [ "Invalid auth\n" ] ]
      }
      # Authed clients can write anything (for updating about, etc).
    } elsif(length($path) < 8 || length($path) > 12 || $path =~ m{[^A-Za-z0-9_-]}) {
      return [ 400, [ 'Content-type', 'text/plain' ], [ "Invalid path\n" ] ]
    }

    if(!$sauth && exists $data{$path}) {
      if(my $cur = eval { decode_json $data{$path} }) {
        if(!$cur->{cookie} || $cur->{cookie} ne $cookie) {
          return [ 403, [ 'Content-type', 'text/plain' ], [ "Invalid cookie\n" ] ]
        }
      }
    }

    $content =~ s/[\r\n]//g;
    if($content =~ m{[^A-Za-z0-9/+=]}) {
      return [ 403, [ 'Content-type', 'text/plain' ],
        [ "Content contains non-base64\n" ] ];
    }

    if(length $content > (640 * 1024)) {
      return [ 403, [ 'Content-type', 'text/plain' ],
        [ "Content too large\n" ] ];
    }

    my $serverkey = $req->header('X-Server-Key');

    $data{$path} = encode_json {
      content => $content,
      cookie => $cookie,
      timestamp => time,
      serverkey => $serverkey,
    };

    [ 200, [ 'Content-type', 'text/plain' ], [ "Saved " . length($content) . " bytes.\n" ] ]
  },
  sub () {
    [ 404, [ 'Content-type', 'text/plain' ], [ 'Not found' ] ]
  }
}

__PACKAGE__->run_if_script;
