#!perl

use strict;
use warnings;
use utf8;

use lib qw(./lib);

use Test::More tests => 71;

BEGIN { use_ok('TestApp'); }

test_DBTransactionStack();
test_DBSnapshot();
test_DB();
test_App();
test_AppCaptureOutput();

done_testing();

exit 0;

###

sub test_DBTransactionStack {
    # given
    my @cases = (
        { command => 'push', params => ['a'], expected => { top => 'a', size => 1 }, testname => 'One'   },
        { command => 'push', params => ['b'], expected => { top => 'b', size => 2 }, testname => 'Two'   },
        { command => 'push', params => ['c'], expected => { top => 'c', size => 3 }, testname => 'Three' },
        { command => 'pop',  params => [],    expected => { top => 'b', size => 2 }, testname => 'Four'  },
        { command => 'pop',  params => [],    expected => { top => 'a', size => 1 }, testname => 'Five'  },
    );
    my $stack = new_ok('DBTransactionStack');

    foreach my $case (@cases) {
        my $tested_command = $case->{command};
        # when
        $stack->$tested_command(@{$case->{params}});
        # then
        while (my ($check_command, $expected_result) = each(%{$case->{expected}})) {
            my $testname = "DBTransactionStack: $case->{testname}";
            ok($stack->$check_command eq $expected_result, $testname);
        }
    }
}

sub test_DBSnapshot {
    # given
    my @cases = (
        { command => 'get',    params => ['a'],      expected => undef,      testname => 'One'    },
        { command => 'set',    params => ['a' => 8], expected => undef,      testname => 'Two'    },
        { command => 'get',    params => ['a'],      expected => '8',        testname => 'Three'  },
        { command => 'find',   params => ['4'],      expected => [],         testname => 'Four'   },
        { command => 'find',   params => ['8'],      expected => ['a'],      testname => 'Five'   },
        { command => 'set',    params => ['b' => 8], expected => undef,      testname => 'Six'    },
        { command => 'find',   params => ['8'],      expected => ['a', 'b'], testname => 'Seven'  },
        { command => 'counts', params => ['8'],      expected => '2',        testname => 'Eight'  },
        { command => 'unset',  params => ['b'],      expected => undef,      testname => 'Nine'   },
        { command => 'find',   params => ['8'],      expected => ['a'],      testname => 'Ten'    },
        { command => 'get',    params => ['b'],      expected => undef,      testname => 'Eleven' },
        { command => 'counts', params => ['8'],      expected => '1',        testname => 'Twelve' },
    );
    my $snapshot = new_ok('DBSnapshot');

    foreach my $case (@cases) {
        my $testname = "DBSnapshot: $case->{testname}";
        my $tested_command = $case->{command};
        # when
        my $got = $snapshot->$tested_command(@{$case->{params}});
        # then
        my $ok;
        if (ref $case->{expected} eq 'ARRAY') {
            $ok = is_deeply([sort @$got], $case->{expected});
        } else {
            $ok = is_deeply([$got], [$case->{expected}]);
        }
        $ok || diag explain $got, $testname;
    }
}

