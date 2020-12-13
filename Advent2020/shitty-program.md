# Christmas Tale About a Shitty Raku Program

Quite a while ago, Santa got a feature request for a web application called [AGRAMMON](https://www.agrammon.ch/en), developed by the elves of one of his sub-contractors [Oetiker+Partner AG](https://www.oetiker.ch) in what then was called Perl 5. When Santa asked the [elf responsible](https://www.oetiker.ch/en/company/team/fz) for this application to get to work, the elf suggested that some refactoring was in order, as the application dated back almost 10 years and had been extended regularly.

As the previous year had seen a real Christmas wonder, namely the [release of Perl 6c](https://perl6advent.wordpress.com/2015/12/), the elf suggested, that instead of bolting yet another feature onto the web application's Perl backend, a rewrite in Perl 6 would be a bold but also appropriate move. The reason being that the application used a specially developed format for describing it's functionality by none-programmers. What better choice for rewriting the parser than Perl 6's grammars, the elf reasoned. Fittingly, the new AGRAMMON was going to be version 6.

When Santa asked when the rewrite would be finished, the elf's obivous answer was "by Christmas". And as things went in Perl 6 land, by the time the rewrite is finally going into production, the backend is now implemented in Raku.

## AGRAMMON

Most people nowadays know about the negative side-effects of agriculture on climate, namely emissions of methane (a strong greenhouse gas) and deforestation. A lesser known, but also significant environmental problem, are ammonia (NH3) and nitrous oxide (NxOx) emissions.

The main source of these emissions are excrements of farm animals, mainly from cows, pigs, and poultry. Both solid (manure) and liquid (slurry) excrements contain ammonia compounds such as urea. These compounds are decomposing when the excrements are lying on the farm grounds, while being stored in manure heaps or slurry storage, and when brought out on the field as fertilizer.

In addition to being an environmental pollutant, those emissions are also entail a big loss of nitrogen (N) from those natural fertilizers and either result in diminished productivity of farming or must be replaced by artificial fertilizers at additional costs to the farmers. In Switzerland alone about 40,000 tonnes of nitrogen are lost every year, amounting to about 30% of the N load of farmland manure.

In order to address these problems, the processes of ammonia volatilisation are being studied, optimizations for its reductions developed, and the effects measured where possible under controlled conditions. However, as those controlled conditions don't exist on a large scale, the effects of the reduction measures as well as the total amount of emissions can only be simulated by model calculations. AGRAMMON is a tool that facilitates such simulations on the scale of a single farm. Those calculations can also be done on regional scales by means of simulating "typical farm types" using average process types and cumulated numbers of animals, storage areas, and fertilizer application. The following picture shows the processes simulated in the model:

<p align="center"><img align="center" src="https://github.com/zaucker/agrammon/blob/Advent/Advent2020/N-model.jpg" /></p>
  
By now it might be obvious to the reader that this article's title is not mainly about code quality.

## The Application

AGRAMMON is a typical web application, with data stored in a PostgreSQL database, a web frontend implemented in JavaScript using the [Qooxdoo framework](https://qooxdoo.org) , and a Raku backend. The physical and chemical processes are not directly implemented in the backend, but as already mentioned in a none-programmer-friendly custom "language", describing (user) inputs, model parameters, calculations, and outputs (results).

Each process is broken down into smaller sub-processes and each is described in its own file, including documentation and references to appropriate scientific sources. Here is a small example for such a file:

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

In the current version of the AGRAMMON model there are 133 such model files with 31,014 lines. From those, the backend can generate

* the PDF documentation of the model (allowing [LaTeX](https://www.latex-project.org/) formatting in the files)
* the actual model simulation using the user's input data
* a description of the web GUI which can be rendered by the frontend

<p align="center"><img align="center" src="https://github.com/zaucker/agrammon/blob/Advent/Advent2020/inputs.png" /></p>

The results are presented in the web GUI in tabular form (showing various subsets of the data that can also be defined in the model files)

<p align="center"><img align="center" src="https://github.com/zaucker/agrammon/blob/Advent/Advent2020/results.png" /></p>

 and can be exported as [PDF report](TestSingle6.pdf) or [Excel file](TestSingle6.xlsx), together with the actual inputs provided by the user.

A special instance of AGRAMMON is used by a [regional government agency](https://lawa.lu.ch/) in the evaluation process of the environmental impact of modifications to local farms and the approval of the respective building applications. For this, the ammonia emissions before and after the planned modifications must be simulated by the applicant and can be directly submitted to the agency's AGRAMMON account, including a notification of the agency by eMail with the PDF report attached.

## The Raku backend

The refactored backend as of today consists of 59 `.pm6` [modules/packages](https://docs.raku.org/language/modules) with 6,942 lines and is covered by tests in 38 `.t` files with 5,854 lines. It uses the 13  Raku modules shown in the following excerpt of the [META6.json](https://docs.raku.org/language/modules#index-entry-META6.json-META6.json) file:
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
Those modules can be found on the [Raku Modules Directory](https://modules.raku.org/). Note that [`Spreadsheet::XLSX`](https://github.com/jnthn/spreadsheet-xlsx) was specifically implemented for this project.

Speaking of the actual implementation, although our brave elf didn't have much experience with either grammars, parsers, or even Perl 6 / Raku, he was smart enough to engage a real [expert elf](https://www.edument.se/en/page/jonathan-worthington-eng) for that. This elf did most of the heavy lifting of the backend implementation and helped our elf with advice and code review for the parts he implemented himself.

Please note that the goal of this rewrite was to leave most of the syntax of the model implementation and also the frontend as is, so the blame for all the sub-optimal design decisions are solely on our primary elf as well as the responsibility for imperfect implementation details passing under the review radar.

## Some Raku features used in AGRAMMON

In this section we'll present a few Raku features used in AGRAMMON. This is not meant as a hardcore technical explanation for experts, but rather as a means to give a taste to people interested in Raku.

### [bin/agrammon.pl6](../bin/agrammon.pl6)

The actual AGRAMMON "executable" is just a three-liner (of which only two are Raku):

```
#!/usr/bin/env raku
use lib "lib"
use Agrammon::UI::CommandLine;
```

This exploits the fact that Rakudo (the Raku implementation used here) has a pretty nice [pre-compilation](https://docs.raku.org/language/faq#index-entry-Precompile_(FAQ)) feature which is useful for minimizing (the still not neglegible) startup time after the first run of the program.

### [Agrammon::UI::CommandLine](../lib/Agrammon/UI/CommandLine.pm6)

This module contains the main functions of the AGRAMMON application available from the command line.

#### Usage

Running `./bin/agrammon.pl6` gives the following output:

```console
Usage:
  ./bin/agrammon.pl6 web <cfg-filename> <model-filename> [<technical-file>] -- Start the web interface
  ./bin/agrammon.pl6 [--language=<SupportedLanguage>] [--prints=<Str>] [--variants=<Str>] [--include-filters] [--include-all-filters] [--batch=<Int>] [--degree=<Int>] [--max-runs=<Int>] [--format=<OutputFormat>] run <filename> <input> [<technical-file>] -- Run the model
  ./bin/agrammon.pl6 [--variants=<Str>] [--sort=<SortOrder>] dump <filename> -- Dump model
  ./bin/agrammon.pl6 [--variants=<Str>] [--sort=<SortOrder>] latex <filename> [<technical-file>]
  ./bin/agrammon.pl6 create-user <username> <firstname> <lastname> -- Create Agrammon user
  
    <cfg-filename>        configuration file
    <model-filename>      top-level model file
    [<technical-file>]    optionally override model parameters from this file

    See https://www.agrammon.ch for more information about Agrammon.
```

This usage message is created automatically from the implementation of the [`multi`](https://docs.raku.org/language/functions#Multi-dispatch) subroutine [`MAIN`](https://docs.raku.org/routine/MAIN) instances as shown for the first line:

```
#| Start the web interface
multi sub MAIN(
        'web',
        ExistingFile $cfg-filename,   #= configuration file
        ExistingFile $model-filename, #= top-level model file
        Str $technical-file?          #= override model parameters from this file
    ) is export {
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

Note that the parameter `$technical-file` is marked as optional by the trailing `?` and that the usage message thus also marks this parameter as optional by enclosing it in `[  ]`.

The usage message also shows the command line calls for
- running the model in batch mode from the command line (`run`),
- showing the simulation flow by `dump`ing the model structur,
- generation of the model documentation (`latex`),
- and for creation of user accounts for the web application.

#### sub web() 

This [subroutine](https://docs.raku.org/language/functions) is called to start the web service as shown in the first line of the above usage message.

```
sub web(Str $cfg-filename, Str $model-filename, Str $technical-file?) is export {

    # initialization
    # ...
    
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
The [subroutine](https://docs.raku.org/language/functions) uses a [signature](https://docs.raku.org/type/Signature) to describe it's arguments (all of them are of [type `Str`](https://docs.raku.org/type/Str) and the third argument is again marked as optional by the trailing `?`.

#### sub run()

The AGRAMMON application can also be used directly from the command line by providing input data from a [CSV](https://tools.ietf.org/html/rfc4180] file. This mode is used from scientists to automate the running large amounts of simulations for regional and national projections. It is planned to make this mode available via a [REST](https://tools.ietf.org/html/rfc6690) API call in the future.

```
sub run (IO::Path $path, IO::Path $input-path, $technical-file, $variants, $format, $language, $prints,
         Bool $include-filters, $batch, $degree, $max-runs, :$all-filters) is export {
         
    # initialization
    # ...
    
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
        # create output
        # ...
    }
```

Here we use [`race`](https://docs.raku.org/routine/race), one of the various [concurrency features](https://docs.raku.org/language/concurrency) of Raku, to run the actual model simulation using multiple threads in parallel to speed-up execution.

The [function's](https://docs.raku.org/language/functions) [signature](https://docs.raku.org/type/Signature) again specifies the types of some parameters. In addition to (too many) positional arguments, `:$all-filters`is a by default optional [named argument](https://docs.raku.org/language/functions#Arguments).

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
the latter using the (abbreviated) [OpenAPI](https://swagger.io/specification/) definition
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

### [Agrammon::OutputFormatter::PDF](../lib/Agrammon/OutputFormatter/PDF.pm6)

For documenting AGRAMMON calculations, PDF reports of the inputs to the model and the simulation results can be created by first creating a LaTeX file using the [`Cro::WebApp::Template`](https://github.com/croservices/cro-webapp) module. While tailored towards generation of HTML pages, it worked quite well for our purpose. The module does escape its input data appropriate for HTML, however, a simple-minded escaping of characters with special meaning in LaTeX was implemented outside the module:

```
sub latex-escape(Str $in) is export {
    my $out = $in // '';
    $out ~~ s:g/<[\\]>/\\backslash/;
    $out ~~ s:g/(<[%#{}&$|]>)/\\$0/;
    $out ~~ s:g/(<[~^]>)/\\$0\{\}/;
    # this is a special case for Agrammon as we use __ in
    # the frontend at the moment for indentation in the table
    $out ~~ s:g/__/\\hspace\{2em\}/;
    $out ~~ s:g/_/\\_/;
    return $out;
}
```

An addition function is used for beautification of chemical molecules:

```
sub latex-chemify(Str $in) is export {
    my $out = $in // '';
    $out ~~ s:g/NOx/\\ce\{NO_\{\(x\)\}\}/;
    $out ~~ s:g/(N2O|NH3|N2|NO2)/\\ce\{$0\}/;
    return $out;
}
```
These functions use simple [regular expression](https://docs.raku.org/language/regexes) substitutions. A more generic handling of LaTeX special characters would  need porting something like the [`LaTeX::Encode`](https://metacpan.org/pod/LaTeX::Encode) Perl module to Raku. Alternatively, [`Inline::Perl5`](https://github.com/niner/Inline-Perl5) could be employed to utilize the Perl module. 

This code fragment shows how a [LaTeX](https://www.latex-project.org/) file is created
```
    %data<titles>    = %titles;
    %data<dataset>   = $dataset-name // 'NO DATASET';
    %data<username>  = $user.username // 'NO USER';
    %data<model>     = $cfg.gui-variant // 'NO MODEL';
    %data<timestamp> = ~DateTime.now( formatter => sub ($_) {
        sprintf '%02d.%02d.%04d %02d:%02d:%02d',
            .day, .month, .year,.hour, .minute, .second,
    });
    %data<version>    = latex-escape($cfg.gui-title{$language} // 'NO  VERSION');
    %data<outputs>    = @output-formatted;
    %data<inputs>     = @input-formatted;
    %data<submission> = %submission;
    
    template-location $*PROGRAM.parent.add('../share/templates');
    my $temp-dir    = $*TMPDIR.add($temp-dir-name);
    my $source-file = "$temp-dir/$filename.tex".IO;

    my $latex-source = render-template('pdfexport.crotmp', %data);
    
    $source-file.spurt($latex-source, %data);   
```

by calling `render-template` with a `%data` hash and a template file `pdfexport.crotmp` like

```
\nonstopmode
\documentclass[10pt,a4paper]{article}

\begin{document}

\section*{<.titles.report>}
\section{<.titles.data.section>}
\begin{tabular}[t]{@{}l@{\hspace{2em}}p{7cm}}
    \textbf{<.titles.data.dataset>:} & <.dataset>\\
    \textbf{<.titles.data.user>:} & <.username>\\
    \textbf{Version:} & <.model>\\
\end{tabular}

\section{<.titles.outputs>}
<@outputs>
<?.section>
<!.first>
\bottomrule
\end{tabular}
</!>
\subsection{<.section>}
\noindent
\rowcolors{1}{LightGrey}{White}
\begin{tabular}[t]{lllrl}
\toprule
</?>
<!.section>
&  & <.label> & <.value> & <.unit>\\
</!>
</@>
\bottomrule
\end{tabular}
\end{document}
```

as arguments. The generated LaTeX source is then written to a file using the [`spurt`](https://docs.raku.org/routine/spurt) function.

While the above template might seem a bit cryptic if you are not familiar with LaTeX, the relevant parts are the HTML-like tags like `<.titles.report>` accessing a value of the hash data structured passed to `render-template`, `<@output> ... </@>` being an array in this data structure being iterated over, or the conditionals `<?.section> ... </?>` or `<!.section> ... </!>`. For details please consult the documentation of the [`Cro::WebApp::Template`](https://github.com/croservices/cro-webapp) module.

The LaTeX file is then rendered into a PDF file with the external program [`lualatex`](`http://www.luatex.org/) and the built-in [`Proc::Async`](https://docs.raku.org/type/Proc::Async) class:

```
# setup temp dir and files
my $temp-dir = $*TMPDIR.add($temp-dir-name);
my $source-file = "$temp-dir/$filename.tex".IO;
my $pdf-file    = "$temp-dir/$filename.pdf".IO;
my $log-file    = "$temp-dir/$filename.log".IO;

# create PDF, discard STDOUT and STDERR (see .log file if necessary)
my $exit-code;
my $signal;
my $reason = 'Unknown';

my $proc = Proc::Async.new: :w, '/usr/bin/lualatex',
        "--output-directory=$temp-dir",  '--no-shell-escape', '--', $source-file, ‘-’;

react {
    # discard any output of the external program
    whenever $proc.stdout.lines {
    }
    whenever $proc.stderr {
    }
    # save exit code and signal if program was terminated
    whenever $proc.start {
        $exit-code = .exitcode;
        $signal    = .signal;
        done; # gracefully jump from the react block
    }
    # make sure we don't end up with a hung-up lualatex process
    whenever Promise.in(5) {
        $reason = 'Timeout';
        note ‘Timeout. Asking the process to stop’;
        $proc.kill; # sends SIGHUP, change appropriately
        whenever Promise.in(2) {
            note ‘Timeout. Forcing the process to stop’;
            $proc.kill: SIGKILL
        }
    }
}

# write appropriate error messages if program didn't terminate sucessfully
if $exit-code {
    note "$pdf-prog failed for $source-file, exit-code=$exit-code";
    die X::Agrammon::OutputFormatter::PDF::Failed.new: :$exit-code;
}
if $signal {
    note "$pdf-prog killed for $source-file, signal=$signal, reason=$reason";
    die X::Agrammon::OutputFormatter::PDF::Killed.new: :$reason;
}

# read content of PDF file created in binary format for further use
my $pdf = $pdf-file.slurp(:bin);
# remove created files if successful, otherwise keep for debugging
unlink $source-file, $pdf-file, $aux-file, $log-file unless %*ENV<AGRAMMON_KEEP_FILES>;
```

A [`react`](https://docs.raku.org/language/concurrency#index-entry-react) block with several `whenever` blocks is used to handle the events from the asynchronously running external program to avoid blocking of the otherwise already asynchronous backend.

[Typed exceptions](https://docs.raku.org/language/exceptions#Typed_exceptions) are used to handle errors occuring in the external process. 

### [Agrammon::OutputFormatter::Excel](../lib/Agrammon/OutputFormatter/Excel.pm6)

Here we create Excel exports of the simulation results and the user inputs, using [`Spreadsheet::XLSX`](https://github.com/jnthn/spreadsheet-xlsx). This module allows to read and write [XLSX](https://docs.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/) files from Raku. The current functionality is by no means complete, but implements what was needed for AGRAMMON. Please feel free to provide pull requests or funds for the implementation of additional features.

```
# get data to be shown
my %data = collect-data();
# ...

my $workbook = Spreadsheet::XLSX.new;

# prepare sheets
my $output-sheet = $workbook.create-worksheet('Results');
my $input-sheet = $workbook.create-worksheet('Inputs');
my $timestamp = ~DateTime.now( formatter => sub ($_) {
    sprintf '%02d.%02d.%04d %02d:%02d:%02d',
            .day, .month, .year, .hour, .minute, .second,
});
# add some meta data to the sheets
for ($output-sheet, $input-sheet) -> $sheet {
    $sheet.set(0, 0, $dataset-name, :bold);
    $sheet.set(1, 0, $user.username);
    $sheet.set(2, 0, $model-version);
    $sheet.set(3, 0, $timestamp);
}

# set column width
for ($output-sheet, $input-sheet) -> $sheet {
    $sheet.columns[0] = Spreadsheet::XLSX::Worksheet::Column.new:
            :custom-width, :width(20);
    $sheet.columns[1] = Spreadsheet::XLSX::Worksheet::Column.new:
            :custom-width, :width(32);
    $sheet.columns[2] = Spreadsheet::XLSX::Worksheet::Column.new:
            :custom-width, :width(20);
    $sheet.columns[3] = Spreadsheet::XLSX::Worksheet::Column.new:
            :custom-width, :width(10);
}

# add input data to sheets
my $row = 0;
my $col = 0;
my @records := %data<inputs>;
for @records -> %rec {
    $input-sheet.set($row, $col+2, %rec<input>);
    $input-sheet.set($row, $col+3, %rec<value>, :number-format('#,#'), :horizontal-align(RightAlign));
    $input-sheet.set($row, $col+4, %rec<unit>);
    $row++;
}

# add output data to sheets
# ...

```
This example shows a variety of [Raku basics](https://docs.raku.org/language/101-basics):
- `%data`, `%rec` are [hash](https://docs.raku.org/language/101-basics#Hashes) [variables](https://docs.raku.org/language/variables). Contrary to Perl, in Raku the [sigils](https://docs.raku.org/language/101-basics#Sigils_and_identifiers) don't change when accessing elements of variables.
- `for ($output-sheet, $input-sheet) -> $sheet { ... }` and `for @records -> %rec { ... }` are [loops](https://docs.raku.org/language/101-basics#for_and_blocks) over a [lists](https://docs.raku.org/language/list), each assigning the current element to a variable in the loop's [scope](https://docs.raku.org/language/variables#Variable_declarators_and_scope) using the [pointy block](https://docs.raku.org/language/functions#Blocks_and_lambdas) syntax.
- `my $timestamp = ~DateTime.now( formatter => sub ($_) { ... } ...)` uses the builtin [`DateTime`](https://docs.raku.org/routine/DateTime) method to create a timestamp, using the [`~`operator](https://docs.raku.org/routine/~) to coerce it into a string. The string is being formatted by the unamed [anonymous subroutine](https://docs.raku.org/language/functions#Defining/Creating/Using_functions) `sub ($_) { ... }` which uses the [topic variable `$_`](https://docs.raku.org/language/101-basics#Topic_variable) as argument on which the various methods of the the DateTime [class](https://docs.raku.org/language/classtut) are being called by just prepending a `.` For example, `.year` is just a short-cut for `$_.year`.

### [Agrammon::Email](../lib/Agrammon/Email.pm6)

As mentioned above PDF reports of simulations can be mailed to certain AGRAMMON users directly from the web application. First, a [multi-part MIME](https://tools.ietf.org/html/rfc1521) message is created using the [`Email::MIME`](https://modules.raku.org/dist/Email::MIME) module.

```
# create PDF attachment
my $attachment = Email::MIME.create(
    attributes => {
        'content-type' => "application/pdf; name=$filename",
        'charset'      => 'utf-8',
        'encoding'     => 'base64',
    },
    body => $pdf,
);
# create main body part            
my $msg = Email::MIME.create(
    attributes => {
        'content-type' => 'text/plain',
        'charset'      => 'utf-8',
        'encoding'     => 'quoted-printable'
    },
    body-str => 'Attached please find a PDF report from a AGRAMMON simulation,
);
# build multi-part Email
my $from = 'support@agrammon.ch';
my $to   = 'foo@bar.com';
my $mail = Email::MIME.create(
    header-str => [
        'to'      => $to,
        'from'    => $from,
        'subject' => 'Mail from AGRAMMON'
    ],
    parts => [
        $msg,
        $attachment,
    ]
);
```

This message is then sent to the mail's recipient using the [promise](https://docs.raku.org/type/Promise) based [`Net::SMTP::Client::Async`](https://modules.raku.org/dist/Net::SMTP::Client::Async) module:

```
# asynchronously send Email via AGRAMMON's SMTP server
with await Net::SMTP::Client::Async.connect(:host<mail.agrammon.ch>, :port(25), :!secure) {
    # wait for SMTP server's welcome response
    await .hello;
    # send message
    await .send-message(
        :$from,
        :to([ $to ]),
        :message(~$mail),
    );
    # terminate connection on exit
    LEAVE .quit;
    # catch exceptions and emit user friendly error message
    CATCH {
        when X::Net::SMTP::Client::Async {
            note "Unable to send email message: $_";
        }
    }
}
```
The [`await`](https://docs.raku.org/type/Promise#sub_await) function is used to handle the asynchronous communication with the [SMPT](https://tools.ietf.org/html/rfc5321) server. The [`LEAVE`](https://docs.raku.org/language/phasers#index-entry-Phasers__LEAVE-LEAVE) is called upon exit from the `with await { ... }` block to close the connection to the server.

### Parser and Compiler

Finally, a few words about the parser and compiler used to process the AGRAMMON model files shown above. [`Agrammon::ModuleParser`](../lib/Agrammon/ModuleParser.pm6) is the top-level element for parsing the model files:

```
use v6;
use Agrammon::CommonParser;

grammar Agrammon::ModuleParser does Agrammon::CommonParser {
    token TOP {
        :my $*TAXONOMY = '';
        :my $*CUR-SECTION = '';
        <.blank-line>*
        <section>+
        [
        || $
        || <.panic('Confused')>
        ]
    }

    proto token section { * }

    token section:sym<general> {
        <.section-heading('general')>
        [
        | <option=.single-line-option>
        | <option=.multi-line-str-option('+')>
        | <.blank-line>
        ]*
    }

    token section:sym<external> {
        <.section-heading('external')>
        [
        | <.blank-line>
        | <external=.option-section>
        ]*
    }

    token section:sym<input> {
        <.section-heading('input')>
        [
        | <.blank-line>
        | <input=.option-section>
        ]*
    }

    token section:sym<technical> {
        <.section-heading('technical')>
        [
        | <.blank-line>
        | <technical=.option-section>
        ]*
    }

    token section:sym<output> {
        <.section-heading('output')>
        [
        | <.blank-line>
        | <output=.option-section>
        ]*
    }

    token section:sym<results> {
        <.section-heading('results')>
        [
        | <.blank-line>
        | <results=.option-section>
        ]*
    }

    token section:sym<tests> {
        <.section-heading('tests')>
        [
        | <.blank-line>
        | <tests=.option-section>
        ]*
    }
}
```
It handles parsing of the various sections of the model file sections, using various elements from module [`Agrammon::CommonParser`](../lib/Agrammon/CommonParser.pm6) such as
```
   token section-heading($title) {
        \h* '***' \h* $title \h* '***' \h* \n
        { $*CUR-SECTION = $title }
    }

    token option-section {
        \h* '+' \h* <name> \h* \n
        [
        | <.blank-line>
        | <option=.single-line-option>
        | <option=.subsection-map>
        | <option=.multi-line-str-option('++')>
        ]*
    }

    token single-line-option {
        \h* <key> \h* '=' \h*
        $<value>=[[<!before \h*'#'>\N]*]
        \h* ['#'\N*]?
        [\n || $]
    }
    
   token blank-line {
        | \h* \n
        | \h* '#' \N* \n
        | \h+ $
    }
```

Raku [grammars](https://docs.raku.org/type/Grammar) are basically build top-down from [regular expressions](https://docs.raku.org/language/regexes). Such grammars can be extended by means of [action classes](https://docs.raku.org/language/grammar_tutorial#Grammar_actions) that further process the [match objects](https://docs.raku.org/type/Match) generated while parsing the data fed to the grammar.

Please consult [this tutorial](https://docs.raku.org/language/grammar_tutorial) or other resources to learn more about those concepts.

If you want to know more about the (real-world) AGRAMMON parser/compiler you can have a look at the other parser elements in the [`Agrammon::Formula::Parser`](../lib/Agrammon/Formula/Parser.pm6), [`Agrammon::Formula::Builder`](../lib/Agrammon/Formula/Builder.pm6), [`Agrammon::ModuleBuilder`](../lib/Agrammon/ModuleBuilder.pm6), [`Agrammon::TechnicalParser`](../lib/Agrammon/TechnicalParser.pm6), [`Agrammon::TechnicalBuilder`](../lib/Agrammon/TechnicalBuilder.pm6), and [`Agrammon::`](../lib/Agrammon/LanguageParser.pm6) modules, the latter being a simple none-grammmar based element.

The compiler finally is implemented in the modules [`Agrammon::Formula::Compiler`](../lib/Agrammon/Formula/Compiler.pm6) and  [`Agrammon::Formula::Builtins`](../lib/Agrammon/Formula/Builtins.pm6).

Finally, as a recent addition, AGRAMMON also got a C-style preprocessor in [`Agrammon::Preprocessor`](../lib/Agrammon/Preprocessor.pm6) for conditionally including or excluding parts of the model using the following syntax:

```
?if FOO
...
?elsif BAR
...
?else
...
?endif
```

with optional `?elsif` and `?else` parts. The keywords can also be negated, such as `?if !FOO`. 

## So, which Christmas?

Well, as you can see from this [presentation](./swp2018.pdf) at the [Swiss Perl Workshop 2018](https://act.perl-workshop.ch/spw2018/), the original plan was not quite met, mostly due to another project being given higher priority (which was a very poor decision, but this is another long story).

We had hoped to have AGRAMMON 6 deployed and in production before the appearance of this article and almost suceeded. All the critical features are in place, a bit of polishing is still to be done. In addition, the customer has done a pretty extensive refactoring of the model files and is currently in the process of verifying both the model calculations and the functionality of the Raku based web application. 

The current setup is already online as [demo/test version](https://model.agrammon.ch/single/test) and you are welcome to give it a try. We expect the Raku implementation to finally go into production in early 2021 and to replace the current [Perl implementation](https://model.agrammon.ch/single).

## Conclusion

Is Raku ready for use in production? Definitely yes!

While having already delivered a few smaller customer projects implemented in Raku, AGRAMMON 6 will be [Oetiker+Partner AG's](https://www.oetiker.ch) first publically accessible (web) application and we hope for many more to come. It was a great pleasure to work with our [colleague](https://www.edument.se/en/page/jonathan-worthington-eng) on this project and we also want to thank our [customer and partners](https://www.agrammon.ch/en/development-of-the-model/) for this opportunity.
