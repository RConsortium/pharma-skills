# RNG layer — getting the draw order right is the key correctness rule of this port.
#
# Two pieces:
#   1. Single-draw wrappers named after numpy's functions. Drawing one value at a time, in the same
#      order, is what keeps per-patient frailties shared across equations and keeps the date fixes
#      from disturbing the calibrated marginals.
#   2. new_substream(): a separate per-patient jitter stream, keyed on (seed, subj_num), that never
#      touches the main draw order. Every visit-date / AE-onset / discontinuation-day jitter draw
#      goes through it.
#
# NOTE (see README / r_implementation.md): R's Mersenne-Twister cannot reproduce numpy's PCG64
# bitstream, so this port is not byte-identical to the Python. It is a re-implementation with its own
# reproducible draws, re-calibrated in R to the same targets.

# ---- numpy-compat single draws (half-open where numpy is half-open) ----------------------------
np_random      <- function() runif(1)                          # np.random.random()  -> [0,1)
np_uniform     <- function(a = 0, b = 1) runif(1, a, b)         # np.random.uniform(a,b)
np_normal      <- function(mu = 0, sd = 1) rnorm(1, mu, sd)     # np.random.normal(mu,sd)
np_exponential <- function(mean = 1) rexp(1, rate = 1 / mean)   # np.random.exponential(mean)
np_lognormal   <- function(mu = 0, sigma = 1) exp(rnorm(1, mu, sigma))  # np.random.lognormal
np_binomial    <- function(n, p) as.integer(rbinom(1, n, p))    # np.random.binomial(n,p)
np_poisson     <- function(lam) as.integer(rpois(1, lam))       # np.random.poisson(lam)
np_gamma       <- function(shape, scale = 1) rgamma(1, shape = shape, scale = scale)
np_beta        <- function(a, b) rbeta(1, a, b)

# np.random.integers(low, high) -> half-open [low, high)
np_integers <- function(low, high) low + as.integer(floor(runif(1) * (high - low)))

# np.random.choice(x, p=) -> one element
np_choice <- function(x, prob = NULL) if (length(x) == 1L) x[[1]] else sample(x, size = 1, prob = prob)

# Bernoulli as numpy code usually writes it: rng.random() < p
np_bernoulli <- function(p) as.integer(runif(1) < p)

# ---- independent per-patient jitter substream --------------------------------------------------
# Returns an environment whose $draw(fn) runs fn() under a private RNG state keyed on (seed,
# subj_num), leaving the caller's global .Random.seed exactly as it was. Deterministic per subject
# and independent of how many draws the main stream has taken, so adding/removing a date-jitter call
# never shifts a single main-stream draw.
new_substream <- function(seed, subj_num) {
  e <- new.env(parent = emptyenv())
  saved <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  # well-mixed private seed (double math avoids 32-bit integer overflow, then fold into int range)
  priv <- as.integer((as.double(seed) * 2654435761 + as.double(subj_num) * 40503 + 12345) %% .Machine$integer.max)
  set.seed(priv)
  e$state <- get(".Random.seed", .GlobalEnv)
  if (is.null(saved)) rm(".Random.seed", envir = .GlobalEnv) else assign(".Random.seed", saved, envir = .GlobalEnv)
  e$draw <- function(fn) {
    outer <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
    assign(".Random.seed", e$state, envir = .GlobalEnv)   # swap in the private stream
    val <- fn()
    e$state <- get(".Random.seed", .GlobalEnv)            # persist how far it advanced
    if (is.null(outer)) rm(".Random.seed", envir = .GlobalEnv) else assign(".Random.seed", outer, envir = .GlobalEnv)  # restore main
    val
  }
  e
}
