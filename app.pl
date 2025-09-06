#!perl

use strict;
use warnings;
use utf8;

use lib qw(./lib);
use TestApp;

STDOUT->autoflush(1);

my $app = App->new;

exit $app->run;
