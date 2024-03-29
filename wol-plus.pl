#!/usr/bin/perl -w
#
# $Id: wol-plus,v 1.0.0.1 2019/11/28 09:47:32 $
#

use strict;
use Net::hostent;
use Socket;
use Getopt::Std;
use vars qw($VERSION $opt_v $opt_h $opt_i $opt_p $opt_f);
$VERSION = '0.41';

my $DEFAULT_IP      = '255.255.255.255';
my $DEFAULT_PORT    = getservbyname('discard', 'udp');

#
# Process the command line
#

getopts("hvp:i:f:");

if ($opt_h) { usage(); exit(0); }
if ($opt_v) { print "wakeonlan version $VERSION\n"; exit(0); }
if (!$opt_f and !@ARGV) { usage(); exit(0); }
if ($opt_i) { $DEFAULT_IP = $opt_i; }		# override default value
if ($opt_p) { $DEFAULT_PORT = $opt_p; }		# override default value

if ($opt_f) { process_file($opt_f); }

# The rest of the command line is a list of hardware addresses 

foreach (@ARGV) {
	wake($_, $opt_i, $opt_p);
} 

#
# wake
#
# The 'magic packet' consists of 6 times 0xFF followed by 16 times
# the hardware address of the NIC. This sequence can be encapsulated
# in any kind of packet, in this case an UDP packet targeted at the
# discard port (9).
#                                                                               

sub wake
{
	my $host    = shift;
	my $ipaddr  = shift || $DEFAULT_IP;
	my $port    = shift || $DEFAULT_PORT;

	my ($raddr, $them, $proto);
	my ($hwaddr, $hwaddr_re, $pkt);
	
	# get the hardware address (ethernet address)

	$hwaddr_re = join(':', ('[0-9A-Fa-f]{1,2}') x 6);
	if ($host =~ m/^$hwaddr_re$/) {
		$hwaddr = $host;
	} else {
		# $host is not a hardware address, try to resolve it
		my $ip_re = join('\.', ('([0-9]|[1-9][0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5]))') x 4);
		my $ip_addr;
		if ($host =~ m/^$ip_re$/) {
			$ip_addr = $host;
		} else {
			my $h;
			unless ($h = gethost($host)) {
				warn "$host is not a hardware address and I could not resolve it as to an IP address.\n";
				return undef;
			}
			$ip_addr = inet_ntoa($h->addr);
		}
		# look up ip in /etc/ethers
		unless (open (ETHERS, '<', '/etc/ethers')) {
			warn "$host is not a hardware address and I could not open /etc/ethers.\n";
			return undef;
		}
		while (<ETHERS>) {
			if (($_ !~ m/^$/) && ($_ !~ m/^#/)) { # ignore comments
				my ($mac, $ip);
				($mac, $ip) = split(' ', $_, 3);
				if ($ip =~ m/^$ip$/) {
					if ($ip eq $ip_addr or $ip eq $host) {
						$hwaddr = $mac;
						last;
					}
					next;
				} else {
					my $h2;
					unless ($h2 = gethost($ip)) {
						next;
					}
					if (inet_ntoa($h2->addr) eq $ip_addr) {
						$hwaddr = $mac;
						last;
					}
				}
			}
		}
		close (ETHERS);
		unless (defined($hwaddr)) {
			warn "Could not find $host in /etc/ethers\n";
			return undef;
		}
	}

	# Generate magic sequence

	foreach (split /:/, $hwaddr) {
		$pkt .= chr(hex($_));
	}
	$pkt = chr(0xFF) x 6 . $pkt x 16;

	# Allocate socket and send packet

	$raddr = gethostbyname($ipaddr)->addr;
	$them = pack_sockaddr_in($port, $raddr);
	$proto = getprotobyname('udp');

	socket(S, AF_INET, SOCK_DGRAM, $proto) or die "socket : $!";
	setsockopt(S, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";

	print "Sending magic packet to $ipaddr:$port with $hwaddr\n";

	send(S, $pkt, 0, $them) or die "send : $!";
	close S;
}

#
# process_file
#

sub process_file {
	my $filename = shift;
	my ($hwaddr, $ipaddr, $port);

	open (F, "<$filename") or die "open : $!";
	while(<F>) {
		next if /^\s*#/;		# ignore comments
		next if /^\s*$/;		# ignore empty lines

		chomp;
		($hwaddr, $ipaddr, $port) = split;

		wake($hwaddr, $ipaddr, $port);
	}
	close F;
}


#
# Usage
#

sub usage {
print <<__USAGE__;
Usage
    wakeonlan [-h] [-v] [-i IP_address] [-p port] [-f file] [[hardware_address] ...]

Options
    -h
        this information
    -v
        displays the script version
    -i ip_address
        set the destination IP address
        default: 255.255.255.255 (the limited broadcast address)
    -p port
        set the destination port
        default: 9 (the discard port)
    -f file 
        uses file as a source of hardware addresses

See also
    wakeonlan(1)    

__USAGE__
}


__END__

