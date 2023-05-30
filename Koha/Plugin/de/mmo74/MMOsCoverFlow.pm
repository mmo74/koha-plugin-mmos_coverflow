package Koha::Plugin::de::mmo74::mmosCoverFlow;

no warnings 'redefine';

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
use Template;

# This block allows us to load external modules stored within the plugin itself
# In this case it's Template::Plugin::Filter::Minify::JavaScript/CSS and deps
# cpanm --local-lib=. -f Template::Plugin::Filter::Minify::CSS from asssets dir
BEGIN {
    use Config;
    use C4::Context;

    my $pluginsdir = C4::Context->config('pluginsdir');
    my @pluginsdir = ref($pluginsdir) eq 'ARRAY' ? @$pluginsdir : $pluginsdir;
    my $plugin_libs = '/Koha/Plugin/de/mmo74/MMOsCoverFlow/lib/perl5';

    foreach my $plugin_dir (@pluginsdir){
        my $local_libs = "$plugin_dir/$plugin_libs";
        unshift( @INC, $local_libs );
        unshift( @INC, "$local_libs/$Config{archname}" );
    }
}

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Members;
use C4::Auth;
use C4::Reports::Guided qw( execute_query );;
use MARC::Record;
use C4::Koha qw(GetNormalizedISBN);
#use Koha::Caches; FIXME not actually being used and causes error in some version
use JSON;
use Business::ISBN;
use JavaScript::Minifier qw(minify);
use Koha::DateUtils qw(dt_from_string);


## Here we set our plugin version
our $VERSION = "0.9.0";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'CoverFlow plugin',
    author          => 'Kyle M Hall',
    description     => 'Convert a report into a coverflow style widget!',
    date_authored   => '2014-06-29',
    date_updated    => '1900-01-01',
    minimum_version => '19.05',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub run_report {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'report.tt' } );

    my $json = get_report( { cgi => $cgi } );
    my $data = from_json($json);
    my $no_image = $self->retrieve_data('custom_image') || "/api/v1/contrib/coverflow/static/artwork/NoImage.png";

    $template->param(
            'data'      => $data,
            coverlinks  => $self->retrieve_data('coverlinks'),
            showtitle   => $self->retrieve_data('showtitle'),
            size_limit  => $self->retrieve_data('size_limit'),
            title_limit => $self->retrieve_data('title_limit'),
            use_coce    => $self->retrieve_data('use_coce'),
            no_image    => $no_image,
            );

    print $cgi->header(
        {
            -type     => 'text/html',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

## If your tool is complicated enough to needs it's own setting/configuration
## you will want to add a 'configure' method to your plugin like so.
## Here I am throwing all the logic into the 'configure' method, but it could
## be split up like the 'report' method is.
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
                mapping => $self->retrieve_data('mapping'),
                coverlinks => $self->retrieve_data('coverlinks'),
                showtitle => $self->retrieve_data('showtitle'),
                custom_image => $self->retrieve_data('custom_image'),
                size_limit => $self->retrieve_data('size_limit'),
                title_limit => $self->retrieve_data('title_limit'),
                use_coce => $self->retrieve_data('use_coce'),
                isbn_flavor => $self->retrieve_data('isbn_flavor'),
                );


        print $cgi->header(
            {
                -type     => 'text/html',
                -charset  => 'UTF-8',
                -encoding => "UTF-8"
            }
        );
        print $template->output();
    }
    else {
        my $coverlinks = $cgi->param('coverlinks') ? 1:0;
        my $use_coce = $cgi->param('use_coce') ? 1:0;
        my $showtitle = $cgi->param('showtitle') ? 1:0;
        my $custom_image = $cgi->param('custom_image') // "";

        my $error = q{};
        my $yaml  = $cgi->param('mapping');
        if ( defined $yaml && $yaml =~ /\S/ ) {
            $yaml  .= "\n\n";
            my $mapping;
            if ( C4::Context->preference('Version') ge '20.120000' ) {
                eval { $mapping = YAML::XS::Load($yaml); };
            } else {
                eval { $mapping = YAML::Load($yaml); };
            }
            $error = $@;
            if ($error) {
                my $template =
                  $self->get_template( { file => 'configure.tt' } );
                $template->param(
                    error   => $error,
                    mapping => $self->retrieve_data('mapping'),
                );
                print $cgi->header(
                    {
                        -type     => 'text/html',
                        -charset  => 'UTF-8',
                        -encoding => "UTF-8"
                    }
                );
                print $template->output();
            } else {
                $self->update_coverflow_js($mapping, $custom_image);
            }
        } else {
            $self->update_coverflow_js("", "");
        }
        $self->store_data(
            {
                mapping            => $cgi->param('mapping') // " ",
                coverlinks         => $coverlinks,
                showtitle          => $showtitle,
                custom_image       => $custom_image,
                size_limit         => $cgi->param('size_limit') // undef,
                title_limit        => $cgi->param('title_limit') // undef,
                last_configured_by => C4::Context->userenv->{'number'},
                use_coce => $use_coce
            }
        );
        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $dt = dt_from_string();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );
    my $opacuserjs = C4::Context->preference('opacuserjs');
    my $orig_oujs = $opacuserjs;
    $opacuserjs =~ s/\/\* JS for Koha CoverFlow Plugin.*End of JS for Koha CoverFlow Plugin \*\///gs;
    C4::Context->set_preference( 'opacuserjs', $opacuserjs ) if $opacuserjs ne $orig_oujs;

    my $opacusercss = C4::Context->preference('opacusercss');
    my $orig_oucss = $opacusercss;
    $opacusercss =~ s/\/\* CSS for Koha CoverFlow Plugin.*End of CSS for Koha CoverFlow Plugin \*\///gs;
    C4::Context->set_preference( 'opacusercss', $opacusercss ) if $opacusercss ne $orig_oucss;

    my $mapping = $self->retrieve_data('mapping');
    my $custom_image = $self->retrieve_data('custom_image');
    if ( C4::Context->preference('Version') ge '20.120000' ) {
        eval { $mapping = YAML::XS::Load($mapping); };
    } else {
        eval { $mapping = YAML::Load($mapping); };
    }
    $self->update_coverflow_js( $mapping, $custom_image );

    return 1;

}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;
}

