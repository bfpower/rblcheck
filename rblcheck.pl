#! /usr/bin/perl

### Smart coders always use strict

### Smart coders also check CPAN to find out if some poor slob has already done
### The heavy lifting like say, writing a convenient Mail::RBL module
### For use in an RBL checking script

use strict;
use Mail::RBL;
use Getopt::Std;

### Just declaring some vars

my $host;
my $list;
my $addlist;
my $addhost;
my $junk;
my @rawhosts;
my @rawbl;
my @checklist;
my @hosts;

### Before we do anything check for unrecogzine flags on the commandline

foreach ("@ARGV") {
	if ("$_" =~ /\-.*/) {
		if ("$_" =~ /\-[^e|r|R|s|S|h|H|q]/) {
			print STDERR "unrecognized option\: $_\n";
			print STDERR "For help, use rblcheck \-h\n";
			exit 1;
		}
	}
}

### Pull in the cmdline flags

our $opt_e = '';
my $email;
our $opt_r = '';
my $rfile;
our $opt_R = '';
our $opt_s = '';
my $sfile;
our $opt_S = '';
our $opt_h = '';
our $opt_H = '';
our $opt_q = '';

getopts('Hhqe:R:S:r:s:');

### If the user sets the -h flag we'll dump help text and exit

$opt_h = "$opt_H" if ("$opt_H");

if ("$opt_h") {
	print "RBL check\n";
	print "\n";
	print "usage\: rblcheck \[\-q\] \[\-e email\] \[\-R single_rbl\] \[\-S server_IP\] [\-r rbl_list\] \[\-s server_list\]"; 
	print "\n";
	print "rblcheck will check the specified host(s) against a predetermined list of RBLS.\n";
	print "The default list of RBLs and hosts are looked for in \/etc\/rblcheck\/ in rbls.conf and hosts.conf, respectively.\n";
	print "Hosts and RBLs may also be provided as commandline options. \n";
	print "The \-R flag sets a single RBL to check, while the \-S sets a single server.\n";
	print "If the \-R or \-S flags are found the corresponding flag \-r or \-s will be ignored.\n";
	print "\-e sets the email address to send the report to.\n";
	print "\-q suppresses output to STDOUT.\n";
	print "\-h or \-H outputs this help text.\n";
	exit 255;
};


### -R allows a user to specify an rbl from the cmdline.
### We'll just push the arg onto the @checklist array now

push (@checklist, $opt_R) if $opt_R;

### -S is the same, but for hosts to check.

push (@hosts, $opt_S) if $opt_S;

### If a user sets the -r flag we want to use that as the rbl list
### Otherwise we default to /etc/rblcheck/rbls.conf

if ("$opt_r") {
	$rfile = $opt_r;
} else {
	$rfile = "\/etc\/rblcheck\/rbls.conf";
};

### If the -R flag isn't set, we're going to read $rfile into the 
### @rawbl array, so that we can clean it up.
### If the -R flag is set we're just going to ignore this whole process 
### and use the RBL specified

unless ("$opt_R") {
	open(LISTS, "<", "$rfile") or die "Can't open RBL list $rfile: $!\n";
		@rawbl = <LISTS>;
	close LISTS;

	### Users need to be able to comment the .conf files, which means we
	### need to strip out anything after a hash
	### We accomplish that with split, then we chomp to remove any newlines
	### And run it through a substitution to strip off any leading/trailing
	### whitespace, because Perl *still* doesn't have a trim function
	### In freaking 2014.
	### If there's anything left in the line after we're done, we'll keep it

	foreach (@rawbl) {
		($addlist, $junk) = split /#/, $_;
		chomp $addlist;
		$addlist =~ s/^\s+|\s+$//g;
		if ($addlist) {
			push @checklist, "$addlist";
		};
	};
};

### Same as above. Read hosts.conf into the @rawhosts array...

if ("$opt_s") {
	$sfile = $opt_s;
} else {
	$sfile = "\/etc\/rblcheck\/hosts.conf";
};
	
unless ("$opt_S") {
	open(HOSTS, "<", "$sfile") or die "Can't open host list $sfile: $!\n";
		@rawhosts = <HOSTS>;
	close HOSTS;

	### ...And strip out all the crap we don't want.
	
	foreach (@rawhosts) {
		($addhost, $junk) = split /#/, $_;
		chomp $addhost;
		$addhost =~ s/^\s+|\s+$//g;
		if ($addhost) {
			push @hosts, "$addhost";
		};
	};
};

### More vars. I like to sprinkle them throughout my code for added flavouring

my $results = '';
my $hostresult;
my @printlist = @checklist;

unless ("$opt_q") {
	print "Checking against the following RBLS:\n";
	### Output which RBLS we're checking against, three per line
	my $cols  = 3;
	my $max   = -1;

	$_ > $max && ($max = $_) for map {length} @printlist;

	while (@printlist) {
    		print join " " => map {sprintf "%-${max}s" => $_}
                           splice @printlist => 0, $cols;
    		print "\n";
	};

	print "\n\n\n";
};

### The Magic(TM). Iterate through each value of @hosts...

foreach (@hosts) {
	$host = $_;
	print "Checking $host...\n" unless ("$opt_q");	

	### Empty out $hostresult so we can use it

	$hostresult = '';

	### ... And then for each value of @host iterate through each 
    ### value of @checklist...

	foreach (@checklist) {

		### And check if the host is listed on that list. Ta-da!

		$list = new Mail::RBL("$_");
		if ($list->check($host)) {

			### This is where, if the host is listed, we grab the listing, along 
            ###with the optional TXT RR that gives more info

			my ($ip_result, $optional_info_txt) = $list->check($host);

			### We're adding what we found to $hostresult, to be used later

			$hostresult = "$hostresult $_ returned result $ip_result for $host";

			### We're also goint to output it unless -q is set

			print "$_\: $ip_result $optional_info_txt\n" unless ("$opt_q");
			
			### If the optional TXT RR exists, we're also going to include that.

			if ($optional_info_txt) {
				$hostresult =  "$hostresult and also said $optional_info_txt";
			};

			### ...And finally add a newline for readability

			$hostresult = "$hostresult\n";
		};
	};

	### Last step is we dump the contents of $hostresult (ie, any results 
    ### for this host) to a master $results string so we can start again
	unless ("$opt_q") {
		print "No result found.\n" unless ("$hostresult");
	};
	$results = "$results$hostresult";
};

### If we've gotten any results we need to email them. Open a  pipe 
### to /usr/bin/mail and dump the contents of $results into it.

if ($results) {
	if ("$opt_e") {
		open MAIL, "| /usr/bin/mail -s 'RBL Alert!' $opt_e" or die "Can't open pipe: $!";
		print MAIL $results;
		close MAIL;
	};
};
