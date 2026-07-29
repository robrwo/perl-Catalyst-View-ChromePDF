package Catalyst::View::ChromePDF;

use v5.24;

use Moose;
extends 'Catalyst::View';

use File::Spec;
use IO::File::WithPath;
use Log::Log4perl ':easy';
use Path::Tiny;
use WWW::Mechanize::Chrome;

use namespace::autoclean;

use experimental qw( signatures );

Log::Log4perl->easy_init($WARN);

has tmpdir => (
    is         => 'ro',
    lazy_build => 1,
    builder    => '_build_tmpdir',
);

sub _build_tmpdir($self) {
    return File::Spec->tmpdir;
}

has tt_view => (
    is      => 'rw',
    lazy    => 1,
    default => 'TT',
);

has stash_key => (
    is      => 'rw',
    lazy    => 1,
    default => 'pdf',
);

has chrome_args => (
    is      => 'ro',
    default => sub($self) { {} },
);

sub process( $self, $c ) {

    my $args = $c->stash->{ $self->stash_key };

    $c->res->body( $self->render( $c, $args // { } ) );

    $c->res->header(
        "Content-Type" => "application/pdf",
        );
}

sub render( $self, $c, $args ) {

    $args->{template_args} ||= undef;

    my $html;
    if ( defined $args->{template} ) {
        $html = $c->view( $self->tt_view )->render( $c, $args->{template} ) or die;
    }
    else {
        $html = $args->{html};
    }
    die 'Void-input' unless defined $html;

    my $file = Path::Tiny->tempfile(
        DIR    => $self->tmpdir,
        SUFFIX => ".html",
        UNLINK => 1,
    );

    $c->log->debug("Saving the HTML to ${file}");
    $file->spew_raw($html);

    my $mech = $args->{mech} // WWW::Mechanize::Chrome->new(
        headless         => 1,
        separate_session => 1,
        $self->chrome_args->%*
    );

    my $res = $mech->get_local( $file->stringify );

    if ( $res->is_success ) {

        my $pdf = $mech->content_as_pdf;

        $mech->close unless $args->{mech};

        if ( $args->{send_filehandle} ) {

        my $out = Path::Tiny->tempfile(
            DIR    => $self->tmpdir,
            SUFFIX => ".pdf",
            UNLINK => 0,               # FIXME
        );

        $c->log->debug("Saving the PDF to ${out}");
        $out->spew_raw($pdf);

        return IO::File::WithPath->new( $out, '<:raw' );

        }
        else {

            return $pdf;

        }

    }

    $mech->close unless $args->{mech};

    die "FIXME";
}

__PACKAGE__->meta->make_immutable();
