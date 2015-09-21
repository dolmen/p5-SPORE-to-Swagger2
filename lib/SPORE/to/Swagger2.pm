use strict;
use warnings;
package SPORE::to::Swagger2;

use JSON::MaybeXS qw<JSON>;
use Carp ();

sub new
{
    my $class = shift;
    my $spore = shift;

    unless (ref($spore) eq 'HASH') {
	if (ref($spore) eq 'SCALAR') {
	    $spore = ${$spore};
	} elsif (ref($spore) eq '') {
	    $spore = do {
		open my $f, '<:encoding(UTF-8)', $spore;
		local $/;
		<$f>
	    }
	}

	$spore = JSON::MaybeXS::decode_json($spore)
    }

    bless { spore => $spore }, $class
}

sub spore { $_[0]->{spore} }

sub to_Swagger2
{
    my $self = shift;

    my $spore = $self->spore;

    my @version = split /\./, $spore->{version};
    my @url;
    if (my $base_url = $spore->{base_url}) {
	require URI;
	$base_url = URI->new($base_url);
	@url = (
	    host => $base_url->host_port,
	    schemes => [ $base_url->scheme ],
	    basePath => length($base_url->path) ? $base_url->path : '/',
	)
    }

    my %paths;
    my $sw2 = {
	swagger => '2.0',
	info => {
	    version => join('.', (@version, 0, 0)[0..2]),
	    title => $spore->{name},
	},
	@url,
	consumes => [ 'application/json' ],
	produces => [ 'application/json' ],
	paths => \%paths,
    };

    while (my ($name, $desc) = each %{$spore->{methods}}) {
	my %p;
	my $path = $desc->{path};
	my %path_params;
	my @params;
	$path =~ s/:([A-Za-z0-9]+)/
		push @params, {
		    name => $1,
		    in => 'path',
		    type => 'string',
		    required => JSON->true,
		};
		$path_params{$1}++;
		"{$1}" # Replacement
		/e;
	if (my $rp = $desc->{required_params}) {
	    push @params,
		map
		{
		    exists $path_params{$_}
		    ? ()
		    : +{
			name => $_,
			in => 'query',
			required => JSON->true,
			type => 'string',
		    }
		}
		@$rp
	}
	if (my $op = $desc->{optional_params}) {
	    push @params,
		map
		{
		    +{
			name => $_,
			in => 'query',
			required => JSON->false,
			type => 'string',
		    }
		}
		@$op
	}
	my @responses = map
	    {
		($_ => +{
		    description => ($_ < 400 ? 'Successful' : 'Error'),
		    # No schema equivalent in SPORE
		    schema => { type => 'object' },
		})
	    }
	    @{ $desc->{expected_status} // [ 200 ]};

	$p{parameters} = \@params;
	$paths{$path}{lc $desc->{method}} = {
	    summary => $desc->{description} // 'FIXME',
	    description => $desc->{documentation} // 'FIXME',
	    operationId => $name,
	    responses => +{
		map
		{
		    ($_ => +{
			description => ($_ < 400 ? 'Successful' : 'Error'),
			# No schema equivalent in SPORE
			schema => { type => 'object' },
		    })
		}
		@{ $desc->{expected_status} // [ 200 ]}
	    },
	    parameters => \@params,
	};
    }

    $sw2
}


1;
