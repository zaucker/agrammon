# Shitty Program - A Raku Christmas Tale

Quite a while ago, Santa got a feature request for a web application called [AGRAMMON](https://agrammon.ch/en), developed by the elves of one of his sub-contractors [Oetiker+Partner AG](https://www.oetiker.ch) in Perl 5. When Santa asked the [elf responsible](https://www.oetiker.ch/en/company/team/fz) for this application to get to work, the elf suggested that some refactoring was in order, as the application dated back almost 10 years and had been extended regularly. As the previous year had seen a real Christmas wonder, namely the release of Perl 6c, the elf suggested, that instead of bolting yet another feature onto the web application's Perl 5 backend, a rewrite in Perl 6 would be a bold but also appropriate move. The reason being that the application used a specially developed format for describing it's functionality by none-programmers. What better choice for rewriting the parser than Perl 6's grammars, the elf reasoned. Fittingly, the new AGRAMMON was going to be version 6.

When Santa asked when the rewrite would be finished, the obivous answer was "By Christmas". And as things went in Perl 6 land, by the time the rewrite is finally going into production, the backend is now implemented in Raku.

## AGRAMMON

While most people nowadays know about the negative side-effects of agriculture on climate, a lesser known, but also significant environmental problem are ammonia (NH3) and nitrous oxide (NxOx) emissions. Those emissions are a result of the excrements of farm animals, mainly from cows, pigs, and pultry. Both solid and liquid excrements contain ammonia compounds such as urea which are decomposing either on the farm grounds, storage, and application as fertilizer. In addition to being an environmental pollutant, those emissions are also a big loss of nitrogen (N) from those natural fertilizers that must be replaced by artificial ones. 

In order to address these problems, the processes of ammonia volatilisation are being studied, optimizations for its reductions developed, and the effects measured where possible under controlled conditions. However, as those controlled conditions don't exist on a large scale, the effects of the reduction measures as well as the total amount of emissions can only be simulated by model calculations. AGRAMMAN is a tool that facilitates such simulations on the scale of a single farm and can also used for calculations on regional scales by means of simulating "typical farm types" using average process types and cumulated numbers of animals, storage areas, and fertilizer application. The following picture shows the processes simulated in the model:

<p align="center"><img align="center" src="https://github.com/zaucker/agrammon/blob/Advent/Advent2020/N-model.jpg" /></p>
  

By now it might be obvious to the reader that this article's title is not mainly about code quality.

## The Application

AGRAMMON is a typical web application, with data stored in a PostgreSQL database, a web frontend implemented in JavaScript using the [Qooxdoo](https://qooxdoo.org), and the Raku backend. The physical and chemical processes are not directly implemented in the backend, but as already mentioned in a none-programmer-friendly custom "language", describing (user) inputs, model parameters, calculations, and outputs (results). Each process is broken down into smaller sub-processes and each is described in its own file, including documentation and references to appropriate scientific sources. Here is a small example for such a file:

```
*** general ***

author   = Agrammon Group
date     = 2008-03-30
taxonomy = Livestock::DairyCow::Excretion

+short

Computes the annual N excretion of a number of dairy cows as a function of the
milk yield and the feed ration.

+description

This process calculates the annual N excretion (total N and Nsol (urea plus
measured total ammoniacal nitrogen)) of a number of dairy cows as a
function of the milk yield and the supplied feed ration. Nitrogen
surpluses from increased nitrogen uptake are primarily excreted as
Nsol in the urine. Eighty percent of the increased N excretion is
therefore added to the Nsol fraction.

*** input parameters ***

+dairy_cows
  type        = integer
  validator = ge(0)
  ++labels
       en = Number of animals
       de = Anzahl Tiere 
       fr   = Nombre d'animaux
  ++units
      en = -
  ++description
       Number of dairy cows in barn.
  ++help
      +++en 
          <p>Actual number of animals
                in the barn.</p>
        +++de  ...
        +++fr    ...

*** technical parameters ***

+standard_N_excretion
   value = 115
  ++units 
      en = kg N/year
      de = kg N/Jahr
      fr   = kg N/an
  ++description
    Annual standard N excretion for a
    dairy cow according to
    Flisch et al. (2009).

*** external ***

+Excretion::CMilk
+Excretion::CFeed

*** output ***
+n_excretion
  print = 7

  ++units
      en = kg N/year
      de = kg N/Jahr
      fr   = kg N/an

  ++formula
        Tech(standard_N_excretion)
      * Val(cmilk_yield,    Excretion::CMilk)
      * Val(c_feed_ration,Excretion::CFeed)
      * In(dairy_cows);

  ++description
      Annual total N excreted by a specified
      number of animals.
```

In the current version of the AGRAMMON model there are 133 such files with 31,014 lines. From those, the backend can generate

* the PDF documentation of the model (allowing LaTeX formatting in the files)
* a description of the web GUI which can be rendered by the frontend
* the actual model simulation using the user's input data

The results are presented in the web GUI in tabular form (showing various subsets of the data that can also be defined in the model files) and can be exported as PDF report or Excel file, together with the actual inputs provided by the user.

A special instance of AGRAMMON is used by a [regional government agency](https://lawa.lu.ch/) in the evaluation process of the environmental impact of modifications to local farms and the approval of the respective building applications. For this, the ammonia emissions before and after the planned modifications must be simulated by the applicant and can be directly submitted to the agencies AGRAMMON account, including a notification of the agency by eMail with the PDF report attached.

## The Raku backend

The refactored backend as of today consists of 59 `.pm6` modules/packes with 6,942 lines and is covered by tests in 38 `.t` files with 5,854 lines. It uses the 13  Raku modules shown in the following excerpt of the [META6.json](../META6.json) file:
```
  "depends": [
    "Cro::HTTP",
    "Cro::HTTP::Session::Pg",
    "Cro::OpenAPI::RoutesFromDefinition",
    "Cro::WebApp::Template",
    "DB::Pg",
    "Digest::SHA1::Native",
    "Email::MIME",
    "LibXML:ver<0.5.10>",
    "Net::SMTP::Client::Async",
    "OO::Monitors",
    "Spreadsheet::XLSX:ver<0.2.1+>",
    "Text::CSV",
    "YAMLish"
  ],
  "build-depends": [],
  "test-depends": [
    "App::Prove6",
    "Cro::HTTP::Test",
    "Test::Mock",
    "Test::NoTabs"
  ],
```
Note that `Spreadsheet::XLSX` was specifically implemented for this project.

Speaking of the actual implementation, although our brave elf didn't have much experience with either grammars, parsers, or even Perl 6 / Raku, he was smart enough to engage a real [expert elf](https://www.edument.se/en/page/jonathan-worthington-eng) for that. This elf did most of the heavy lifting of the backend implementation and helped our elf with advice and code review for the parts he implemented himself. Please note that the goal of this rewrite was to leave most of the syntax of the model implementation and also the frontend as is, so the blame for all the sub-optimal design decisions are solely on our primary elf (as all the implementation details passing under the review radar).

## Raku features used in AGRAMMON

In this section you'll see a few Raku features used in AGRAMMON. This is not meant as a hardcore technical explanation for experts, but rather as a means to give a taste to people interested in Raku.

### [bin/agrammon.pl6](../bin/agrammon.pl6)

```
#!/usr/bin/env raku
use lib "lib"
use Agrammon::UI::CommandLine;
```
The acutal AGRAMMON "executable" is just a three-liner (of which only two are Raku). This exploits the fact that Rakudo (the Raku implementation used here) has a pretty nice pre-compilation feature which is useful for minimizing (the still not neglegible) startup time after the first run of the program.

### [Agrammon::UI::CommandLine]](../lib/Agrammon/UI/CommandLine.pm6)

#### Usage

Running `./bin/agrammon.pl6` gives the following output:
```console
Usage:
  ./bin/agrammon.pl6 web <cfg-filename> <model-filename> [<technical-file>] -- Start the web interface
  ./bin/agrammon.pl6 [--language=<SupportedLanguage>] [--prints=<Str>] [--variants=<Str>] [--include-filters] [--include-all-filters] [--batch=<Int>] [--degree=<Int>] [--max-runs=<Int>] [--format=<OutputFormat>] run <filename> <input> [<technical-file>] -- Run the model
  ./bin/agrammon.pl6 [--variants=<Str>] [--sort=<SortOrder>] dump <filename> -- Dump model
  ./bin/agrammon.pl6 [--variants=<Str>] [--sort=<SortOrder>] latex <filename> [<technical-file>]
  ./bin/agrammon.pl6 create-user <username> <firstname> <lastname> -- Create Agrammon user
    See https://www.agrammon.ch for more information about Agrammon.
```
This usage message is created automatically from the implementation of the `multi sub MAIN` instances as shown for the first line:
```
#| Start the web interface
multi sub MAIN('web', ExistingFile $cfg-filename, ExistingFile $model-filename, Str $technical-file?) is export {
    my $http = web($cfg-filename, $model-filename, $technical-file);
    react {
        whenever signal(SIGINT) {
            say "Shutting down...";
            $http.stop;
            done;
        }
    }
}
```

#### sub web() 

This subroutine is called to start the web service as shown in the first line of the above usage message (some lines for initialization omitted).

```
sub web(Str $cfg-filename, Str $model-filename, Str $technical-file?) is export {

    # initialization
    ...
    
    my $model = timed "Load model from $module-path/$module.nhd", {
        load-model-using-cache($*HOME.add('.agrammon'), $module-path, $module, preprocessor-options($variants));
    }

    my $db = DB::Pg.new(conninfo => $cfg.db-conninfo);
    PROCESS::<$AGRAMMON-DB-CONNECTION> = $db;

    my $ws = Agrammon::Web::Service.new(:$cfg, :$model, :%technical-parameters);

    # setup and start web server
    my $host = %*ENV<AGRAMMON_HOST> || '0.0.0.0';
    my $port = %*ENV<AGRAMMON_PORT> || 20000;
    my Cro::Service $http = Cro::HTTP::Server.new(
        :$host, :$port,
        application => routes($ws),
        after => [
            Cro::HTTP::Log::File.new(logs => $*OUT, errors => $*ERR)
        ],
        before => [
            Agrammon::Web::SessionStore.new(:$db)
        ]
    );
    $http.start;
    say "Listening at http://$host:$port";
    return $http;
}
```

#### sub run()

```
sub run (IO::Path $path, IO::Path $input-path, $technical-file, $variants, $format, $language, $prints,
         Bool $include-filters, $batch, $degree, $max-runs, :$all-filters) is export {
         
    ### initialization
    ...
    
    my $rc = Agrammon::ResultCollector.new;
    my atomicint $n = 0;
    my class X::EarlyFinish is Exception {}
    race for $ds.read($fh).race(:$batch, :$degree) -> $dataset {
        my $my-n = ++⚛$n;

        my $outputs = timed "$my-n: Run $filename", {
            $model.run(
                input     => $dataset,
                technical => %technical-parameters,
            );
        }
        ### create output
        ...
    }
```
Here we use the concurrency features of Raku to run the actual model simulation using multiple threads to speed-up execution.


### [Agrammon::Web::Routes](../lib/Agrammon/Web/Routes.pm6)

While already having shown the start-up of the web service above, here we see an example of setting up the routes of AGRAMMON's REST interface using `Cro::HTTP::Router` from [Edument's](https://www.edument.se/en) [Cro Services](https://cro.services/):
```
use Cro::HTTP::Router;
use Cro::OpenAPI::RoutesFromDefinition;
use Agrammon::Web::Service;
use Agrammon::Web::SessionUser;

subset LoggedIn of Agrammon::Web::SessionUser where .logged-in;

sub routes(Agrammon::Web::Service $ws) is export {
    my $schema = 'share/agrammon.openapi';
    my $root = '';
    route {
        include static-content($root);
        include api-routes($schema, $ws);

        ...

        after {
            forbidden if .status == 401 && request.auth.logged-in;
            .status = 401 if .status == 418;
        }
    }
}

sub static-content($root) {
    route {
        get -> {
            static $root ~ 'public/index.html'
        }
        
        ...
    }
}

sub api-routes (Str $schema, $ws) {
    openapi $schema.IO, {
        # working
        operation 'createAccount', -> LoggedIn $user {
            request-body -> (:$email!, :$password!, :$key, :$firstname, :$lastname, :$org, :$role) {
                my $username = $ws.create-account($user, $email, $password, $key, $firstname, $lastname, $org, $role);
                content 'application/json', { :$username };
                CATCH {
                    note "$_";
                    when X::Agrammon::DB::User::CreateFailed  {
                        not-found 'application/json', %( error => .message );
                    }
                    when X::Agrammon::DB::User::AlreadyExists
                       | X::Agrammon::DB::User::CreateFailed  {
                        conflict 'application/json', %( error => .message );
                    }
                }
            }
        }
        
    ...
}
```
the latter using the (abbreviated) OpenAPI definition
```
openapi: 3.0.0
info:
    version: 1.0.0,
    title: OpenApi Agrammon,
paths:
    /create_account:
        post:
            summary: Create new user account
            operationId: createAccount
            requestBody:
                required: true
                content:
                    application/json:
                        schema:
                            type: object
                            required:
                                - email
                                - password
                            properties:
                                email:
                                    description: User's email used as username
                                    type: string
                                firstname:
                                    description: Firstname
                                    type: string
                                lastname:
                                    description: Lastname
                                    type: string
              responses:
                '200':
                    description: Account created.
                    content:
                        application/json:
                            schema:
                                type: object
                                required:
                                    - username
                                properties:
                                    username:
                                        type: string
                '404':
                    description: Couldn't create account
                    content:
                        application/json:
                            schema:
                                $ref: "#/components/schemas/CreationFailed"
                '409':
                    description: User already exists
                    content:
                        application/json:
                            schema:
                                $ref: "#/components/schemas/Error"
```
handled by `Cro::OpenAPI::RoutesFromDefinition`.

## Which Christmas?

Well, as you can see from this [presentation](./swp2018.pdf] at the [Swiss Perl Workshop 2018](https://act.perl-workshop.ch/spw2018/), the original plan was not quite met, mostly due to another project being given higher priority (which was a very poor decision, but this is another long story). We had hoped to have AGRAMMON 6 deployed and in production before the appearance of this article and we almost suceeded. All the critical features are in place, a bit of polishing is still to be done. In addition, the customer has done a pretty extensive refactoring of the model description itself and is currently in the process of verifying both the model calculations and the functionality of the Raku based web application. The current setup is already online as [demo/test version](https://model.agrammon.ch/single/test) and you are welcome to give it a try. We expect the Raku implementation to go into production in early 2021 and to replace the current [Perl 5 implementation][https://model.agrammon.ch/single).

## Conclusion

Is Raku ready for use in production? Definitely yes! While having already delivered a few smaller customer projects implemented in Perl 6 and Raku, AGRAMMON 6 will be [Oetiker+Partner AG's](https://oetiker.ch) first publically accessible (web) application and we hope for many more to come. It was a great pleasure to work with our [colleague](https://www.edument.se/en/page/jonathan-worthington-eng) on this project and we also want to thank our [customer and partners](https://agrammon.ch/en/development-of-the-model/) for this opportunity.
