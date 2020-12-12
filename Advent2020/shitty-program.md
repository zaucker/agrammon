# Shitty Program - A Raku Christmas Tale

Quite a while ago, Santa got a feature request for a web application called [AGRAMMON](https://agrammon.ch/en), developed by one of his [sub-contractors](https://www.oetiker.ch) in Perl 5. When Santa asked the elve responsible for this application to get to work, the elve suggested that some refactoring was in order, as the application dated back almost 10 years and had been extended regularly. As the previous year had seen a real Christmas wonder, namely the release of Perl 6c, the elve suggested, that instead of bolting yet another feature onto the web application's Perl 5 backend, a rewrite in Perl 6 would be a bold but also appropriate move. The reason being that the application used a specially developed format for describing it's functionality by none-programmers. What better choice for rewriting the parser than Perl 6's grammars, the elve reasoned. When Santa asked when the rewrite would be finished, the obivous answer was "By Christmas".

And as things went in Perl 6 land, by the time the rewrite is going into production, the backend is now implemented in Raku.

## AGRAMMON

While most people nowadays know about the negative side-effects of agriculture on climate, a lesser known, but also significant environmental problem are ammonia (NH3) and nitrous oxide (NxOx) emissions. Those emissions are a result of the excrements of farm animals, mainly from cows, pigs, and pultry. Both solid and liquid excrements contain ammonia compounds such as urea which are decomposing either on the farm grounds, storage, and application as fertilizer. In addition to being an environmental pollutant, those emissions are also a big loss of nitrogen (N) from those natural fertilizers that must be replaced by artificial ones. 

In order to address these problems, the processes of ammonia volatilisation are being studied, optimizations for its reductions developed, and the effects measured where possible under controlled conditions. However, as those controlled conditions don't exist on a large scale, the effects of the reduction measures as well as the total amount of emissions can only be simulated by model calculations. AGRAMMAN is a tool that facilitates such simulations on the scale of a single farm and can also used for calculations on regional scales by means of simulating "typical farm types" using average process types and cumulated numbers of animals, storage areas, and fertilizer application. The following picture shows the processes simulated in the model.
[N model](N-model.jpg)

By now it might be obvious to the reader that this article's title is not mainly about code quality.

## The Application

AGRAMMON is a typical web application, with data stored in a PostgreSQL database, a web frontend implemented in JavaScript using the [Qooxdoo](https://qooxdoo.org), and the Raku backend. The physical and chemical processes are not directly implemented in the backend, but as already mentioned in a none-programmer-friendly custom "language", describing (user) inputs, model parameters, calculations, and outputs (results). Each process is broken down into smaller sub-processes and each is described in its own file, including documentation and references to appropriate scientific sources. Here is a small example for such a file:

```
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
