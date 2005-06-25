use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'CGI::Application::Plugin::ViewSource',
    license             => 'perl',
    dist_author         => 'Michael Peters <mpeters@plusthree.com>',
    dist_version_from   => 'lib/CGI/Application/Plugin/ViewSource.pm',
    requires => {
        'Test::More'                        => 0,
        'CGI::Application'                  => 4.00,
        'Syntax::Highlight::Perl::Improved' => 1.0 
    },
    create_makefile_pl  => 'traditional',
);

$builder->create_build_script();