sub test_DB {
    # given
    my @cases = (
        { command => 'get',      params => ['a'],         expected => 'NULL',      testname => 'One'         },
        { command => 'set',      params => ['a' => '10'], expected => undef,       testname => 'Two'         },
        { command => 'find',     params => ['10'],        expected => ['a'],       testname => 'Three'       },
        { command => 'counts',   params => ['10'],        expected => '1',         testname => 'Four'        },
        { command => 'set',      params => ['b' => '10'], expected => undef,       testname => 'Five'        },
        { command => 'begin',    params => [],            expected => undef,       testname => 'Six'         },
        { command => 'get',      params => ['a'],         expected => '10',        testname => 'Seven'       },
        { command => 'set',      params => ['c' => '20'], expected => undef,       testname => 'Eight'       },
        { command => 'unset',    params => ['a'],         expected => undef,       testname => 'Nine'        },
        { command => 'get',      params => ['a'],         expected => 'NULL',      testname => 'Ten'         },
        { command => 'find',     params => ['10'],        expected => ['b'],       testname => 'Eleven'      },
        { command => 'counts',   params => ['10'],        expected => '1',         testname => 'Twelve'      },
        { command => 'rollback', params => [],            expected => undef,       testname => 'Thirteen'    },
        { command => 'get',      params => ['a'],         expected => '10',        testname => 'Fourteen'    },
        { command => 'find',     params => ['10'],        expected => ['a', 'b'],  testname => 'Fiveteen'    },
        { command => 'counts',   params => ['10'],        expected => '2',         testname => 'Sixteen'     },
        { command => 'find',     params => ['20'],        expected => [],          testname => 'Seventeen'   },
        { command => 'get',      params => ['c'],         expected => 'NULL',      testname => 'Nineteen'    },
        { command => 'begin',    params => [],            expected => undef,       testname => 'Twenty'      },
        { command => 'set',      params => ['d' => '30'], expected => undef,       testname => 'TwentyOne'   },
        { command => 'set',      params => ['e' => '42'], expected => undef,       testname => 'TwentyTwo'   },
        { command => 'unset',    params => ['a'],         expected => undef,       testname => 'TwentyThree' },
        { command => 'find',     params => ['10'],        expected => ['b'],       testname => 'TwentyFour'  },
        { command => 'counts',   params => ['10'],        expected => '1',         testname => 'TwentyFive'  },
        { command => 'begin',    params => [],            expected => undef,       testname => 'TwentySix'   },
        { command => 'set',      params => ['f' => '42'], expected => undef,       testname => 'TwentySeven' },
        { command => 'get',      params => ['f'],         expected => '42',        testname => 'TwentyEight' },
        { command => 'commit',   params => [],            expected => undef,       testname => 'TwentyNine'  },
        { command => 'get',      params => ['f'],         expected => '42',        testname => 'Thirty'      },
        { command => 'commit',   params => [],            expected => undef,       testname => 'ThirtyOne'   },
        { command => 'get',      params => ['f'],         expected => '42',        testname => 'ThirtyTwo'   },
        { command => 'find',     params => ['10'],        expected => ['b'],       testname => 'ThirtyThree' },
        { command => 'counts',   params => ['10'],        expected => '1',         testname => 'ThirtyFour'  },
        { command => 'find',     params => ['42'],        expected => ['e', 'f'],  testname => 'ThirtyFive'  },
        { command => 'counts',   params => ['42'],        expected => '2',         testname => 'ThirtySix'   },
    );
    my $db = new_ok('DB');

    foreach my $case (@cases) {
        my $testname = "DB: $case->{testname}";
        my $tested_command = $case->{command};
        # when
        my $got = $db->$tested_command(@{$case->{params}});
        # then
        my $ok;
        if (ref $case->{expected} eq 'ARRAY') {
            $ok = is_deeply($got, $case->{expected});
        } else {
            $ok = is_deeply([$got], [$case->{expected}]);
        }
        $ok || diag explain $got, $testname;
    }
}

sub test_App {
    # given
    my @cases = (
        { command => 'parseUserInput', params => ['  GET   AA   '], expected => [qw(GET AA)],    testname => 'One'   },
        { command => 'parseUserInput', params => ['SET B   10  '],  expected => [qw(SET B 10)],  testname => 'Two'   },
        { command => 'parseUserInput', params => [' FIND 20'],      expected => [qw(FIND 20)],   testname => 'Three' },
        { command => 'parseUserInput', params => ['UNSET C'],       expected => [qw(UNSET C)],   testname => 'Four'  },
        { command => 'parseUserInput', params => ['COUNTS   30'],   expected => [qw(COUNTS 30)], testname => 'Five'  },
        { command => 'wantsToExit',    params => ['END'],           expected => [1],             testname => 'Six'   },
        { command => 'runOnce',        params => ['END'],           expected => [1, 0],          testname => 'Seven' },
    );
    my $app = new_ok('App');

    foreach my $case (@cases) {
        my $testname = "App: $case->{testname}";
        my $tested_command = $case->{command};
        # when
        my @got = $app->$tested_command(@{$case->{params}});
        # then
        is_deeply(\@got, $case->{expected}) || diag explain @got, $testname;
    }
}

sub test_AppCaptureOutput {
    local *STDOUT;
    open(STDOUT, '>', \my $captured_output) or die "Can't redirect STDOUT: $!";

    # given
    my @cases = (
        'BEGIN', 'SET A 10', 'BEGIN', 'SET A 20', 'BEGIN', 'SET A 30',
        'GET A', 'ROLLBACK', 'GET A', 'COMMIT', 'GET A'
    );
    my $app = new_ok('App');
    my $expected = "30\n20\n20\n";

    # when
    foreach my $case (@cases) {
        $app->runOnce($case);
    }

    # then
    ok($captured_output eq $expected);
}
