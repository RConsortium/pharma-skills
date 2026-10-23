# Passing ADPC to PKNCA

ADPC is the input to NCA, not the place where NCA happens. This reference shows
which ADPC records and variables an NCA tool needs, using {PKNCA}. Computing
NCA parameters and building ADPP is outside the `admiral-adpc` skill.

## Which records to use

| NCA input | ADPC records | Variables |
|---|---|---|
| Concentrations | `PARAMCD` = analyte, one `PARCAT1` (e.g. PLASMA), original records only (`ANL02FL == "Y"`) | `AVAL`, `AFRLT` (or `NFRLT`), `USUBJID`, treatment |
| Doses | `PARAMCD == "DOSE"` | `DOSEA`, `AFRLT`, `USUBJID`, treatment |

Use the original records, not the `DTYPE = "HALFLLOQ"` copies: PKNCA applies
its own BLQ rules (`PKNCA.options(conc.blq = ...)`), which expect BLQ values as
0. Set BLQ concentrations to 0 when building the PKNCA input, and configure the
BLQ rule in PKNCA to match the SAP.

Choose actual (`AFRLT`) or nominal (`NFRLT`) time per the SAP. When EX has no
dose times, actual times rest on imputed 00:00 dose times; see the `# REVIEW:`
in SKILL.md Step 4.

## Example

```r
library(PKNCA)

conc_df <- adpc |>
  filter(PARAMCD == "XAN", PARCAT1 == "PLASMA", ANL02FL == "Y") |>
  mutate(CONC = if_else(AVALCAT1 %in% "<BLQ", 0, AVAL)) |>
  select(USUBJID, TRT01A, AFRLT, CONC)

dose_df <- adpc |>
  filter(PARAMCD == "DOSE") |>
  select(USUBJID, TRT01A, AFRLT, DOSEA)

conc_obj <- PKNCAconc(conc_df, CONC ~ AFRLT | TRT01A + USUBJID)
dose_obj <- PKNCAdose(dose_df, DOSEA ~ AFRLT | TRT01A + USUBJID)

# Without an intervals argument, PKNCA picks intervals from the dosing records.
# For a submission, specify intervals and parameters explicitly per the SAP.
nca_data <- PKNCAdata(conc_obj, dose_obj)
nca_res  <- pk.nca(nca_data)
summary(nca_res)
```

The NCA results (`as.data.frame(nca_res)`) are the input to ADPP, with one
record per subject, interval and NCA parameter.
