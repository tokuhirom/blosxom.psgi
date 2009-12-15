#!/usr/bin/perl
package MyBlosxom;
use strict;
use warnings;
use autodie;
use 5.010;
use Path::Class qw/dir/;
use Text::MicroTemplate::File;
use Time::Piece;

my $config = {
    data_dir => 'data/',
    title    => "Blosxom.PSGI!",
    author   => "anonymous",
};

sub get_entries {
    my @entries;
    dir( $config->{data_dir} )->recurse(
        callback => sub {
            my $f = shift;
            return unless $f =~ /\.txt$/ && -f $f;

            open my $fh, '<:utf8', $f;
            my ( $title, @content ) = <$fh>;
            close $fh;

            push @entries, +{
                mtime   => Time::Piece->new( $f->stat->mtime ),
                title   => $title,
                content => join( "", @content ),
                file    => $f,
                name    => do {
                    local $_ = "$f";
                    s/^$config->{data_dir}|\..*$//g;
                    $_;
                }
            };
        }
    );
    return reverse sort { $a->{mtime} <=> $b->{mtime} } @entries;
}

sub {
    my $env = shift;

    # get data
    my @entries = get_entries();
    my ($path_info, $flavor) = ($env->{PATH_INFO} =~ /(.+?)(\.[^.]+)?$/);
    $flavor //= '.html';
    if ($path_info =~ m{/(?<year>\d{4})(?:/(?<month>\d\d?)(?:/(?<day>\d\d?))?)?$}) {
        for my $key (qw/year month day/) {
            next unless $+{$key};
            @entries = grep { $_->{mtime}->$key eq $+{$key} } @entries;
        }
    } else {
        (my $path = $path_info) =~ s!^/*!!;
        @entries = sub {
            my @e;
            for my $e (@entries) {
                if ($e->{name} eq $path) {
                    return ($e);
                }
                if ($e->{name} =~ /^$path/) {
                    push @e, $e;
                }
            }
            @e;
        }->();
    }

    # rendering
    my $mt = Text::MicroTemplate::File->new(
        include_path => './',
    );
    my $body = $mt->render_file("template$flavor", {
        entries => \@entries,
        home    => $env->{"SCRIPT_NAME"} // '/',
        %$config,
    });

    # create response
    utf8::encode($body);
    return [
        200,
        [
            'Content-Length' => length($body),
            'Content-Type'   => 'text/html; charset=utf-8',
        ],
        [$body],
    ];
}

