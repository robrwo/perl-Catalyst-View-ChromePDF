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

=attr tmpdir

=cut

has tmpdir => (
    is         => 'ro',
    lazy_build => 1,
    builder    => '_build_tmpdir',
);

sub _build_tmpdir($self) {
    return File::Spec->tmpdir;
}

=attr tt_view

=cut

has tt_view => (
    is      => 'rw',
    lazy    => 1,
    default => 'TT',
);

=attr stash_key

It defaults to "pdf".

Note: for L<Catalyst::View::Wkhtmltopdf> compatability, use "wk".

=cut

has stash_key => (
    is      => 'rw',
    lazy    => 1,
    default => 'pdf',
);

=attr chrome_args

=cut

has chrome_args => (
    is      => 'ro',
    default => sub($self) { {} },
);

=method process

=cut

sub process( $self, $c ) {

    my $args = $c->stash->{ $self->stash_key };

    $c->res->body( $self->render( $c, $args // { } ) );

    $c->res->header(
        "Content-Type" => "application/pdf",
        );
}

=method render

=arg template

=arg html

=arg mech

This is a L<WWW::Mechanize::Chrome> instance.

If omitted, a new instance will be created and then closed, usinbg the L</chrome_args>.

=arg send_filehandle

=cut

sub render( $self, $c, $args ) {

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

        my $out = Path::Tiny->tempfile(
            DIR    => $self->tmpdir,
            SUFFIX => ".pdf",
            UNLINK => 0,               # FIXME
        );

        my $res;

        my %opts = $self->_build_pdf_options( $c, $args );

        if ( $args->{send_filehandle} ) {

            $c->log->debug("Saving the PDF to ${out}");

            $mech->content_as_pdf( %opts, filename => $out->stringify );
            $res = IO::File::WithPath->new( $out, '<:raw' );

        }
        else {

            $res = $mech->content_as_pdf( %opts );

        }

        $mech->close unless $args->{mech};

        return $res;

    }

    $mech->close unless $args->{mech};

    die "FIXME";
}

=arg format

This is the format or page size.

=arg page_size

This is the same as L</format>, but is added for compatability with L<Catalyst::View::Wkhtmltopodf>.

=arg paper_width

=arg paper_height

Specify the paper with and height as an alternative to specifying the L</format>.

=cut

sub _build_pdf_options( $self, $c, $args ) {

    my %opts;

    if ( $args->{page_size} ) { # for compatability with Catalyst::View::Wkhtmltopdf
        $opts{format} = $args->{page_size};
    }
    elsif ( $args->{format} ) {
        $opts{format} = $args->{format};
    }
    elsif ( $args->{paper_width} && $args->{paper_height} ) {
        $opts{paperWidth}  = $args->{paper_width};
        $opts{paperHeight} = $args->{paper_height};
    }

    return %opts;
}

=head1 COMPATABILITY

=head2 Catalyst::View::Wkhtmltopdf

There are some differences with L<Catalyst::View::Wkhtmltopdf>:

=over 4

=item *

C<orientation> is not supported.

=item *

L</stash_key> has a different default.

=back


=cut

__PACKAGE__->meta->make_immutable();
