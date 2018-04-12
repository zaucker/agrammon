use v6;

class Agrammon::Model::Input {
    has Str $.name;
    has Str $.description;
    has     $.default-calc;
    has     $.default-gui;
    has Str $.type;         # XXX Should be something richer than Str
    has Str $.validator;    # XXX Should be something richer than Str
    #    has Str %.labels{Str};
    has  %.labels;
    has  %.enum;
    #    has Str %.units{Str};
        has  %.units;
    #    has Str %.help{Str};
    has %.help;
    has Str @.models;
    #    has Str @.options;     # XXX set correct type: array of arrays
    has @.options;     # XXX set correct type: array of arrays
    #    has Str @.optionsLang; # XXX set correct type: array of hashes
    has @.optionsLang; # XXX set correct type: array of hashes
    has Int $.order;

    submethod TWEAK(:$default_calc, :$default_gui) {
        with $default_calc {
            $!default-calc = val($_);
        }
        with $default_gui {
            $!default-gui = val($_);
        }
    }

    method as-hash {
        my $validator = $.validator;
        my %validator;
        if $validator {
            $validator = $validator ~ '';
            $validator ~~ /(.+)\((.+)\)/;
            my $name = $0 ~ '';
            my $args = $1;
            my @args = split(',', $args);
            %validator = %( name => $name, args => @args);
        }
        my %units = %!units;
        %units<de> = %!units<en> unless  %units<de>;
        %units<fr> = %!units<en> unless  %units<fr>;

        my @options;
        my @optionsLang;
        my %enums = %!enum;

        if %enums {

            for %enums.keys -> $name {
                my $label   = $name;
                $label      ~~ s:g/_/ /;
                my @opt     = [ $label, '', $name];
                my $optLang = %enums{$name};
                my @optLang = split("\n", $optLang);
                my %optLang;
                for @optLang -> $ol {
                    my ($l, $o) = split(/ \s* '=' \s* /, $ol);
#                    $l.=trim;
#                    $o.=trim;
                    $o ~~ s:g/_/ /;
                    %optLang{$l} = $o;
                }
                push @options,     @opt;
                push @optionsLang, %optLang;
            }
        }
        return %(
            defaults    => %(
                calc => $.default-calc,
                gui  => $.default-gui,
            ),
            enum        => %!enum,
            help        => %!help,
            labels      => %!labels,
            models      => @!models || @("all"),
            options     => @options,
            optionsLang => @optionsLang,
            order       => $!order // 500000,
            type        => $!type,
            units       => %units,
            variable    => $!name,
            validator   => %validator,
        )
    }
}
