library(pharmaverseadam)
library(dplyr)
library(haven)

ref <- pharmaverseadam::adsl |>
  zap_labels() |>
  select(USUBJID, TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, SAFFL)

comparison <- adsl |>
  zap_labels() |>
  select(USUBJID, TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, SAFFL) |>
  mutate(USUBJID = as.character(USUBJID)) |>
  left_join(ref, join_by(USUBJID), suffix = c("_agent", "_ref"))

# Agreement rates
comparison |>
  summarise(
    trtsdt_match = mean(TRTSDT_agent == TRTSDT_ref, na.rm = TRUE),
    trtedt_match = mean(TRTEDT_agent == TRTEDT_ref, na.rm = TRUE),
    trt01p_match = mean(TRT01P_agent == TRT01P_ref, na.rm = TRUE),
    trt01a_match = mean(TRT01A_agent == TRT01A_ref, na.rm = TRUE),
    eosstt_match = mean(EOSSTT_agent == EOSSTT_ref, na.rm = TRUE),
    saffl_match  = mean(SAFFL_agent  == SAFFL_ref,  na.rm = TRUE)
  )

# Mismatches
comparison |>
  filter(
    TRTSDT_agent != TRTSDT_ref |
    TRTEDT_agent != TRTEDT_ref |
    EOSSTT_agent != EOSSTT_ref |
    SAFFL_agent  != SAFFL_ref
  ) |>
  select(USUBJID, TRTSDT_agent, TRTSDT_ref, TRTEDT_agent, TRTEDT_ref,
         EOSSTT_agent, EOSSTT_ref, SAFFL_agent, SAFFL_ref)
