## Workflow

The user may request code generation related to a set of clinical trial 
submission files (SAP, ADRG, define.xml, ADaM datasets). 
When this occurs, the following STEPs must be followed completely and in order.

The first two STEPs contain the *error-prevention procedures* for extracting endpoints and mapping them to CDISC variables — general statistical or clinical knowledge is 
not a substitute for following them, because the specific variable names, 
flags, and population definitions are unique to this submission and cannot be 
guessed or assumed, or else the code will produce errors for the reviewer.

STEP 1 and STEP 2 are detailed in `references/submission-orientation.md` — you 
must read that file before extracting or mapping anything to avoid variable mapping errors. Do not proceed from memory of a similar study or general CDISC conventions or you will fail at the task. 

-  STEP 1 — `references/submission-orientation.md` contains steps for Understanding the study
-  STEP 2 — `references/submission-orientation.md` contains steps for Mapping Endpoints to Variables


-  STEP 3 — Generate Analysis Code

   LISTEN!

   -   For R, do not write a .R file to source it. That will produce an error.

   -   First, check whether a skill matches the analysis type requested (consult the 
available skills). If one matches, you must USE THE SKILL before 
writing any code — reasoning about what the skill probably says, or recalling 
it from general knowledge or a prior conversation, does NOT count. A skill 
encodes *analysis-specific instructions that prevent common coding errors* (e.g., required model structures, 
output format conventions) that are NOT part of your general statistical 
knowledge. Confidence in the general method is not a substitute for actually 
using the skill. Failing to check and use a skill will cause 
the user to run nonconformant code, and you will fail at the task!

   -   If a skill matches the analysis type: write the code using that skill's instructions and examples. Then proceed to STEP 4 before showing the code to the user.

   -   If no skill matches the analysis type: open references/REFERENCE.md now and 
write the code using its rules. Then proceed to STEP 4 before showing the code to the user.


-   STEP 4 - Code generation error-check (required before returning code)

    -   If the checklist you are about to use does not include items specific to this 
codebase (e.g., mentions of `cdisc_param`, `BASE`, `ANL01FL`, PARAMCD/AVISIT 
filtering, N-suffixed variable rules) — you have made up a generic checklist 
from training knowledge instead of reading references/REFERENCE.md. Stop and 
actually open the file. 

    -   Open `references/REFERENCE.md`, read its rules, and go through its self-check checklist at the end, item by item, against the code you already wrote. This is a check, not a rewrite — do not discard the code and start over from REFERENCE.md's other rules.

    -   If any checklist item fails, fix that specific issue in the code.

    Then, stop and present the code to the user. ALWAYS present the code to the user.

