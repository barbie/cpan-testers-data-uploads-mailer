package CPAN::Testers::Data::Uploads::Mailer;

use warnings;
use strict;
$|++;

our $VERSION = '0.03';

#----------------------------------------------------------------------------

=head1 NAME

CPAN::Testers::Data::Uploads::Mailer - Verify CPAN uploads and mails reports

=head1 SYNOPSIS

    my $mailer = CPAN::Testers::Data::Uploads::Mailer->new();
    $mailer->process();

=head1 DESCRIPTION

Reads the uploads log, then generates and emails the bad uploads report to 
the appropriate authors.

=cut

# -------------------------------------
# Library Modules

use Email::Simple;
use File::Basename;
use File::Path;
use File::Slurp;
use Getopt::ArgvFile default=>1;
use Getopt::Long;
use IO::File;
use Template;
use Time::Piece;

# -------------------------------------
# Variables

# the following will have the emails mailed to them too
my @ADMINS = ('barbie@missbarbell.co.uk');
my %ADMINS = map {$_ => 1} @ADMINS;

my %default = (
    source      => 'logs/uploads.log',
    lastfile    => 'logs/uploads-mailer.txt',
    logfile     => 'logs/uploads-mailer.log',
    debug       => 0,   # if set to 1 will not send mails
    test        => 1    # if set to 1 will only send to @ADMINS
);

#my $HOW  = 'blah';
my $HOW  = '/usr/sbin/sendmail -bm';
my $HEAD = 'To: EMAIL
From: Barbie <barbie@cpantesters.org>
Subject: SUBJECT
Date: DATE

';

#----------------------------------------------------------------------------
# The Application Programming Interface

sub new {
    my $class = shift;
    my %opts  = @_;

    my $self = {};
    bless $self, $class;

    $self->{options} = {};
    $self->{default}{$_} = $self->_defined_or($opts{$_}, $default{$_})  for(keys %default);
    $self->_init_options(@_);
    return $self;
}

sub process {
    my $self    = shift;
    my $source  = $self->{options}{source};
    my $lastid  = $self->_last_id();
    my $last_id = $lastid;

    $self->{mail}{layout}  = 'mail-bad-uploads.eml';

    my $fh = IO::File->new($source) or die "Cannot open file [$source]: $!";
    while(<$fh>) {
        chomp;

        #... [1281307] subject=CPAN Upload: A/AP/APLA/update_db_schema.pl
        my ($id,$path,$cpan,$dist) = m!\.\.\. \[(\d+)\] subject=CPAN Upload: (\w/\w{2}/(\w+)/(.*))!;
        next    unless($id && $id > $lastid);
        $last_id = $id;

        next    unless(defined $cpan);
        next    if($dist =~ /\.(?:(?:tar\.|t)(?:gz|bz2)|zip)$/i);   # valid archives
        next    if($dist =~ /\.(pl|sh)/i);                          # ignore scripts ...
        next    if($dist =~ /\.(gif|png|jpg)/i);                    # ... images ...
                                                                    # ... docs and patches, etc.
        next    if($dist =~ /\.(asc|pdf|ppm|patch|readme|meta|yml|pod|txt|changelog)/i);

        if($dist !~ /\b(rar|tgs|tbz|zip|tar|pm|gz|bz2|tz)$/i) {     # only attempts caught for now
            $self->{mail}{others} .= "$id,$path\n";
            next;
        }
        $self->{mail}{authors}{$cpan.'@cpan.org'} = 1;
        $self->{mail}{uploads} .= "$id,$path\n";
    }

    $self->_send_mail();

    $self->_last_id($last_id);
}

#----------------------------------------------------------------------------
# Private Methods

sub _send_mail {
    my $self = shift;

    return  unless(defined $self->{mail}{authors} && keys %{$self->{mail}{authors}});

    my $DATE = _emaildate();
    $DATE =~ s/\s+$//;

    my %tvars = (
        date    => $DATE,
        uploads => $self->{mail}{uploads},
    );

    my   @recipients;
    push @recipients, (keys %{$self->{mail}{authors}}) unless($self->{options}{test});
    push @recipients, @ADMINS;

    for my $addr (@recipients) {
        $tvars{email}  = $addr;
        $tvars{others} = $ADMINS{$addr} ? $self->{mail}{others}||'' : '';

        my $body = _create_mail($self->{mail}{layout},\%tvars);

        my $cmd = qq!| $HOW $addr!;

        if($self->{options}{debug}) {
                $self->_log("$DATE: NULL: $addr");
                $self->_log("$body");
        } else {
            if(my $fh = IO::File->new($cmd)) {
                print $fh $body;
                $fh->close;
                $self->_log("$DATE: PASS: $addr");
            } else {
                $self->_log("$DATE: FAIL: $addr");
            }
        }
    }
}

