#!perl
use strict;
use warnings;
use List::MoreUtils qw/any/;

main();

sub main {
    opendir my $dh, "/proc" or die $!;
    my @pid_dirs = grep { m{^[1-9][0-9]*$} } readdir $dh;
    closedir $dh;

    my @program_infos;
    for my $pid (@pid_dirs) {
        my $program_info = read_program_status($pid);
        next unless defined $program_info;

        push @program_infos, $program_info;
    }

    my %pid_name;
    map { $pid_name{$_->{pid}} = $_->{name} } @program_infos;

    my %name_pid;
    map { $name_pid{$_->{name}} = $_->{pid} } @program_infos;

    my $ps_tree = {};
    my @parents;
    my @children;
    for my $program_info (@program_infos) {
        my $ppid = $program_info->{ppid};
	next if $ppid == 0;

        my $pid = $program_info->{pid};
        $ps_tree->{$ppid}->{$pid} = 1;
    }

    my @ppids = keys %{$ps_tree};
    construct_ps_tree($ps_tree, $ps_tree, \@ppids);

    my $name_tree = {};
    ps_tree_to_name_tree($ps_tree, $name_tree, \%pid_name);
    print_tree($name_tree, \%name_pid, 0);
}

sub ps_tree_to_name_tree {
    my ($ps_tree, $name_tree, $pid_name) = @_;

    for my $pid (keys $ps_tree) {
        my $name = $pid_name->{$pid} || '0';
        if (ref $ps_tree->{$pid} eq "HASH") {
            $name_tree->{$name} = {};
            ps_tree_to_name_tree($ps_tree->{$pid}, $name_tree->{$name}, $pid_name);
        } else {
            $name_tree->{$name} = 1;
        }
    }
}

sub construct_ps_tree {
    my ($ps_tree, $parent, $ppids) = @_;

    my @deleted_pids;
    for my $pid (keys %{$parent}) {
        next unless ref $parent->{$pid} eq 'HASH';
        for my $child_pid (keys %{$parent->{$pid}}) {
            if (any { $_ == $child_pid } @{$ppids}) {
                $parent->{$pid}->{$child_pid} = $ps_tree->{$child_pid};
                push @deleted_pids, $child_pid;
                my @children = keys %{$ps_tree->{$child_pid}};
                construct_ps_tree($ps_tree, $parent->{$pid}->{$child_pid}, \@children);
            }
        }
    }

    for my $deleted_pid (@deleted_pids) {
        delete $ps_tree->{$deleted_pid};
    }
}

sub print_tree {
    my ($name_tree, $name_pid, $indent_level) = @_;

    my $indent = "    " x $indent_level;
    for my $name (sort keys %{$name_tree}) {
        printf "%s%s(%s)\n", $indent, $name, $name_pid->{$name} || $name;
        if (ref $name_tree->{$name} eq 'HASH') {
            print_tree($name_tree->{$name}, $name_pid, $indent_level+1);
        }
    }
}

sub read_program_status {
    my $pid = shift;

    my %program_info;
    open my $fh, '<', "/proc/$pid/status" or return;
    while (defined(my $line = <$fh>)) {
        chomp $line;

        if ($line =~ m{^([^:]+):\s*(.+)$}) {
            $program_info{lc $1} = $2;
        }
    }
    close $fh;

    return \%program_info;
}
