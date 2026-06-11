# sdtm.oak Function Reference

Quick reference for the six core mapping algorithms and supporting utilities.

---

## Mapping algorithms

### `assign_no_ct()`

Maps a raw column to an SDTM variable **without** controlled terminology recoding.

```r
assign_no_ct(
  tgt_dat = NULL,      # growing SDTM dataset (pipe from previous step)
  tgt_var,             # target SDTM variable name (string)
  raw_dat,             # original raw dataset (never tgt_dat)
  raw_var,             # source column name in raw_dat (string)
  id_vars = oak_id_vars()
)
```

Use for: AETERM, CMTRT, VSORRES, VSORRESU, VSORRESU, free-text verbatim fields.

---

### `assign_ct()`

Maps a raw column to an SDTM variable **with** CT recoding applied.

```r
assign_ct(
  tgt_dat = NULL,
  tgt_var,
  raw_dat,
  raw_var,
  ct_spec,             # CT spec dataframe from read_ct_spec()
  ct_clst,             # codelist_code string, e.g. "AESEV", "NY", "RACE"
  id_vars = oak_id_vars()
)
```

Use for: AESEV, AESER, AEREL, AEOUT, SEX, RACE, ETHNIC, VSBLFL, EXROUTE, any
variable with a CDISC codelist. Unmatched raw values are returned uppercased —
always verify output frequency table after derivation.

---

### `hardcode_no_ct()`

Assigns a **fixed scalar value** to all records without CT validation.

```r
hardcode_no_ct(
  tgt_dat = NULL,
  tgt_val,             # scalar value to assign to every row
  raw_dat,             # used to determine which records receive the value
  raw_var,             # presence filter: rows where raw_var is non-NA
  tgt_var,
  id_vars = oak_id_vars()
)
```

Use for: STUDYID, custom study flags, any constant free-text value.

---

### `hardcode_ct()`

Assigns a **fixed scalar value** validated against a CT codelist.

```r
hardcode_ct(
  tgt_dat = NULL,
  tgt_val,
  raw_dat,
  raw_var,
  tgt_var,
  ct_spec,
  ct_clst,
  id_vars = oak_id_vars()
)
```

Use for: DOMAIN (always), VSTESTCD / VSTEST per parameter block in findings
domains, any constant that must conform to CDISC CT.

---

### `assign_datetime()`

Converts raw date/time column(s) to ISO 8601 format.

```r
assign_datetime(
  tgt_dat = NULL,
  tgt_var,
  raw_dat,
  raw_var,             # string or character vector (multiple columns for date+time)
  raw_fmt,             # format string(s) matching raw_var order
                       #   codes: "y" year, "m" month, "d" day,
                       #          "H" hour, "M" minute, "S" second
                       #   e.g. "d-m-y", "y/m/d", c("y-m-d","H:M:S")
                       #   use list() for alternative formats: list(c("y-m-d","y m d"))
  raw_unk = c("UN", "UNK"),   # strings treated as missing
  id_vars = oak_id_vars(),
  .warn = TRUE
)
```

Use for: every `--DTC` variable. Never use `as.Date()` or string manipulation.

---

### `condition_add()`

Tags rows matching a logical condition; downstream `assign_*` / `hardcode_*`
calls apply only to tagged rows.

```r
condition_add(
  dat,                 # dataframe to condition (the growing tgt_dat)
  ...,                 # one or more logical expressions (combined with &)
  .na = NA
)
```

Returns a `cnd_df` — pass as `tgt_dat` to any mapping function. Rows where the
condition is FALSE receive NA for the newly derived variable.

---

## Supporting utilities

### `generate_oak_id_vars()`

Adds `oak_id`, `raw_source`, `patient_number` to a raw dataset. **Must be
called first** before any mapping function.

```r
generate_oak_id_vars(
  raw_dat,
  pat_var,    # column in raw_dat holding subject identifier
  raw_src     # string label for this CRF form / data source
)
```

### `oak_id_vars()`

Returns the default join key vector `c("oak_id", "raw_source", "patient_number")`.
Used as the default `id_vars` argument throughout all mapping functions.

### `read_ct_spec()` / `read_ct_spec_example()`

```r
ct_spec <- read_ct_spec("path/to/ct_spec.csv")   # study CT
ct_spec <- read_ct_spec_example()                  # built-in example
assert_ct_spec(ct_spec)                            # validate before use
```

Required columns: `codelist_code`, `collected_value`, `term_synonyms`, `term_value`.

### `derive_seq()`

Derives the `--SEQ` variable. Call after all variables are derived and the
domain is complete.

```r
derive_seq(sdtm_in = domain, tgt_var = "AESEQ")
```

### `derive_study_day()`

Calculates `--DY` relative to DM reference date.

```r
derive_study_day(
  sdtm_in       = domain,
  dm_domain     = dm,
  tgdt          = "AESTDTC",    # DTC variable to compute day from
  refdt         = "RFSTDTC",    # reference date in DM (usually RFSTDTC)
  study_day_var = "AESTDY"
)
```

### `derive_blfl()`

Derives baseline flag for findings domains.

```r
derive_blfl(
  sdtm_in         = vs_domain,
  dm_domain       = dm,
  tgt_var         = "VSBLFL",
  ref_var         = "VSDTC",
  baseline_visits = c("BASELINE", "DAY 1")   # protocol-specific
)
```

### `generate_sdtm_supp()`

Splits non-standard variables to a SUPP-- domain.

```r
result <- generate_sdtm_supp(
  sdtm_dataset   = domain,
  idvar          = "--SEQ variable name",
  supp_qual_info = supp_spec,   # df with QNAM, QLABEL, QORIG per variable
  qnam_var       = "QNAM",
  label_var      = "QLABEL",
  orig_var       = "QORIG"
)
main_domain <- result$sdtm
supp_domain <- result$supp
```
