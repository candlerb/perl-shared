package perfSONAR_PS::NPToolkit::WebService::Router;

use strict;
use warnings;
use JSON::XS;
use Carp qw( cluck confess );
use CGI qw( header );
use Data::Dumper;

sub new {
    my $that  = shift;
    my $class =ref($that) || $that;

    my %args = (
        debug                => 0,
        max_post_size        => 0,
        @_,
    );

    my $self = \%args;

    if (!defined $self->{cgi}) {
        $self->{cgi} = CGI->new();
    }
    if (!defined $self->{fh}) {
        $self->{fh} = \*STDOUT; 
    }
    
    #--- check for alternate output handle
    if (!defined $self->{'output_handle'}) {
        $self->{'output_handle'} = \*STDOUT;
    }

    #--- register builtin help method
    bless $self,$class;

    $self->set_format();

    #--- register the help method
    my $help_method = perfSONAR_PS::NPToolkit::WebService::Method->new(
        name   => "help",
        description  => "provide intropective documentation about registered methods",
        is_default      => 1,
        callback => \&help
        #callback => sub { $self->help(@_); }
    );
    #$help_method->add_parameter(
    #    name            => "method_name",
    #    pattern         => '^((\w+|\_)+)$',
    #    required        =>  0,
    #    description     => "optional method name, if provided will give details about this specific method",
    #);

    $self->add_method($help_method);


    return $self;

}

sub add_method {
    my ($self, $method) = @_;
    my $name = $method->{name};
    if (!exists($self->{methods}->{$name})) {
        $method->set_router($self);
        $self->{methods}->{ $name } = $method;                
        return 1;
    } else {
        return 0;
    }
}

sub help {
    my $method_ref = shift;
    my $route_ref = $method_ref->{router};

    my $results = [];
    my $methods = $route_ref->{methods};
    while ( my ($name, $method) = each %$methods) {
        push @$results, { 'name' => $name, 'description' => $method->{description}};
    }

    return {'methods' => $results};
}

sub set_format {
    my ($self, $format) = @_;
    if (lc($format) eq 'xml') {
        $self->{format} = 'xml';
        $self->{output_type} = 'application/xml';
        $self->{formatter} = \&format_xml;
    } else {
        $self->{format} = 'json';
        $self->{output_type} = 'application/json';
        $self->{formatter} = \&format_json;
    }
}

sub handle_request {
    my ($self) = @_;
    my $cgi = $self->{cgi};
    my $fh = $self->{fh};
    if ($cgi->param("method_name")) {
        my $param_name = $cgi->param("method_name");
        if ($cgi->param("format")) {
            $self->set_format($cgi->param("format"));
        }
        if (exists $self->{methods}->{$param_name}) {
            my $method = $self->{methods}->{$param_name};
            warn "using method name: " . Dumper $method;
            my $results = $method->handle_request($cgi, $fh);
            $self->_output_results($results);
        
        }
    } else {
        my $method = $self->_get_default_method();
        if ($method) {
            #warn "default method: " . Dumper $method;
            my $results = $method->handle_request($cgi, $fh);
            $self->_output_results($results);
        } else {    
            $self->_output_error("No method name specified and no default found.", 501);
        }
    }
    
}

sub _output_results {
    my ($self, $results) = @_;
    my $fh = $self->{fh};
    $self->_set_headers($results);
    my $formatter = $self->{formatter};
    print { $fh } &$formatter($results);
}

sub _output_error {
    my ($self, $error, $status) = @_;
    my $fh = $self->{fh};
    $self->{status} =  $status || 500;
    $self->_set_headers();
    my $formatter = $self->{formatter};
    print { $fh } &$formatter({'error' => $error });

}

sub _set_headers {
    my ($self, $results) = @_;
    my $fh = $self->{fh};
    print $fh header(
        -type => $self->{output_type},
        -expires => $self->{expires} || '-1d',
        -status => $self->{status} || '200'
        );
}

sub _get_default_method {
    my ($self) = @_;
    foreach my $name (keys %{$self->{methods}}) {
        my $method = $self->{methods}->{$name};
        return $method if $method->{is_default};
    }
    return;
}

sub format_json {
    my ($content) = @_;
    return encode_json($content);
}

sub format_xml {
    my ($content) = @_;
    return XML::Simple::XMLout($content);
}

1;


