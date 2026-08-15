# CATH adverse-event grading (FIXED functions — never tuned). Ported from
# causal_examples/allergy/cath/graders.py. CATH AEs are either symptomatic (VitD3 GI class) or
# procedural (blood draw / tape strip / biopsy). Only the severity DRAW is tunable (ae_p_severe);
# the grade->word map and the serious rule are fixed (FDA Toxicity Grading Scale: 1 mild .. 4 death).

CATH_SEV_WORD <- c("MILD", "MODERATE", "SEVERE", "LIFE-THREATENING")  # indexed by grade 1..4

# term -> list(decod = MedDRA term, sys = body system, cls = "gi" or "proc")
CATH_AE_CATALOG <- list(
  Constipation          = list(decod = "CONSTIPATION",           sys = "Gastrointestinal disorders", cls = "gi"),
  Flatulence            = list(decod = "FLATULENCE",             sys = "Gastrointestinal disorders", cls = "gi"),
  `Abdominal bloating`  = list(decod = "ABDOMINAL DISTENSION",   sys = "Gastrointestinal disorders", cls = "gi"),
  `Abdominal discomfort`= list(decod = "ABDOMINAL DISCOMFORT",   sys = "Gastrointestinal disorders", cls = "gi"),
  `Injection site bruising`   = list(decod = "INJECTION SITE BRUISING",  sys = "General disorders and administration site conditions", cls = "proc"),
  `Application site erythema` = list(decod = "APPLICATION SITE ERYTHEMA",sys = "General disorders and administration site conditions", cls = "proc"),
  `Procedural pain`           = list(decod = "PROCEDURAL PAIN",          sys = "Injury, poisoning and procedural complications", cls = "proc"),
  `Biopsy site haemorrhage`   = list(decod = "POST PROCEDURAL HAEMORRHAGE", sys = "Injury, poisoning and procedural complications", cls = "proc")
)
CATH_GI_TERMS   <- names(Filter(function(x) x$cls == "gi",   CATH_AE_CATALOG))
CATH_PROC_TERMS <- names(Filter(function(x) x$cls == "proc", CATH_AE_CATALOG))

# FDA severity grade: severe -> 3. Grade 4 (life-threatening) is never produced (no SAEs in this trial).
cath_fda_grade <- function(is_severe) if (is_severe) 3L else (if (np_random() < 0.7) 1L else 2L)

# 'serious' means grade 4 only, which never happens here
cath_is_serious <- function(grade) grade >= 4
