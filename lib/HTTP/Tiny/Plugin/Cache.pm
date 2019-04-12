package HTTP::Tiny::Plugin::Cache;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Digest::SHA;
use File::Util::Tempdir;
use Storable qw(store_fd fd_retrieve);

sub meta {
}

sub before_request {
    my ($class, $r) = @_;

    my ($self, $method, $url, $options) = @{ $r->{argv} };
    unless ($method eq 'GET') {
        log_trace "Not a GET response, skip caching";
        return -1; # decline
    }

    my $tempdir = File::Util::Tempdir::get_user_tempdir();
    my $cachedir = "$tempdir/http_tiny_plugin_cache";
    #log_trace "Cache dir is %s", $cachedir;
    unless (-d $cachedir) {
        mkdir $cachedir or die "Can't mkdir '$cachedir': $!";
    }
    my $cachepath = "$cachedir/".Digest::SHA::sha256_hex($url);
    log_trace "Cache file is %s", $cachepath;

    my $maxage = $r->{config}{max_age} //
        $ENV{HTTP_TINY_PLUGIN_CACHE_MAX_AGE} //
        $ENV{CACHE_MAX_AGE} // 86400;

    if (!(-f $cachepath) || (-M _) > $maxage/86400) {
        # cache does not exist or too old, we execute request() as usual and
        # later save
        $r->{cache_response}++;
        return 0;
    } else {
        log_trace "Retrieving response from cache ...";
        open my $fh, "<", $cachepath
            or die "Can't read cache file '$cachepath' for '$url': $!";
        $r->{response} = fd_retrieve $fh;
        close $fh;
        return 99; # skip request()
    }
}

sub after_request {
    my ($class, $r) = @_;

  CACHE_RESPONSE:
    {
        last unless $r->{cache_response};
        log_trace "Saving response to cache ...";
        open my $fh, ">", $cachepath
            or die "Can't create cache file '$cachepath' for '$url': $!";
        store_fd $r->{response}, $fh;
        close $fh;
        undef $r->{cache_response};
    }
    0;
}

1;
# ABSTRACT: Cache HTTP::Tiny responses

=head1 SYNOPSIS

 use HTTP::Tiny::Plugin 'Cache' => {
     max_age => '3600', # defaults to HTTP_TINY_PLUGIN_CACHE_MAX_AGE or CACHE_MAX_AGE or 86400
 };

 my $res  = HTTP::Tiny::Plugin->new->get("http://www.example.com/");
 my $res2 = HTTP::Tiny::Plugin->request(GET => "http://www.example.com/"); # cached response


=head1 DESCRIPTION

This plugin can cache responses to cache files.

Currently only GET requests are cached. Cache are keyed by SHA256-hex(URL).
Error responses are also cached. Currently no cache-related HTTP request or
response headers (e.g. C<Cache-Control>) are respected.


=head1 CONFIGURATION

=head2 max_age

Int.


=head1 ENVIRONMENT

=head2 CACHE_MAX_AGE

Int. Will be consulted after L</"HTTP_TINY_PLUGIN_CACHE_MAX_AGE">.

=head2 HTTP_TINY_PLUGIN_CACHE_MAX_AGE

Int. Will be consulted before L</"CACHE_MAX_AGE">.


=head1 SEE ALSO

L<HTTP::Tiny::Plugin>
