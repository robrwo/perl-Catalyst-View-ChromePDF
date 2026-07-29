package Catalyst::View::ChromePDF;

use v5.24;

use Moose;
extends 'Catalyst::View';

use File::Spec;
use IO::File::WithPath;
use Log::Log4perl ':easy';
use MooseX::Aliases;
use Path::Tiny;
use Types::Common qw( Enum NonEmptySimpleStr );
use WWW::Mechanize::Chrome;

use namespace::autoclean;

use experimental qw( signatures try );

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
    is      => 'ro',
    default => 'TT',
);

=attr stash_key

It defaults to "pdf".

Note: for L<Catalyst::View::Wkhtmltopdf> compatability, use "wk".

=cut

has stash_key => (
    is      => 'ro',
    lazy    => 1,
    default => 'pdf',
);

=attr chrome_args

=cut

has chrome_args => (
    is      => 'ro',
    default => sub($self) { {} },
);

=attr format

This is the paper format. It defaults to C<undef>.

=attr page_size

This is an alias for L</format>.

=cut

my $PageSizes = Enum [ keys %WWW::Mechanize::Chrome::PaperFormats ];

has page_size => (
    is         => 'ro',
    isa        => $PageSizes,
    alias      => 'format',
    default    => 'a4',
);

=attr orientation

=cut

my $Orientations = Enum [qw( portrait landscape )];

has orientation => (
    is         => 'ro',
    isa        => $Orientations,
    default    => 'portrait',
);

=attr disposition

=cut

my $Dispositions = Enum[ qw( inline attachment ) ];

has 'disposition' => (
    is      => 'rw',
    isa     => $Dispositions,
    default => 'inline',
);

=attr filename

=cut

has 'filename' => (
    is      => 'rw',
    isa     => NonEmptySimpleStr,
    default => 'output.pdf',
);

=method process

=cut

sub process( $self, $c ) {

    my $args = $c->stash->{ $self->stash_key };

    $c->res->body( $self->render( $c, $args // { } ) );

    my $disposition = $Dispositions->assert_return( $args->{disposition} // $self->disposition );
    my $filename    = $args->{filename} // $self->filename;

    $c->res->header(
        "Content-Disposition" => "${disposition}; filename*=UTF-8''${filename}",
        "Content-Type" => "application/pdf",
    );

    return 1;
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
        $html = $c->view( $self->tt_view )->render( $c, $args->{template} );
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

    try {
        my $res = $mech->get_local( $file->stringify );

        if ( $res->is_success ) {

            my $out = Path::Tiny->tempfile(
                DIR    => $self->tmpdir,
                SUFFIX => ".pdf",
                UNLINK => 0,
            );

            my $res;

            my %opts = $self->_build_pdf_options( $c, $args );

            if ( $args->{send_filehandle} ) {

                $c->log->debug("Saving the PDF to ${out}");

                $mech->content_as_pdf( %opts, filename => $out->stringify );
                $res = IO::File::WithPath->new( $out, '<:raw' );

            }
            else {

                $res = $mech->content_as_pdf(%opts);

            }

            return $res;

        }

    }
    catch ($e) {

        $c->log->error("$e");
        $c->error("$e");

    }

    return 0;
}

=arg format

This is the format or paper size.

=arg page_size

This is the same as L</format>, but is added for compatability with L<Catalyst::View::Wkhtmltopodf>.

=arg paper_width

=arg paper_height

Specify the paper with and height as an alternative to specifying the L</format>.

These are in inches, as that is what L<WWW::Mechanize::Chrome> uses.

=arg orientation

=cut

sub _build_pdf_options( $self, $c, $args ) {

    my $size = $PageSizes->assert_return( $args->{page_size} // $args->{format} // $self->format );
    my ( $width, $height ) = map { $WWW::Mechanize::Chrome::PaperFormats{$size}{$_} } qw( width height );

    my $orientation = $Orientations->assert_return( $args->{orientation} // $self->orientation );
    if ( $orientation eq "landscape" ) {
        ( $width, $height ) = ( $height, $width );
    }

    my %opts = (
        paperWidth  => $args->{paper_width}  // $width,
        paperHeight => $args->{paper_height} // $height,
    );

    return %opts;
}

=head1 COMPATABILITY

=head2 Differences from Catalyst::View::Wkhtmltopdf

=over 4

=item *

C<orientation> must be lowercase, e.g. "portrait" instead of "Portrait".

=item *

L</stash_key> has a differemt default.

=back

=cut

__PACKAGE__->meta->make_immutable();
