# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Arecibo;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(
    arecibo_handle_error
    arecibo_generate_id
    arecibo_should_notify
);

use Apache2::Log;
use Apache2::SubProcess;
use Carp;
use Email::Date::Format 'email_gmdate';
use LWP::UserAgent;
use POSIX 'setsid';
use Sys::Hostname;

use Bugzilla::Util;

use constant CONFIG => {
    # 'types' maps from the error message to types and priorities
    types => [
        {
            type  => 'the_schwartz',
            boost => -10,
            match => [
                qr/TheSchwartz\.pm/,
            ],
        },
        {
            type  => 'database_error',
            boost => -10,
            match => [
                qr/DBD::mysql/,
                qr/Can't connect to the database/,
            ],
        },
        {
            type  => 'patch_reader',
            boost => +5,
            match => [
                qr#/PatchReader/#,
            ],
        },
        {
            type  => 'uninitialized_warning',
            boost => 0,
            match => [
                qr/Use of uninitialized value/,
            ],
        },
    ],

    # 'codes' lists the code-errors which are sent to arecibo
    codes => [qw(
        bug_error
        chart_datafile_corrupt
        chart_dir_nonexistent
        chart_file_open_fail
        illegal_content_type_method
        jobqueue_insert_failed
        ldap_bind_failed
        mail_send_error
        template_error
        token_generation_error
    )],

    # any error messages matching these regex's will not be sent to arecibo
    ignore => [
        qr/^Software caused connection abort/,
    ],
};

sub arecibo_generate_id {
    return sprintf("%s.%s", (time), $$);
}

sub arecibo_should_notify {
    my $code_error = shift;
    return grep { $_ eq $code_error } @{CONFIG->{codes}};
}

sub arecibo_handle_error {
    my $class = shift;
    my @message = split(/\n/, shift);
    my $id = shift || arecibo_generate_id();

    my $is_error = $class eq 'error';
    if ($class ne 'error' && $class ne 'warning') {
        # it's a code-error
        return 0 unless arecibo_should_notify($class);
        $is_error = 1;
    }

    # build traceback
    my $traceback;
    {
        # for now don't show function arguments, in case they contain
        # confidential data.  waiting on bug 700683
        #local $Carp::MaxArgLen  = 256;
        #local $Carp::MaxArgNums = 0;
        local $Carp::MaxArgNums = -1;
        local $Carp::CarpInternal{'CGI::Carp'} = 1;
        local $Carp::CarpInternal{'Bugzilla::Error'}   = 1;
        local $Carp::CarpInternal{'Bugzilla::Arecibo'} = 1;
        $traceback = Carp::longmess();
    }

    # strip timestamp
    foreach my $line (@message) {
        $line =~ s/^\[[^\]]+\] //;
    }
    my $message = join(" ", map { trim($_) } grep { $_ ne '' } @message);

    # don't send to arecibo unless configured
    my $arecibo_server = Bugzilla->params->{arecibo_server} || '';
    my $send_to_arecibo = $arecibo_server ne '';
    if ($send_to_arecibo) {
        # message content filtering
        foreach my $re (@{CONFIG->{ignore}}) {
            if ($message =~ $re) {
                $send_to_arecibo = 0;
                last;
            }
        }
    }

    # log to apache's error_log
    if ($send_to_arecibo) {
        $message .= " [#$id]";
    } else {
        $traceback =~ s/\n/ /g;
        $message .= " $traceback";
    }
    _write_to_error_log($message, $is_error);

    return 0 unless $send_to_arecibo;

    # set the error type and priority from the message content
    $message = join("\n", grep { $_ ne '' } @message);
    my $type = '';
    my $priority = $class eq 'error' ? 3 : 10;
    foreach my $rh_type (@{CONFIG->{types}}) {
        foreach my $re (@{$rh_type->{match}}) {
            if ($message =~ $re) {
                $type = $rh_type->{type};
                $priority += $rh_type->{boost};
                last;
            }
        }
        last if $type ne '';
    }
    $type ||= $class;
    $priority = 1 if $priority < 1;
    $priority = 10 if $priority > 10;

    my $username = '';
    eval { $username = Bugzilla->user->login };

    my $data = [
        msg        => $message,
        priority   => $priority,
        server     => hostname(),
        status     => '500',
        timestamp  => email_gmdate(),
        traceback  => $traceback,
        type       => $type,
        uid        => $id,
        url        => Bugzilla->cgi->self_url,
        user_agent => $ENV{HTTP_USER_AGENT},
        username   => $username,
    ];

    # fork then post
    $SIG{CHLD} = 'IGNORE';
    my $pid = fork();
    if (defined($pid) && $pid == 0) {
        # detach
        chdir('/');
        open(STDIN, '</dev/null');
        open(STDOUT, '>/dev/null');
        open(STDERR, '>/dev/null');
        setsid();

        # post to arecibo (ignore any errors)
        my $agent = LWP::UserAgent->new(
            agent   => 'bugzilla.mozilla.org',
            timeout => 10, # seconds
        );
        $agent->post($arecibo_server, $data);

        CORE::exit(0);
    }
    return 1;
}

sub _write_to_error_log {
    my ($message, $is_error) = @_;
    if ($ENV{MOD_PERL}) {
        if ($is_error) {
            Apache2::ServerRec::log_error($message);
        } else {
            Apache2::ServerRec::warn($message);
        }
    } else {
        print STDERR "$message\n";
    }
}

# lifted from Bugzilla::Error
sub _in_eval {
    my $in_eval = 0;
    for (my $stack = 1; my $sub = (caller($stack))[3]; $stack++) {
        last if $sub =~ /^ModPerl/;
        $in_eval = 1 if $sub =~ /^\(eval\)/;
    }
    return $in_eval;
}

BEGIN {
    require CGI::Carp;
    CGI::Carp::set_die_handler(sub {
        return if _in_eval();
        my $message = shift;
        my $is_compilation_failure = $message =~ /\bcompilation aborted\b/;
        if (!$is_compilation_failure) {
            eval { Bugzilla::Error::ThrowTemplateError($message) };
        }
        if ($is_compilation_failure || $@) {
            print "Content-type: text/html\n\n";
            my $uid = arecibo_generate_id();
            my $notified = arecibo_handle_error('error', $message, $uid);
            my $maintainer = html_quote(Bugzilla->params->{'maintainer'});
            $message = html_quote($message);
            $uid = html_quote($uid);
            print qq(
                <h1>Bugzilla has suffered an internal error</h1>
                <pre>$message</pre>
            );
            if ($notified) {
                print qq(
                    The <a href="mailto:$maintainer">Bugzilla maintainers</a> have
                    been notified of this error [#$uid].
                );
            };
            exit;
        }
    });
    $main::SIG{__WARN__} = sub {
        return if _in_eval();
        arecibo_handle_error('warning', shift);
    };
}

1;
