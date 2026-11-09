# Submission Orientation

The two MANDATORY tasks below extract and map study information from submission documents (SAP, ADRG, etc)
before any code is allowed to be generated. Each item under the TASK is within a checklist. 

**Skipping sections or using targeted searches will miss critical variable construction rules, resulting in code that is non-conformant and numerically incorrect if run. The user will check your code against authoritative sources.**

**Variable mappings must be extracted from authoritative source documents (SAP, ADRG, define.xml). Guessed or assumed values will cause code failures and violate the skill protocol.**

**This is a very important charge you have. STAY. ON. TASK. Take it seriously. It is much different from a generic coding query.**


## Document Authority
Always search the files/documents before answering any study-specific 
question below. Use documents in this order of authority:

- What are the endpoints, covariates, statistical methods, analysis populations, etc? → SAP 
- Which treatment variable and population flag to use? What is the appropriate dataset to use? → ADRG
- What are the PARAMCD values, visit names, variable definitions? → define.xml file 
- What do ADaM variable conventions mean (ANL01FL, ABLFL, CHG, DTYPE, etc.)? → ADaMIG 

Never rely on general knowledge for study-specific facts. GENERAL KNOWLEDGE WILL CAUSE VARIABLE MAPPING ERRORS. Always search the 
documents in the folder first. 


## TASK 1 — Understand the Study. 
Read the entire SAP from start to finish during this TASK. Do not use `pdftotext` (it mangles tables). `pypdfium2` with `page.get_textpage().get_text_range()` is recommended for PDF reading. Extract the **ENTIRE** SAP for later searching! (Extraction into a .txt file may help)

Check for a .venv first because the user will be very upset if you work in their base env!!

Searching or grepping must be done thoroughly to get *every single* instance, not just the first instance or first couple instances! 
Thorough searching translates to conformant code in this high-stakes clinical trial context. 

As you read, answer the following questions. **DO NOT WRITE ANY CODE until you have completed the check boxes and documented your results. Correct variable mappings cannot be determined without completing these steps.** Each item MUST use a fresh `grep` or else you will not find the answer.

- [ ] PRIMARY ENDPOINT: What are the primary efficacy endpoint(s)? (exact description from SAP)
- [ ] PRIMARY ANALYSIS METHOD: What statistical method is used for the primary endpoint? (e.g., ANCOVA, t-test, MMRM, logistic regression)
    - [ ] What is the full model specification: outcome variable, treatment variable, all covariates? 
      If the SAP explicitly specifies a statistical model formula or describes how variables enter the model (e.g., continuous vs categorical), capture that information. Make sure you know from the SAP or ADRG how EACH variable is used, categorical or continuous, BEFORE writing any code. The efficacy analyses section of the SAP is a good source for the model specification and how each variable and covariate enters the model (continuous vs. categorical), but you must also check the general statistical considerations, data handling conventions, and appendix table shells. These sections often contain critical rules for variable construction, data aggregation, or outcome definitions that are not found in the main analysis text.
    - [ ] What are the exact SAP descriptions of any covariates used in the statistical model?
- [ ] MEASUREMENT TIMEPOINTS: What are the baseline and endpoint visits mentioned?
- [ ] PARAMETERS: What specific clinical parameters are being measured?    
- [ ] PRIMARY ANALYSIS POPULATION: What analysis population is specified? (e.g., Full Analysis Set, Per Protocol, Safety, etc)
- [ ] Run a new grep on the full SAP using each of the following keywords separately: "pool*", "multi-center", "site", "grouped" to find out if a site
      variable must be entered as a pooled version. DO NOT REUSE previous grep results.
- [ ] Run a new grep on the full SAP using each of the following keywords separately: "missing data", "MAR", "imputation", etc. to find out whether a 
      particular missing data handling was used. DO NOT REUSE previous grep results.
- [ ] SECONDARY ENDPOINT: What are the key secondary efficacy endpoint(s)? (exact description from SAP)
- [ ] SECONDARY ANALYSIS METHODS: What statistical methods are used for   
  secondary endpoints? (exact descriptions from SAP)
  -   [ ] What is the full model specification: outcome variable, treatment variable, all covariates? Follow the advice given above for primary 
          analysis method.