sub _create_mail {
    my $layout = shift;
    my $tvars  = shift;
    my $body;

    my %config = (                              # provide config info
        RELATIVE        => 1,
        ABSOLUTE        => 1,
        INCLUDE_PATH    => './templates',
        INTERPOLATE     => 0,
        POST_CHOMP      => 1,
        TRIM            => 1,
    );

    my $parser = Template->new(\%config);       # initialise parser
    $parser->process($layout,$tvars,\$body)     # parse the template
        or die $parser->error();

    return $body;
}

# Format date and time into one that conforms to the RFCs.

sub _emaildate {
    my $t = localtime;
    return $t->strftime("%a, %d %b %Y %H:%M:%S %z");
}

sub _last_id {
    my $self = shift;
    my ( $id ) = @_;

    overwrite_file( $self->{options}{lastfile}, 0 ) unless -f $self->{options}{lastfile};

    if (defined $id) {
        overwrite_file( $self->{options}{lastfile}, $id );
    } else {
        $id = read_file($self->{options}{lastfile});
    }

    return $id;
}

sub _log {
    my $self = shift;
    my $msg  = shift;
    my $logfile = $self->{options}{logfile};
    return  unless($logfile);

    my $fh = IO::File->new($logfile,'a+')   or die "Cannot write to file [$logfile]: $!\n";
    print $fh "$msg\n";
    $fh->close;
}

sub _defined_or {
    my $self = shift;
    while(@_) {
        my $value = shift;
        return $value   if(defined $value);
    }

    return;
}

sub _init_options {
    my $self = shift;

    GetOptions( $self->{options},
        'source|s=s',
        'logfile=s',
        'lastfile=s',
        'test|t!',
        'debug|d!',
        'help|h',
        'version|v'
    );

    _help(1) if($self->{options}{help});
    _help(0) if($self->{options}{version});

    $self->{options}{$_} = $self->_defined_or($self->{options}{$_}, $self->{default}{$_})  for(keys %default);

    unless(-f $self->{options}{source}) {
        print "No uploads source log file [$self->{options}{source}] found\n\n";
        _help(1);
    }

    mkpath(dirname($self->{options}{lastfile}));
    mkpath(dirname($self->{options}{logfile}));
}

sub _help {
    my $full = shift;

    if($full) {
        print <<HERE;

Usage: $0 \\
        [--logfile=<file>] [--source=<file>] [--lastfile=<file>] \\
        [--test] [--debug] [-h] [-V]

  --logfile         log file from cpanstats-verify
  --source          results output file
  --lastfile        last NNTP ID mailed out
  --test            send mails to admin only
  --debug           do not send mails
  -h                this help screen
  -V                program version

HERE

    }

    print "$0 v$VERSION\n";
    exit(0);
}

__END__

=head1 INTERFACE

=head2 The Constructor

=over

=item * new

Instatiates the CPAN::Testers::Data::Uploads::Mailer object.

  my $obj = CPAN::Testers::Data::Uploads::Mailer->new();
  $obj->process();

=back

=head2 Public Methods

=over

=item * process

Based on accessor settings will run the appropriate methods for the current
execution.

=back

=head1 BUGS, PATCHES & FIXES

There are no known bugs at the time of this release. However, if you spot a
bug or are experiencing difficulties, that is not explained within the POD
documentation, please send an email to barbie@cpan.org. However, it would help
greatly if you are able to pinpoint problems or even supply a patch.

Fixes are dependant upon their severity and my availablity. Should a fix not
be forthcoming, please feel free to (politely) remind me.

=head1 SEE ALSO

L<CPAN::Testers::Data::Uploads>

F<http://www.cpantesters.org/> (Reports),
F<http://stats.cpantesters.org/> (Statistics),
F<http://wiki.cpantesters.org/> (Wiki),
F<http://devel.cpantesters.org/> (Development)

=head1 AUTHOR

  Barbie, <barbie@cpan.org>
  for Miss Barbell Productions <http://www.missbarbell.co.uk>.

=head1 COPYRIGHT AND LICENSE

  Copyright (C) 2010 Barbie for Miss Barbell Productions.

  This module is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself.

=cut

