# RaveSim: the RAVE (NCT00104299 / ITN021AI) trial as an R6 subclass of TrialSim. Mirrors
# causal_examples/autoimmune/rave/rave_run.py (RaveSim). ANCA-associated vasculitis; the endpoint
# is complete remission at 6 months (yes/no). Set the config, wire up the hooks, inherit the rest.
#
# Before this, source (in order, or just run run_rave.R): the engine R/*.R, then this trial's
# dag_state.R, rave_params.R, rave_baseline.R, rave_longitudinal.R, rave_outcomes.R,
# rave_emit.R, rave_metrics.R.

RaveSim <- R6Class("RaveSim", inherit = TrialSim, public = list(
  prefix = "RAVE", nct = "NCT00104299",
  sched = RAVE_SCHED, admin_censor_day = RAVE_ADMIN_CENSOR_DAY,
  emitters = RAVE_EMITTERS,
  default_n = 197L, default_seed = 20100715L,
  allowed_params = names(RAVE_DEFAULT_PARAMS), param_checks = RAVE_PARAM_CHECKS,

  default_params      = function() rave_default_params(),
  make_baseline       = function(subj_num) rave_make_baseline(subj_num, self$params),
  simulate_trajectory = function(patient, jit) rave_simulate_trajectory(self, patient, jit),
  derive_endpoints    = function(patient) rave_derive_endpoints(self, patient),
  run_dag_gates       = function(crfs_dir) rave_run_dag_gates(crfs_dir),
  measure_marginals   = function(out_dir) rave_compute_marginals(file.path(out_dir, "crfs"))
))
