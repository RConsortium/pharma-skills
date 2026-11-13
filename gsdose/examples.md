# gsDose worked example

Source: the `Introduction` vignette of the [gsDose package](https://github.com/eric-zhang16/gsDose),
implementing Zhang & Jin (2025), doi:[10.1080/19466315.2025.2539831](https://doi.org/10.1080/19466315.2025.2539831).

The package vignette's hypothetical oncology trial, end to end. It exercises every
step of both workflows; use it as the canonical usage pattern when writing R code.
The bundled scripts automate these computations — this file shows the direct
package calls they wrap.

**Scenario** (vignette "Background"): primary endpoint OS. IA1 is the
dose-selection interim among three candidate doses vs control (30 patients/arm
enrolled, 1:1:1:1). After IA1 one dose is selected; enrollment continues 1:1 in
the selected dose + control until 700 patients total across those two arms.
IA2 and IA3 are efficacy interims at 50% and 80% information fraction; FA is at
planD = 520 OS events, alpha = 0.025 one-sided, O'Brien-Fleming spending.
Hypotheses H01/H02/H03 (dose k vs control); the selected dose is rejected only if
ALL intersections containing it are rejected (closed testing).

In skill terms: K = 3 dose arms (Q3), testing stages s = 3 — IA2, IA3, FA; the
dose-selection IA1 is NOT counted (Q7).

## 1. Stage weights w from expected events (Q10 = B / step A2)

At the first testing stage (IA2) all weight is on the data so far. Later rows are
square roots of incremental expected cohort-1 event fractions, estimated with
gsDesign2:

```r
library(gsDose)
library(gsDesign2)

w.ia2 <- c(1, 0, 0)

# design parameters
n1 <- 60       # cohort-1 patients (selected dose + control)
n2 <- 700      # total patients, selected dose + control (both cohorts)
gamma <- c(c(5, 8, 12, 18) * 2/3, 0, c(18, 25), 23)   # enrollment rates
R <- c(2, 2, 2, 4, 4, 8, 18, 1)                        # period durations (months)
lambda <- 33   # control median OS (months)
hr <- 0.74
planE <- c(260, 416, 520)   # planned events at IA2, IA3, FA

enroll    <- define_enroll_rate(duration = R, rate = gamma)
enroll.n1 <- define_enroll_rate(duration = c(2, 2, 2, 2), rate = gamma[1:4])
fail.rate <- define_fail_rate(duration = 1000, fail_rate = log(2) / lambda,
                              hr = hr, dropout_rate = 0)

# expected cohort-1 events at each analysis
l <- length(planE)
d.n1 <- rep(NA, l)
for (j in 1:l) {
  exp.ia.time <- expected_time(enroll_rate = enroll, fail_rate = fail.rate,
                               ratio = 1, target_event = planE[j],
                               interval = c(0.01, 1000))
  d.n1[j] <- expected_event(enroll_rate = enroll.n1, fail_rate = fail.rate,
                            total_duration = exp.ia.time$time, simple = TRUE)
}

d21 <- d.n1[1]; d31 <- d.n1[2]; d41 <- d.n1[3]
w.ia3 <- c(sqrt(d21/d31), sqrt(1 - d21/d31), 0)
w.fa  <- c(sqrt(d21/d41), sqrt((d31 - d21)/d41), sqrt((d41 - d31)/d41))

w <- matrix(c(w.ia2, w.ia3, w.fa), nrow = 3, ncol = 3, byrow = TRUE)
```

With these inputs, d.n1 is approximately (36.1, 44.6, 49.9) and the IA3/FA weight
rows are approximately (0.899, 0.438, 0) and (0.850, 0.414, 0.327). Each row's
squared weights sum to 1. (`scripts/compute_w_weights.R` reproduces this and also
returns the cohort-2 events planE - d.n1.)

## 2. Cohort weights h (Q5)

Proportional to each cohort's patients, the same at every analysis:

```r
h <- matrix(rep(c(sqrt(n1/n2), sqrt(1 - n1/n2)), 3), nrow = 3, ncol = 2, byrow = TRUE)
```

## 3. Design-stage efficacy boundaries (workflow A)

Expected events for both cohorts and cohort 2, planned FA events, OBF spending:

```r
d  <- planE                     # events, selected dose + control, both cohorts
d2 <- planE - ceiling(d.n1)     # expected cohort-2 events
planD <- planE[3]
s <- 3
alpha <- 0.025

gsBoundary(w, h, d, d2, s, planD, alpha, sf = 'OF', bt = 'upper')

# optional futility (lower) bound, package convention: null-based spending of
# 1 - alpha with conservative Hwang-Shih-DeCani
gsBoundary(w, h, d, d2, s, planD, alpha = 1 - alpha, sf = 'HSD', sfpar = -6,
           bt = 'lower')
```

(`scripts/compute_boundary.R` wraps this from a config JSON.)

## 4. Analysis at IA2 — boundary at actual events + combination test (workflow B)

Dose arm 2 is selected after IA1. IA2 occurs at 270 actual OS events, 231 from
cohort 2 (Q9 underway path: actual total AND actual cohort-2). Update the
boundary at the actual information fraction, then test:

```r
# boundary at IA2 (stage 1 of 3): d/d2 run only up to the current analysis;
# expected FA events enter as planD
gsBoundary(w = 1, h = h[1, ], d = 270, d2 = 231, s = 3, planD, alpha,
           sf = 'OF', bt = 'upper')
# -> Zbound = 2.90

# observed data (B-Q2..B-Q4): cohort-1 z per dose arm, cohort-1 events per arm,
# cohort-2 z for the selected dose
z1.ia2 <- matrix(c(0.8, 1, 0.7), nrow = 1, byrow = TRUE)
d1.ia2 <- matrix(c(40, 36, 38), nrow = 1, byrow = TRUE)
z2.ia2 <- 2.01

combTest(w = 1, h = h[1, ], z1.ia2, d1.ia2, z2.ia2, sid = 2, zbound = 2.9)
```

None of the intersections containing H02 are rejected, so there is no efficacy
claim at IA2 and the trial continues.

## 5. Analysis at IA3 — rejection

IA3 is triggered at 430 events (385 from cohort 2). Cumulative inputs now carry
two rows:

```r
gsBoundary(w = w[1:2, 1:2], h = h[1:2, ], d = c(270, 430), d2 = c(231, 385),
           s = 3, planD, alpha, sf = 'OF', bt = 'upper')
# -> Zbound at IA3 = 2.22

z1.ia3 <- matrix(c(0.8, 1,   0.7,
                   0.9, 1.2, 0.81), nrow = 2, byrow = TRUE)
d1.ia3 <- matrix(c(40, 36, 38,
                   51, 42, 49), nrow = 2, byrow = TRUE)
z2.ia3 <- 2.35

combTest(w = w[2, 1:2], h = h[2, ], z1.ia3, d1.ia3, z2.ia3, sid = 2, zbound = 2.22)
```

All intersections containing H02 reject (combination Z 2.39–2.60 vs 2.22), so
H02 is rejected: dose 2 is declared superior to control in OS.
(`scripts/compute_test.R` wraps this and writes the decision.)
