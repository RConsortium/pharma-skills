# Submission Orientation

These two steps extract and map study information from submission documents 
before any code is allowed to be generated. To help you keep track on your scratchpad, each item under the STEP is within a checklist. 

## Document Authority
Always search the files/documents before answering any study-specific 
question. Use documents in this order of authority:

- What are the endpoints, covariates, statistical methods, analysis populations, etc? → SAP 
- Which treatment variable and population flag to use? What is the appropriate dataset to use? → ADRG
- What are the PARAMCD values, visit names, variable definitions? → define.xml file 
- What do ADaM variable conventions mean (ANL01FL, ABLFL, CHG, DTYPE, etc.)? → ADaMIG 

Never rely on general knowledge for study-specific facts. GENERAL KNOWLEDGE WILL CAUSE VARIABLE MAPPING ERRORS. Always search the 
documents in the folder first.

## STEP 1 — Understand the Study. 
DO NOT skip reading the SAP or the code will fail.
For each of the following, write down exact descriptions from the SAP so that downstream tasks are easier to get right. 
Search the SAP to identify:
- [ ] PRIMARY ENDPOINT: What are the primary efficacy endpoint(s)? (exact description from SAP)
- [ ] PRIMARY ANALYSIS METHOD: What statistical method is used for the primary endpoint? (e.g., ANCOVA, t-test, MMRM, logistic regression)
    - What is the full model specification: outcome variable, treatment  
      variable, all covariates? 
      If the SAP explicitly specifies a statistical model formula or describes how variables enter the model (e.g., continuous vs categorical), capture that information. Make sure you know from the SAP or ADRG how EACH variable is used, categorical or continuous, BEFORE writing any code.The efficacy analyses section of the SAP is the best source for a full model specification — this section will likely give the outcome variable and state how each variable and covariate enters the model (continuous vs. categorical).
    - What are the exact SAP descriptions of any covariates used in the statistical model?
- [ ] PRIMARY ANALYSIS POPULATION: What analysis population is specified? (e.g., Full Analysis Set, Per Protocol, Safety, etc)
- [ ] SECONDARY ENDPOINT: What are the key secondary efficacy endpoint(s)? (exact description from SAP)
- [ ] SECONDARY ANALYSIS METHODS: What statistical methods are used for   
  secondary endpoints? (exact descriptions from SAP)
  -   What is the full model specification: outcome variable, treatment variable, all covariates?
- [ ] MEASUREMENT TIMEPOINTS: What are the baseline and endpoint visits mentioned?
- [ ] PARAMETERS: What specific clinical parameters are being measured?
- [ ] How is missing data handling done (LOCF, observed cases, etc.) [exact description from SAP]

Search the ADRG to identify:
- [ ] Which treatment variable is used for efficacy analyses? Is it continuous or categorical in the model?
- [ ] Which treatment variable is used for safety analyses? Note that we will not be dealing with safety analyses here.
- [ ] Which population flag defines the efficacy analysis population
- [ ] Which flag identifies baseline records
- [ ] Which flag identifies records selected for analysis within a visit window (e.g., ANL01FL, ANL02FL, etc)
- [ ] Which dataset contains which endpoints (multi-dataset submissions)
- [ ] Additional questions:
    1. What clinical parameters are being measured
    2. Which PARAMCD value best matches each clinical parameter?
    3. What are the baseline and endpoint timepoints

Search define.xml to identify:
- [ ] PARAMCD values for each clinical parameter
- [ ] Visit names (AVISIT values)
- [ ] Variable definitions and coded values
- [ ] For each covariate description in the SAP, identify the exact authoritative variable name 
      in define.xml that matches that description. DO NOT guess variable names — guessing will cause code to fail.
- [ ] subject-level demographic variables. Include all demographic variables 
      found — age, sex, race, and any groupings or categorizations of those.

## STEP 2 — Map Endpoints to Variables

For each endpoint, determine:
- [ ] PARAMCD value
- [ ] Endpoint visit names, including baseline if available 
- [ ] Analysis population flag
- [ ] Treatment variable (from ADRG)
- [ ] Analysis record selection flag (from ADRG)
- [ ] All model covariates (from SAP model specification and description)
- [ ] Which dataset to use (from ADRG dataset descriptions)

## Output 

Once STEP 1 and STEP 2 are complete, recording these results is required to prevent downstream errors so that downstream skills can read them (see `references/REFERENCE.md` for how these fields are used when generating code):

**MAPPED ENDPOINTS** — one entry per endpoint, with these fields:
- `cdisc_param` — the PARAMCD value for this endpoint
- `endpoint_visit` — the endpoint visit name (AVISIT value)
- `baseline_visit` — the baseline visit name (AVISIT value)
- `statistical_method` — the method named in the SAP (e.g., ANCOVA, ANOVA)
- `statistical_model` — the full model specification, including how each 
  variable enters the model (continuous vs. categorical)
- `covariates` — all covariates specified in the SAP model for this endpoint, exactly as written in SAP, followed by corresponding CDISC name from define.xml
- `dataset` — what dataset(s) is this endpoint in

**ADRG GUIDANCE** — one set of values covering all endpoints:
- `efficacy_treatment_variable` — the treatment variable to use for efficacy analyses
- `efficacy_population_flag` — the population flag defining the efficacy analysis population
- `baseline_flag` — the flag identifying baseline records
- `analysis_flag` — the flag identifying records selected for analysis within a visit window (e.g., ANL01FL)

Keep this information available for the remainder of the session and update as needed.
