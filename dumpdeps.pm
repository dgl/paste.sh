# Dump the dependencies of a perl program, both Perl and shared libraries for
# modules and the interpreter.

package dumpdeps;
use v5.20;

use constant LIB_IS_SYMLINK => -l "/lib";

my %additional_requires = (
  "LWP/UserAgent.pm" => [qw(HTTP::Headers::Util LWP::Authen::Basic HTTP::Request::Common HTML::HeadParser HTTP::Config File::Temp Encode Encode::Locale LWP::Protocol::http LWP::Protocol::https)],
  "URI.pm" => [qw(URI/_foreign.pm URI::data URI::file URI::http URI::https)],
  "Plack/Runner.pm" => [qw(Getopt::Long Getopt::Long::Parser Plack::Loader Socket POSIX Carp Config_heavy.pl)],
);

our $x;

sub new {
  return bless {}, shift;
}

sub DESTROY {
  say $0;

  for my $module (keys %::INC) {
    if (exists $additional_requires{$module}) {
      eval "require $_" for @{$additional_requires{$module}};
    }
  }

  for (values %::INC) {
    say if -f;
  }

  my %seen;

  # loaded shared libraries + mmaped data, etc.
  {
    open my $fh, "<", "/proc/self/maps" or die $!;
    while(<$fh>) {
      if (m{ (/.*?)$}) {
        say $1 unless $seen{$1}++;
      }
    }
  }

  # ldd deps (will in most cases pick up symlinks, which we try to also resolve below).
  {
    open my $fh, "-|", "ldd", $^X or die $!;
    while(<$fh>) {
      if (m{\s(/.*?) \(}) {
        my $l = $1;
        $l =~ s{^/lib}{/usr/lib} if LIB_IS_SYMLINK;
        say $l unless $seen{$l}++;
      }
    }
  }

  for (keys %seen) {
    if (LIB_IS_SYMLINK) {
      if (m{^(/usr?)/lib/}) {
        say "/lib" unless $seen{"/lib"}++;
      } elsif (m{^(/usr)?/lib64/}) {
        say "/lib64" unless $seen{"/lib64"}++;
      }
    }

    if (m{^(.*\.so)\.([0-9.]+)$}) {
      my $l = $1;
      my $v = $2;
      if ($v =~ /\./) {
        my @parts = split /\./, $v;
        for my $i (1 .. @parts) {
          my $solib = "$l." . join(".", @parts[0 .. $i-1]);
          if (-e $solib) {
            say $solib unless $seen{$solib}++;
          }
        }
      }
    }
  }
}

BEGIN {
  $x = __PACKAGE__->new;
}

1;