Search the ADRG to identify:
- [ ] Which treatment variable is used for efficacy analyses? Is it continuous or categorical in the model?
- [ ] Which population flag defines the efficacy analysis population
- [ ] Which flag identifies baseline records
- [ ] Which flag identifies records selected for analysis within a visit window (e.g., ANL01FL, ANL02FL, etc)
- [ ] Which dataset contains which endpoints?
      - [ ] Once you identify the target dataset, print the column names by running `head -n 1 <dataset>.csv` or equivalent. 
            Also print the unique values of the PARAMCD column. You will use this information to **verify every variable and PARAMCD you map**.
- [ ] Additional questions:
    1. What clinical parameters are being measured
    2. Which PARAMCD value in `define.xml` best matches each clinical parameter? Is it in the dataset? If not, you either have the wrong dataset or
       the wrong PARAMCD value.



## TASK 2 — Map Endpoints to Variables

Search the entire `define.xml` for the following:
- [ ] For each variable used in the analysis (PARAMCD, AVISIT, population flags, analysis flags, covariates, etc), find the exact variable name and coded values in the `define`.xml file (try, e.g., `ItemDef`, `adamref`, `CodeList`). Match covariates by literal description or functional intent from the SAP. 
- [ ] Confirm the PARAMCD values identified from the SAP exist in define.xml with the correct definitions (matching the endpoint). 
- [ ] Confirm the visit names (AVISIT values) identified from the SAP exist in define.xml with the correct definitions.
- [ ] Confirm that any site-related variables identified from the SAP exist in define.xml with the correct definitions.
- [ ] Locate all subject-level demographic variables, such as age, sex, race, and any groupings or categorizations of those.
- [ ] Locate all site variables used in the target dataset and find their definitions in define.xml. 
- [ ] STOP!: **DATASET VERIFICATION:** For **every** variable (PARAMCD value, covariates, flags, outcomes, analysis populations, demographics, visits, sites), you must verify RIGHT NOW it actually exists in the target dataset. Do not map a variable that does not exist in the data. If you do, the code will give "Error"! This step makes or breaks any code you write.


## Output 

Once TASK 1 and TASK 2 are complete, **you must produce and display the following tables in the chat before proceeding**: 

**MAPPED ENDPOINTS** — one entry per endpoint, with these fields:
- `cdisc_param` — the PARAMCD value for this endpoint (along with its **exact** description in the SAP). 
   Quote the exact entry from `define.xml` that confirms this PARAMCD exists, and verify it appears in the actual dataset by inspecting the PARAMCD column in the CSV file.
- `outcome_variable(s)` - Is the outcome variable the raw value (AVAL), change from baseline (CHG), or something else? Verify in define.xml.
- `endpoint_visit` — the endpoint visit name (AVISIT value)
- `baseline_visit` — the baseline visit name (AVISIT value)
- `statistical_method` — the method named in the SAP (e.g., ANCOVA, ANOVA, t-test, etc)
- `statistical_model` — the full model specification, including how each 
  variable enters the model (continuous vs. categorical)
- `covariates` — all covariates specified in the SAP model for this endpoint, exactly as written in SAP, 
   followed by corresponding CDISC name from `define.xml`
- `pooling of sites` — Quote any rule from the SAP or `define.xml`. If a site grouping variable appears in the dataset, 
   name that variable here. It should be used in analyses instead of SITEID. 
- `dataset` — what dataset(s) is this endpoint in? 

**grep results**
- `site pooling`: give the exact results found in the SAP
- `missing data handling`: give the exact results found in the SAP

**ADRG GUIDANCE** — one entry per endpoint, with these fields:
- `efficacy_treatment_variable` — the treatment variable(s) to use for efficacy analyses
- `efficacy_population_flag` — the population flag(s) defining the efficacy analysis population
- `baseline_flag` — the flag(s) identifying baseline records
- `analysis_flag` — the flag(s) identifying records selected for analysis within a visit window (e.g., ANL01FL)

Keep this information available for the remainder of the session and update as needed.
As this information is the source for the code you will generate, it is paramount to be correct and verified against the submission documents to avoid non-conformance when the user audits the code against the authoritative sources.

If you rushed through this important process, go through it again in order to complete the task. The user will wait for correct code, but will be very upset if it is non-conformant when compared against the authoritative documents.
