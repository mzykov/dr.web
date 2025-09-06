#!perl

use strict;
use warnings;
use utf8;

STDOUT->autoflush(1);

my $app = App->new;
exit $app->run;

###

package App;

sub new {
    my ($class) = @_;
    return bless({ db => DB->new }, $class);
}

sub db { shift->{db} }
sub EXIT_CODE_SUCCESS { 0 }
sub EXIT_CODE_FAILURE { 1 }

sub run {
    my ($self) = @_;

    my $exit_code = $self->EXIT_CODE_SUCCESS;
    $self->welcome;

    while (my $str = <>) {
        chomp $str;

        if ($str) {
            my ($last, $code) = $self->runOnce($str);
            $exit_code = $code;
            last if $last;
        }

        $self->welcome;
    }

    $self->printResult("");

    return $exit_code;
}

sub runOnce {
    my ($self, $nonempty_str) = @_;

    my $db = $self->db;
    my ($last, $exit_code) = (0, $self->EXIT_CODE_SUCCESS);
    my ($cmd, $var, $val) = $self->parseUserInput($nonempty_str);

    if ($self->wantsToExit($cmd)) {
        $last = 1;
    }
    elsif ($db->commandSupported($cmd)) {
        my $method = $self->dbMethodNameByCmd($cmd);
        my $res = $db->$method($var, $val);

        unless ($self->printResult($res)) {
            $exit_code = $self->EXIT_CODE_FAILURE;
            $last = 1;
        }
    }
    else {
        warn "Unsupported input\n";
    }

    return ($last, $exit_code);
}

sub dbMethodNameByCmd {
    my ($self, $cmd) = @_;
    return lc($cmd);
}

sub parseUserInput {
    my ($self, $str) = @_;
    $str =~ s{^\s+|\s+$}{}g;
    return split(/\s+/, $str);
}

sub printResult {
    my ($self, $res) = @_;

    return 1 unless defined $res;
    my $EOL = "\n";

    if (ref $res eq 'ARRAY') {
        print(join(", ", @$res), $EOL) if @$res;
    }
    elsif (!ref $res) {
        print $res, $EOL;
    }
    else {
#        require Data::Dumper;
#        print STDERR Data::Dumper::Dumper([ res => $res ]);
        warn "Unsupported result format";
        return 0;
    }

    return 1;
}

sub wantsToExit {
    my ($self, $cmd) = @_;
    return $cmd eq 'END';
}

sub welcome {
    my ($self) = @_;
    print '> ';
    return 0;
}

1;

package DB;

sub new {
    my ($class) = @_;

    my $stack = DBTransactionStack->new;
    $stack->push(DBSnapshot->new);

    my $self = {
        stack => $stack,
    };

    return bless($self, $class);
}

sub stack { shift->{stack} }

sub commandSupported {
    my ($self, $cmd) = @_;
    my @commands = qw(GET SET UNSET COUNTS FIND BEGIN ROLLBACK COMMIT);
    return scalar grep { $_ eq $cmd } @commands;
}

sub get {
    my ($self, $var) = @_;

    my $v = $self->stack->top->data;

    if (exists $v->{$var} && defined $v->{$var}) {
        return $v->{$var};
    } else {
        return 'NULL';
    }
}

sub set {
    my ($self, $var, $val) = @_;

    my $v = $self->stack->top;
    $v->set($var, $val);

    return undef;
}

sub unset {
    my ($self, $var) = @_;

    my $v = $self->stack->top;
    $v->unset($var);

    return undef;
}

sub find {
    my ($self, $val) = @_;

    my $v = $self->stack->top->data;
    # Используем sort, чтобы результат был детерминированным
    my @names = sort grep { $v->{$_} eq $val } keys %$v;

    return \@names;
}

sub counts {
    my ($self, $val) = @_;
    my $v = $self->stack->top;
    return $v->counts->{$val} // 0;
}

sub begin {
    my ($self) = @_;
    $self->stack->push($self->makeSnapshot);
    return undef;
}

sub rollback {
    my ($self) = @_;

    if ($self->stack->size > 1) {
        $self->stack->pop;
    }

    return undef;
}

sub commit {
    my ($self) = @_;

    if ($self->stack->size < 2) {
        return undef;
    }

    my $commited = $self->stack->top;
    $self->stack->pop;
    $self->apply($commited->data);

    return undef;
}

sub apply {
    my ($self, $commited) = @_;

    while (my ($var, $val) = each(%$commited)) {
        $self->set($var, $val);
    }
}

sub makeSnapshot {
    my ($self) = @_;
    return DBSnapshot->new($self->stack->top);
}

1;

package DBSnapshot;

sub new {
    my ($class, $data) = @_;

    my $self = {
        variables => {},
        values    => {},
    };

    if ($data) {
        $self->{variables} = { %{$data->{variables}} };
        $self->{values}    = { %{$data->{values}} };
    }

    return bless($self, $class);
}

sub data   { shift->{variables} }
sub counts { shift->{values}    }

sub set {
    my ($self, $var, $val) = @_;

    $self->{variables}->{$var} = $val;
    $self->{values}->{$val}++;

    return undef;
}

sub unset {
    my ($self, $var) = @_;

    my $val = $self->{variables}->{$var};
    $self->{variables}->{$var} = undef;
    $self->{values}->{$val}--;

    if ($self->{values}->{$val} <= 0) {
        $self->{values}->{$val} = undef;
    }

    return undef;
}

1;

package DBTransactionStack;

sub new {
    my ($class) = @_;
    return bless({ snapshots => [] }, $class);
}

sub pop {
    my ($self) = @_;
    pop(@{$self->{snapshots}});
    return undef;
}

sub push {
    my ($self, $snapshot) = @_;
    push @{$self->{snapshots}}, $snapshot;
    return $snapshot;
}

sub size { scalar(@{shift->{snapshots}}) }

sub top { shift->{snapshots}->[-1] }

1;
