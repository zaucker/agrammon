use v6;
use JSON::Fast;

use Agrammon::Inputs;

class Agrammon::DataSource::JSON {
    method load($simulation-name, $dataset-id, $json-data) {
        my %input-data = from-json $json-data;
        my $inputs = Agrammon::Inputs.new(:$simulation-name, :$dataset-id);
        for %input-data.kv -> $full-tax, $module-data {
            if $module-data ~~ Array {
                for @($module-data) {
                    my $instance = .<name>;
                    my $values   = .<values>;
                    for $values.kv -> $sub-tax, $instance-inputs {
                        for $instance-inputs.kv -> $var, $value {
                            $inputs.add-multi-input(
                                $full-tax, $instance, $sub-tax,
                                $var, $value
                            );
                        }
                    }
                }
            }
            else {
                for $module-data.kv -> $var, $value {
                    $inputs.add-single-input($full-tax, $var, $value);
                }
            }
        }
        return $inputs;
    }
}

# JSON input expected
# {
#     "Application::Slurry::Cfermented": {
#       "fermented_slurry": 20
#     },
#     "Application::Slurry::Applrate": {
#       "dilution_parts_water": 1.0000,
#       "appl_rate": 20
#     },
#     "Application::Slurry::Ctech": {
#       "share_trailing_shoe": 20,
#       "share_trailing_hose": 20,
#       "share_splash_plate": 40,
#       "share_shallow_injection": 10,
#       "share_deep_injection": 10
#     },
#     "PlantProduction::MineralFertiliser": {
#       "mineral_fertiliser_ammoniumNitrate_N_content": 50,
#       "soil_ph": "low",
#       "mineral_fertiliser_ammoniumNitrate_amount": 1500
#     },
#     "Application::SolidManure::Cseason": {
#       "appl_autumn_winter_spring": 70,
#       "appl_summer": 30
#     },
#     "PlantProduction::RecyclingFertiliser": {
#       "compost": 10,
#       "solid_digestate": 10,
#       "liquid_digestate": 10
#     },
#     "Application::Slurry::CfreeFactor": {
#       "free_correction_factor": 5
#     },
#     "Storage::SolidManure::Solid": {
#       "share_applied_direct_pig_manure": 20,
#       "share_covered_basin_pig_manure": 20,
#       "share_applied_direct_cattle_other_manure": 20,
#       "share_covered_basin_cattle_manure": 20
#     },
#     "Application::SolidManure::CfreeFactor": {
#       "free_correction_factor": -5
#     },
#     "Storage::SolidManure::Poultry": {
#       "share_covered_basin": 20,
#       "share_applied_direct_poultry_manure": 20
#     },
#     "Application::Slurry::Cseason": {
#       "appl_autumn_winter_spring": 70,
#       "appl_summer": 30
#     },
#     "Application::Slurry::Csoft": {
#       "appl_evening": 20,
#       "appl_hotdays": "frequently"
#     },
#     "Application::SolidManure::CincorpTime": {
#       "incorp_lw8h": 10,
#       "incorp_lw1h": 10,
#       "incorp_gt3d": 10,
#       "incorp_lw1d": 10,
#       "incorp_none": 40,
#       "incorp_lw4h": 10,
#       "incorp_lw3d": 10
#     },
#     "Livestock::DairyCow": [
#         {
#             "name": "DC_Ex1",
#             "values": {
#                 "Housing::Floor": {
#                     "mitigation_housing_floor": "raised_feeding_stands"
#                 },
#                 "Excretion::CConcentrates": {
#                     "amount_winter": 0,
#                     "amount_summer": 0
#                 },
#                 "Excretion": {
#                     "dimensioning_barn": 0,
#                     "animals": 10,
#                     "animalcategory": "dairy_cows"
#                 },
#                 "Excretion::CFeedWinterRatio": {
#                     "share_beets_winter": 100,
#                     "share_grass_silage_winter": 100,
#                     "share_maize_pellets_winter": 100,
#                     "share_potatoes_winter": 100,
#                     "share_maize_silage_winter": 100
#                 },
#                 "Housing::Type": {
#                     "housing_type": "Loose_Housing_Slurry"
#                 },
#                 "Outdoor": {
#                     "grazing_days": 0,
#                     "exercise_yard": "not_available",
#                     "grazing_hours": 0,
#                     "yard_days": 270,
#                     "floor_properties_exercise_yard": "solid_floor"
#                 },
#                 "Excretion::CFeedSummerRatio": {
#                     "share_maize_pellets_summer": 100,
#                     "share_maize_silage_summer": 100,
#                     "share_hay_summer": 100
#                 },
#                 "Housing::CFreeFactor": {
#                     "free_correction_factor": 5
#                 },
#                 "Excretion::CMilk": {
#                     "milk_yield": 1000
#                 }
#             }
#         }
#     ],
#     "Storage::Slurry": [
#         {
#             "name": "Store Liquid 1",
#             "values": {
#                 "EFLiquid": {
#                     "contains_cattle_manure": "yes",
#                     "contains_pig_manure": "no",
#                     "cover_type": "solid_cover"
#                 },
#                 "": {
#                     "mixing_frequency": "7_to_12_times_per_year",
#                     "volume": 100,
#                     "depth": 4
#                 }
#             }
#         }
#     ]
# }
