#!/usr/bin/env perl

use strict;

use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::DBus;

use JSON;
use Encode;

my $cv = AnyEvent->condvar;
my $list = MessageList->new;

sub get_msg_line {    
    my %data = @_;

    sprintf('%s: %s', $data{user}, $data{msg});
}

sub print_msg {
    print shift . "\n";
}

sub add_pidgin_msg {
    $list->add(get_msg_line(
        user => $_[1],
        msg  => $_[2],
    ));

    print_msg $list->get_next;
}

my $w; $w = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
     chomp (my $input = <STDIN>);
     
     print_msg $list->get_next;
});

my $bus     = Net::DBus->session;
my $service = $bus->get_service("im.pidgin.purple.PurpleService");
my $object  = $service->get_object("/im/pidgin/purple/PurpleObject");

$object->connect_to_signal('ReceivedChatMsg', \&add_pidgin_msg);
$object->connect_to_signal('ReceivedImMsg', \&add_pidgin_msg);

$cv->recv;

package MessageList;

use strict;

sub new {
    bless {
        lines => [],
        index => 0
    }, shift;
}

sub add {
    my ($this, $line) = @_;

    push @{$this->{lines}}, $line;
}

sub get_next {

    my $this = shift;

    if (! @{$this->{lines}}) {
        return;
    }

    if ($this->{index} == $#{$this->{lines}}) {
        $this->{index} = 0;
    } else {
        $this->{index}++;
    }

    return $this->{index}+1 . ' ' . $this->{lines}->[$this->{index}];
}
