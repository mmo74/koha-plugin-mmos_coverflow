package Koha::Plugin::de::mmo74::MMOsCoverFlow::Controller;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use C4::Context;
use Koha::Plugin::de::mmo74::MMOsCoverFlow;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json);
use Encode qw(encode_utf8);
use Template;

use Try::Tiny;

=head1 Koha::Plugin::de::mmo74::MMOsCoverFlow::Controller

A class implementing the controller code for CoverFlow requests

=head2 Class methods

=head3 get

Method that adds a new order from a GOBI request

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $report_id   = $c->validation->param('report_id');
    my $report_name = $c->validation->param('name');
    my $sql_params  = $c->validation->every_param('sql_params');

    return try {
        # We need this weird hack until the plugin subsystem is not CGI-oriented
        my $plugin   = Koha::Plugin::de::mmo74::MMOsCoverFlow->new();

        my $data = decode_json( encode_utf8(Koha::Plugin::de::mmo74::MMOsCoverFlow::get_report(
            {
                id         => $report_id,
                name       => $report_name,
                sql_params => $sql_params
            }
        )));

        my $no_image = $plugin->retrieve_data('custom_image')
        || "/api/v1/contrib/coverflow/static/artwork/NoImage.png";

        my $template = Template->new({INCLUDE_PATH => join(':',@INC)});
        my $content;
        my $params = {
            data        => $data,
            coverlinks  => $plugin->retrieve_data('coverlinks'),
            showtitle   => $plugin->retrieve_data('showtitle'),
            size_limit  => $plugin->retrieve_data('size_limit'),
            title_limit => $plugin->retrieve_data('title_limit'),
            use_coce    => $plugin->retrieve_data('use_coce'),
            no_image    => $no_image,
            CoceHost    => C4::Context->preference('CoceHost'),
            CoceProviders => C4::Context->preference('CoceProviders'),
            OPACURLOpenInNewWindow => C4::Context->preference('OPACURLOpenInNewWindow'),
        };
        $template->process( 'Koha/Plugin/de/mmo74/MMOsCoverFlow/report.tt',$params,\$content);

        return $c->render(
            status => 200,
            text   => $content
        );
    }
    catch {
        return $c->render(
            status  => 500,
            openapi => { error => "Unhandled exception ($_)" }
        );
    };
}

1;
