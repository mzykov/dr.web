package App;

use strict;
use warnings;
use utf8;

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

    return $self->gracefulReturn($exit_code);
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

sub gracefulReturn {
    my ($self, $code) = @_;
    print "\n";
    return $code;
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

    if (ref $res eq 'ARRAY') {
        print(join(", ", @$res), "\n") if @$res;
    }
    elsif (!ref $res) {
        print $res, "\n";
    }
    else {
        warn "Unsupported result format\n";
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

use strict;
use warnings;
use utf8;

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

    my $top = $self->stack->top;
    my $val = $top->get($var);

    unless (defined $val) {
        return 'NULL';
    }

    return $val;
}

sub set {
    my ($self, $var, $val) = @_;

    my $top = $self->stack->top;
    $top->set($var, $val);

    return undef;
}

sub unset {
    my ($self, $var) = @_;

    my $top = $self->stack->top;
    $top->unset($var);

    return undef;
}

sub find {
    my ($self, $val) = @_;

    my $top = $self->stack->top;
    my $names = $top->find($val);

    # Используем сортировку, чтобы результат был детерминированным
    return [ sort(@$names) ];
}

sub counts {
    my ($self, $val) = @_;
    my $top = $self->stack->top;
    return $top->counts($val) // 0;
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

    my $top = $self->stack->top;
    $self->stack->pop; # Срезаем текущий
    $self->stack->pop; # И предыдущий
    $self->stack->push($top);

    return undef;
}

sub makeSnapshot {
    my ($self) = @_;
    return DBSnapshot->new($self->stack->top);
}

1;

package DBSnapshot;

use strict;
use warnings;
use utf8;

sub new {
    my ($class, $other) = @_;

    my $self = {
        variables => {},
        values    => {},
    };

    if ($other) {
        $self->{variables} = { %{$other->variables}   };
        $self->{values}    = { %{$other->values} };
    }

    return bless($self, $class);
}

sub variables { shift->{variables} }
sub values    { shift->{values}    }

sub get {
    my ($self, $var) = @_;

    my $v = $self->variables;

    if (exists $v->{$var} && defined $v->{$var}) {
        return $v->{$var};
    } else {
        return undef;
    }
}

sub set {
    my ($self, $var, $val) = @_;

    my $v = $self->variables;
    my $c = $self->values;

    if (exists $v->{$var} && defined $v->{$var}) {
        my $old_val = $v->{$var};
        $c->{$old_val}--;

        if ($c->{$old_val} <= 0) {
            $c->{$old_val} = undef;
        }
    }

    $v->{$var} = $val;
    $c->{$val}++ if defined $val;

    return undef;
}

sub unset {
    my ($self, $var) = @_;
    return $self->set($var, undef);
}

sub find {
    my ($self, $val) = @_;

    my $v = $self->variables;
    my @names = grep { defined $v->{$_} && $v->{$_} eq $val } keys %$v;

    return \@names;
}

sub counts {
    my ($self, $val) = @_;

    my $c = $self->values;

    if (exists $c->{$val} && defined $c->{$val}) {
        return $c->{$val};
    }

    return undef;
}

1;

package DBTransactionStack;

use strict;
use warnings;
use utf8;

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
