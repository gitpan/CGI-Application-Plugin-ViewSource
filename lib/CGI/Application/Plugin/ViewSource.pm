package CGI::Application::Plugin::ViewSource;
use warnings;
use strict;
use Syntax::Highlight::Perl::Improved;

=head1 NAME

CGI::Application::Plugin::ViewSource - View the source of the running application

=head1 DEPRECATED

Please use L<CGI::Application::Plugin::ViewCode> instead.

=cut

our $VERSION = '0.02';
our $DEBUG = 0;

# DEFAULT_STYLES taken from Apache::Syntax::Highlight::Perl by Enrico Sorcinelli
our %DEFAULT_STYLES = (
    'Comment_Normal'    => 'color:#006699;font-style:italic;',
    'Comment_POD'       => 'color:#001144;font-style:italic;',
    'Directive'         => 'color:#339999;font-style:italic;',
    'Label'             => 'color:#993399;font-style:italic;',
    'Quote'             => 'color:#0000aa;',
    'String'            => 'color:#0000aa;',
    'Subroutine'        => 'color:#998800;',
    'Variable_Scalar'   => 'color:#008800;',
    'Variable_Array'    => 'color:#ff7700;',
    'Variable_Hash'     => 'color:#8800ff;',
    'Variable_Typeglob' => 'color:#ff0033;',
    'Whitespace'        => 'white-space: pre;',
    'Character'         => 'color:#880000;',
    'Keyword'           => 'color:#000000;',
    'Builtin_Operator'  => 'color:#330000;',
    'Builtin_Function'  => 'color:#000011;',
    'Operator'          => 'color:#000000;',
    'Bareword'          => 'color:#33AA33;',
    'Package'           => 'color:#990000;',
    'Number'            => 'color:#ff00ff;',
    'Symbol'            => 'color:#000000;',
    'CodeTerm'          => 'color:#000000;',
    'DATA'              => 'color:#000000;',
    'LineNumber'        => 'color:#BBBBBB;'
);

our %SUBSTITUTIONS = (
    '<'     => '&lt;', 
    '>'     => '&gt;', 
    '&'     => '&amp;',
);

=head1 SYNOPSIS

In you CGI::Application based class

    use CGI::Application::Plugin::ViewSource;

Then you can view your modules source as it's running by changing the url

    ?rm=view_source
    ?rm=view_source&line_no=1
    ?rm=view_source&module=CGI-Application

=head1 INTERFACE

This plugin works by adding an extra run mode named C<< view_source >> to the
application. By calling this run mode you can see the source of the running module
(by default) or you can specify which module you would like to view (see L<SECURITY>).

This extra run mode will accept the following arguments in the query string:

=over

=item module

The name of the module to view. By default it is the module currently being run. Also,
since colons (':') aren't simply typed into URL's, you can just substitute '-' for '::'.

    ?rm=view_source?module=My-Base-Class

=item highlight

Turn syntax highlighting (using L<Syntax::Highlight::Perl::Improved>) on or off. 
By default it is 1 (on).

=item line_no

Turn viewing of line numbers on or off. By default it is 1 (on).

=item pod

Turn viewing of pod on or off. By default it is 1 (on).

=back

=cut


use Apache::Reload;
sub import {
    my $caller = scalar(caller);
    warn("**** " . __PACKAGE__ . "::import called.\n") if $DEBUG;
    $caller->add_callback( init => \&_add_runmode );
}

sub _add_runmode {
    my $self = shift;
    $self->run_modes( view_source => \&_view_source );
}

sub _view_source {
    my $self = shift;
    my $query = $self->query;
    warn("**** " . __PACKAGE__ . "::_view_source called.\n") if $DEBUG;

    my %options;
    foreach my $opt qw(highlight line_no pod) {
        if( defined $query->param($opt) ) {
            $options{$opt} = $query->param($opt);
        } else {
            $options{$opt} = 1;
        }
    }
        
    # defaults
    $options{module} = $query->param('module') || ref($self);

    # get the file to be viewed
    my $module = $options{module};
    # change into file name
    $module =~ s/-|(::)/\//g;    # allow for :: or -
    $module .= '.pm';

    warn("*** using module $module.\n") if $DEBUG;
    my $file = $INC{$module};
    warn("*** using file $file.\n") if $DEBUG;

    # make sure the file exists
    if( $file && -e $file ) {
        my $IN;
        open($IN, $file) 
            or return _error("Could not open $file for reading! $!");
        my @lines= <$IN>;

        # if we aren't going to highlight then turn all colors/styles
        # into simple black
        my %styles = %DEFAULT_STYLES;
        my $style_sec = '';
        foreach my $style (keys %styles) {
            $styles{$style} = 'color:#000000;'
                if( !$options{highlight} );
            $style_sec .= ".$style { $styles{$style} }\n";
        }

        # now use Syntax::Highlight::Perl::Improved to do the work
        my $formatter = Syntax::Highlight::Perl::Improved->new();
        $formatter->define_substitution(%SUBSTITUTIONS);
        foreach my $style (keys %styles) {
            $formatter->set_format($style, [qq(<span class="$style">), qq(</span>)]);
        }
        @lines = $formatter->format_string(@lines);
        
        # if we want line numbers
        if( $options{line_no} ) {
            my $i = 1;
            @lines = map { 
                (qq(<span class="LineNumber">) . $i++ . qq(:</span>&nbsp;). $_) 
            } @lines;
        }

        # apply any other transformations necessary
        if( $options{highlight} || !$options{pod} ) {
            foreach my $line (@lines) {
                # if they don't want the pod
                if( !$options{pod} ) {
                    if( $line =~ /<span class="Comment_POD"/ ) {
                        $line = '';
                        next;
                    }
                }
                
                # if they are highlighting
                if( $options{highlight} ) {
                    if( $line =~ /<span class="Package">([^<]*)<\/span>/ ) {
                        my $package = $1;
                        my $link = $package;
                        $link =~ s/::/-/g;
                        $link = "?rm=view_source&amp;module=$package";
                        $line =~ s/<span class="Package">[^<]*<\/span>/<a class="Package" href="$link">$package<\/a>/;
                    }    
                }
            }
        }
        my $code = join('', @lines);

        return qq(
        <html>
        <head>
            <title>$module - View Source</title>
            <style>$style_sec</style>
        </head>
        <body>
            <pre>$code</pre>
        </body>
        </html>
        );
    } else {
        return _error("File $file does not exist!");
    }
}

sub _error {
    my $message = shift;
    return qq(
    <html>
      <head>
        <title>View Source Error!</title>
      </head>
      <body>
        <h1 style="color: red">Error!</h1>
        <strong>Sorry, but there was an error in your 
        request to view the source: 
        <blockquote><em>$message</em></blockquote>
      </body>
    </html>
    );
}

1;

__END__

=head1 SECURITY

This plugin is designed to be used for development only. Please do not use it in a
production system as it will allow anyone to see the source code for any loaded module.
Consider yourself warned.

=head1 AUTHOR

Michael Peters, C<< <mpeters@plusthree.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-cgi-application-plugin-viewsource@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Application-Plugin-ViewSource>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2005 Michael Peters, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

