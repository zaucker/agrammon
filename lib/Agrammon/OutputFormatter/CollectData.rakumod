use v6;
use Agrammon::Model;
use Agrammon::Outputs;
use Agrammon::Outputs::FilterGroupCollection;
use Agrammon::OutputFormatter::Util;

sub collect-data(
    Agrammon::Model $model,
    Agrammon::Outputs $outputs, Agrammon::Inputs $inputs, $reports,
    Str $language, Int $report-selected,
    Bool $include-filters, Bool $all-filters
) is export {

    # add inputs
    my @inputs;
    for $model.annotate-inputs($inputs) -> $ai {
        my $gui-translated = $ai.gui-root{$language} // 'NO GUI ROOT';
        my $value = $ai.value;
        my $value-translated = $value;
        if $value and $ai.input.enum {
            $value-translated = $ai.input.enum{$value}{$language} // $value;
        }
        @inputs.push( %(
            :module($ai.module.taxonomy),
            :instance($ai.instance-id // ''),
            :input($ai.input.name),
            :input-translated($ai.input.labels{$language} // $ai.input.labels<en> // $ai.input.name),
            :$value,
            :$value-translated,
            :unit($ai.input.units{$language} // $ai.input.units<en> // ''),
            :$gui-translated,
            :gui($ai.gui-root{'raw'}),
        ));
    }

    my @prints = $reports[$report-selected]<data> if defined $report-selected;
    my %print-labels;
    my @print-set;
    for @prints -> @print {
        for @print -> $print {
            @print-set.push($print<print>);
            %print-labels{$print<print>} = $print<langLabels>;
        }
    }
    # add outputs
    my @outputs = ();
    my $last-order = -1;
    for sorted-kv($outputs.get-outputs-hash) -> $module, $_ {
        when Hash {
            for sorted-kv($_) -> $output, $raw-value {
                next unless $model.should-print($module, $output, @print-set);

                my $value = flat-value($raw-value // 'UNDEFINED');
                my $var-print = $model.output-print($module, $output);
                my $print = ($var-print.split(',') ∩ @print-set).keys[0];
                my $order = $model.output-labels($module, $output)<sort> || $last-order;
                my $unit  = $model.output-unit($module, $output, $language);
                my $output-label = $language ?? $model.output-labels($module, $output){$language} !! $output;
                my $unit-label   = $language ?? $model.output-units($module, $output){$language}  !! $unit;
                @outputs.push(%( :module(''), :label($output-label), :$value, :unit($unit-label), :$order, :$print));
                if $include-filters {
                    if $raw-value ~~ Agrammon::Outputs::FilterGroupCollection && $raw-value.has-filters {
                        add-filters(
                            @outputs, $module, $model, $raw-value, $unit, $language, $order,
                            :$all-filters
                        );
                    }
                }
                $last-order = $order;
            }
        }
        when Array {
            for sorted-kv($_) -> $instance-id, %instance-outputs {
                for sorted-kv(%instance-outputs) -> $fq-name, %values {
                    my $q-name = module-with-instance($module, $instance-id, $fq-name);
                    for sorted-kv(%values) -> $output, $raw-value {
                        next unless $model.should-print($module, $output, @print-set);

                        my $value = flat-value($raw-value // 'UNDEFINED');
                        my $var-print = $model.output-print($module, $output);
                        my $print = ($var-print.split(',') ∩ @print-set).keys[0];
                        my $order = $model.output-labels($module, $output)<sort> || $last-order;
                        my $unit  = $model.output-unit($module, $output, $language);
                        my $output-label = $language ?? $model.output-labels($module, $output){$language} !! $output;
                        my $unit-label   = $language ?? $model.output-units($module, $output){$language}  !! $unit;
                        @outputs.push(%( :module(''), :label($output-label), :$value, :unit($unit-label), :$order, :$print));
                        if $include-filters {
                            if $raw-value ~~ Agrammon::Outputs::FilterGroupCollection && $raw-value.has-filters {
                                add-filters(
                                    @outputs, $q-name, $model, $raw-value, $unit-label, $language, $order,
                                   :$all-filters
                                );
                            }
                        }
                        $last-order = $order;
                    }
                }
            }
        }
    }
    return %( :@inputs, :@outputs, :%print-labels );
}

sub add-filters(@records, $module, $model, Agrammon::Outputs::FilterGroupCollection $collection,
                   $unit, $language, $order, Bool :$all-filters) {
    my @results = $collection.results-by-filter-group(:all($all-filters));
    for @results {
        my %keyFilters := .key;
        my %filters    := translate-filter-keys($model, %keyFilters);
        my $value      := .value;
#        we might need the %label for multiple filter groups later
#        for %filters.kv -> %label, %enum {
        for %filters.values -> %enum {
            my $label = %enum{$language};
            @records.push( %( :$module, :label('....' ~ $label), :$value, :$unit, :$order) );
        }
    }
}
