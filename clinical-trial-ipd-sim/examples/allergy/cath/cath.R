# CathSim — the CATH (NCT00789880 / ADVN CATH 03-01) trial, as a TrialSim R6 subclass.
# Ported from causal_examples/allergy/cath/cath_run.py. Short VitD3-vs-placebo trial;
# endpoints are change-from-baseline skin AMP / cytokine levels, with no time-to-event.
#
# Source these in order (or just run run_cath.R): the engine R/*.R first, then cath_dag_state.R,
# cath_graders.R, cath_params.R, cath_baseline.R, cath_longitudinal.R, cath_outcomes.R,
# cath_emit.R, cath_gates.R.

CathSim <- R6Class("CathSim", inherit = TrialSim, public = list(
  prefix = "CATH", nct = "NCT00789880",
  sched = CATH_SCHED, admin_censor_day = CATH_ADMIN_CENSOR_DAY,
  emitters = CATH_EMITTERS,
  default_n = 82L, default_seed = 789880L, fixed_n = 82L,
  allowed_params = NULL,            # params come from the Step-4 JSON, not hand-edited

  default_params      = function() cath_default_params(),
  make_baseline       = function(subj_num) cath_make_baseline(subj_num, self$params),
  simulate_trajectory = function(patient, jit) cath_simulate_trajectory(self, patient, jit),
  derive_endpoints    = function(patient) cath_derive_endpoints(self, patient),
  run_dag_gates       = function(crfs_dir) cath_run_dag_gates(crfs_dir),
  measure_marginals   = function(out_dir) cath_compute_marginals(file.path(out_dir, "crfs")),
  # logical-consistency rules (defined in cath_gates.R): the engine blanks these fields where they
  # don't apply, and cath_run_dag_gates checks them again, failing the run if any slipped through.
  applicability_rules = function() CATH_APPLICABILITY_RULES,
  consistency_rules   = function() CATH_CONSISTENCY_RULES
))