sub get_report {
    my ($params) = @_;

    my $report_id   = $params->{'id'};
    my $report_name = $params->{'name'};
    my $sql_params  = $params->{'sql_params'};
    my @sql_params;

    my $cgi = $params->{'cgi'};
    if ($cgi) {
        $report_id   ||= $cgi->param('id');
        $report_name ||= $cgi->param('name');
        @sql_params  = $cgi->multi_param('sql_params');
    }

    my $report_rec;
    if ( C4::Context->preference('Version') ge '18.110000' ) {
        require Koha::Reports;
        $report_rec = Koha::Reports->search(
            $report_name ? { 'name' => $report_name } : { 'id' => $report_id } );
        $report_rec = $report_rec->next->unblessed if $report_rec;
    } else {
        $report_rec = get_saved_report(
            $report_name ? { 'name' => $report_name } : { 'id' => $report_id } );
    }
    if ( !$report_rec ) { die "There is no such report.\n"; }

    #die "Sorry this report is not public\n" unless $report_rec->{public};

     $sql_params ||= \@sql_params;
     my $cache;#        = Koha::Caches->get_instance();
     my $cache_active;# = $cache->is_cache_active;
     my ( $cache_key, $json_text );
#    if ($cache_active) {
#        $cache_key =
#            "opac:report:"
#          . ( $report_name ? "name:$report_name" : "id:$report_id" )
#          . join( '-', @sql_params );
#        $json_text = $cache->get_from_cache($cache_key);
#    }

    unless ($json_text) {
        my $offset = 0;
        my $limit  = C4::Context->preference("SvcMaxReportRows") || 10;
        my $sql    = $report_rec->{savedsql};

        # convert SQL parameters to placeholders
        $sql =~ s/(<<.*?>>)/\?/g;

        my ( $sth, $errors );
        if ( C4::Context->preference('Version') ge '21.110500' ) {
            ( $sth, $errors ) = execute_query({
                sql => $sql,
                offset => $offset,
                limit => $limit,
                sql_params => $sql_params
            });
        } else {
            ( $sth, $errors ) = execute_query( $sql, $offset, $limit, $sql_params );
        }
        if ($sth) {
            my $lines;
            $lines = $sth->fetchall_arrayref( {} );
            map { $_->{isbn} = GetNormalizedISBN( $_->{isbn} ) } @$lines;
            $json_text = to_json($lines);

#            if ($cache_active) {
#                $cache->set_in_cache( $cache_key, $json_text,
#                    { expiry => $report_rec->{cache_expiry} } );
#            }
        }
        else {
            $json_text = to_json($errors);
        }
    }

    return $json_text;
}

sub opac_js {
    my ( $self ) = @_;
    my $coverflow_js = $self->retrieve_data('coverflow_js');
    return qq{
        <script src="/api/v1/contrib/coverflow/static/jquery-flipster/jquery.flipster.min.js"></script>
        <script>$coverflow_js</script>
    };
}

sub opac_head {
    my ( $self ) = @_;

    return q|
<link id='flipster-css' href='/api/v1/contrib/coverflow/static/jquery-flipster/jquery.flipster.min.css' type='text/css' rel='stylesheet' />
<style>
    /* CSS for Koha CoverFlow Plugin 
       This CSS was added automatically by installing the CoverFlow plugin
       Please do not modify */
    .coverflow {
        height:160px;
        margin-left:25px;
        width:850px;
    }

    .coverflow img,.coverflow .item {
        -moz-border-radius:10px;
        -moz-box-shadow:0 5px 5px #777;
        -o-border-radius:10px;
        -webkit-border-radius:10px;
        -webkit-box-shadow:0 5px 5px #777;
        border-radius:10px;
        box-shadow:0 5px 5px #777;
        height:100%;
        width:100%;
    }

    .itemTitle {
        padding-top:30px;
    }

    .coverflow .selectedItem {
        -moz-box-shadow:0 4px 10px #0071BC;
        -webkit-box-shadow:0 4px 10px #0071BC;
        border:1px solid #0071BC;
        box-shadow:0 4px 10px #0071BC;
    }
    /* End of CSS for Koha CoverFlow Plugin */
</style>
    |;
}

sub update_coverflow_js {
    my ($self, $mapping, $custom_image) = @_;

    my $pluginsdir = C4::Context->config('pluginsdir');
    my @pluginsdir = ref($pluginsdir) eq 'ARRAY' ? @$pluginsdir : $pluginsdir;
    my @plugindirs;
    foreach my $plugindir ( @pluginsdir ){
            $plugindir .= "/Koha/Plugin/de/mmo74/MMOsCoverFlow";
            push @plugindirs, $plugindir
    }
    my $template = Template->new({
        INCLUDE_PATH => \@plugindirs
    });

    foreach my $setting ( @{$mapping} ) {
        foreach my $param ( @{ $setting->{params} } ) {
            push @{ $setting->{sql_params} }, "sql_params=$param";
        }
    }

    my $coverflow_js;
    $template->process('opacuserjs.tt',{ mapping => $mapping, custom_image => $custom_image}, \$coverflow_js);
    $coverflow_js = minify( input => $coverflow_js );
    $self->store_data({ coverflow_js => $coverflow_js });

}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub static_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'coverflow';
}

1;
