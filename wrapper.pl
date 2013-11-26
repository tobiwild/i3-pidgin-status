#!/usr/bin/env perl

use strict;
use Data::Dumper;
use AnyEvent::DBus;
use AnyEvent::I3;
use List::Util qw/first/;
use JSON;
use Encode;

$| = 1;

my $cv = AnyEvent->condvar;
my $list = MessageList->new;
my $pidgin_ws = 'pidgin';
my $i3 = i3();
my $pidgin_ws_active;
$i3->connect->recv or die 'could not connect to i3';

sub get_msg_line {    
    my %data = @_;

    sprintf('%s: %s', $data{user}, $data{msg});
}

sub print_msg {
    print shift . "\n";
}

my $w; $w = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
     chomp (my $input = <STDIN>);
     
     $list->forward;
     print_msg $list->get_line;
});

sub create_timer {
    my $interval = 5;

    AnyEvent->timer (after => $interval, interval => $interval, cb => sub {
        $list->forward;
        print_msg $list->get_line;
    });
}

my $timer = create_timer();

sub add_pidgin_msg {

    if ($pidgin_ws_active) {
        return;
    }

    $list->add(get_msg_line(
        user => $_[1],
        msg  => $_[2],
    ));

    if ($list->forward_to_new) {
        $timer = create_timer;
    }

    print_msg $list->get_line;
}

$i3->subscribe({
    workspace => sub {
        my $ev = shift;

        $pidgin_ws_active = $ev->{change} eq 'focus' && index($ev->{current}->{name}, $pidgin_ws) > -1;

        if ($pidgin_ws_active) {
            $list->clear;    
        }
    }
});

my $bus     = Net::DBus->find;
my $service = $bus->get_service("im.pidgin.purple.PurpleService");
my $object  = $service->get_object("/im/pidgin/purple/PurpleObject");

$object->connect_to_signal('ReceivedChatMsg', \&add_pidgin_msg);
$object->connect_to_signal('ReceivedImMsg', \&add_pidgin_msg);

my $ws = $i3->get_workspaces->recv;
$pidgin_ws_active = !! first { $_->{focused} && index($_->{name}, $pidgin_ws) > -1 } @$ws;

$cv->recv;

package MessageList;

use strict;

sub new {
    bless {
        lines     => [],
        index     => 0,
        count_new => 0
    }, shift;
}

sub add {
    my ($this, $line) = @_;

    push @{$this->{lines}}, $line;
    $this->{count_new}++;
}

sub clear {
    my $this = shift;

    $this->{lines} = [];
    $this->{index} = 0;
    $this->{count_new} = 0;
}

sub get_line {
    my $this = shift;

    if (! @{$this->{lines}}) {
        return '';
    }

    my $result =  sprintf '[%d/%d] %s',
        $this->{index} + 1,
        scalar(@{$this->{lines}}),
        $this->{lines}->[$this->{index}];


    my $count_new = $this->{count_new};

    if ($this->{index} >= scalar(@{$this->{lines}}) - $count_new) {
        $count_new--;
    } 

    if ($count_new) {
        $result .= sprintf ' (+%d)', $count_new;
    }

    $result;
}

sub forward {
    my $this = shift;

    if (! @{$this->{lines}}) {
        return;
    }

    if ($this->{index} == $#{$this->{lines}}) {
        $this->{index}     = 0;
        $this->{count_new} = 0;
    } else {
        $this->{index}++;
        if ($this->{index} >= scalar(@{$this->{lines}}) - $this->{count_new}) {
            $this->{count_new}--;
        }
    }

}

sub forward_to_new {

    my $this = shift;

    if (! $this->{count_new}){
        return;
    }

    if ($this->{index} < scalar(@{$this->{lines}}) - $this->{count_new}) {
        $this->{index} = scalar(@{$this->{lines}}) - $this->{count_new};

        return 1;
    }
}
