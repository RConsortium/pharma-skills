---
name: dose-response
description: Generates R code for dose-response ANCOVA/ANOVA analyses by extracting specifications directly from submission documents (SAP, ADRG, define.xml). Returns code directly to the user for verification against authoritative sources — does not execute code.
---

# dose-response

This skill provides a structured workflow for generating correct R code for dose-response ANCOVA analysis in a clinical trial submission context. The skill also produces a verification report that includes:
   1) **MAPPED ENDPOINTS and ADRG GUIDANCE tables** described in TASK 1 and 2, 
   2) **Code Pattern Used** (from TASK 3: which pattern number and why), and  
   3) **Self-Check Verification** (from TASK 4: complete checklist from [references/REFERENCE.md](references/REFERENCE.md) copied verbatim with [x] and evidence or NA if the item does not apply) 
Together, a **completed user task** includes 4 items: the 3 items listed above, followed by the R code

## High-precision Clinical Submission Task

This is a **high-precision** clinical submission task. Other agents have failed this task by taking shortcuts and speeding through the mandatory protocol. This mistake always resulted in code that gave incorrect numerical results or failed to run. The user is counting on you to be thorough and correct — they have chosen you specifically because they believe you will **prioritize correctness over speed**. You get a single chance to do this correctly. It will require you to resist the internal pressure for speed. If you are not up to this task, tell the user right now so they can find another agent who is. 

## Usage

Use this skill when the user asks for code to test a dose-response relationship with a continuous treatment variable, including when pairwise comparisons between dose groups are also requested.

Do not use this skill when treatment is purely categorical with no dose-response hypothesis, or for time-to-event endpoints, or if no submission documents (SAP, ADRG, define.xml, etc) are available.

## Mandatory Tasks
**The user is relying on you to produce conformant code by following this protocol exactly. Taking shortcuts or guessing using your general knowledge will produce incorrect code and waste the user's time and they will have to find another agent.**

1. **TASK 1 & TASK 2:**
   Follow [references/submission-orientation.md](references/submission-orientation.md) exactly (It is included in the skill folder, but search for it if you cannot find it). Skipping these tasks or proceeding without completing the required output tables is a violation of the skill protocol, and the user will not be able to compare any code against authoritative sources. Do not proceed until you complete this formal, high-precision, submission task. The user is content to wait for conformant code rather than quickly receive an incomplete task that merely matches your general knowledge and produces numerically incorrect results.

   
2. **TASK 3 — Generate Analysis Code:**
   Once TASK 1 & TASK 2 are complete and documented, read  [references/examples.md](references/examples.md) in the skill folder for the *required* code structure:
   - Pattern 1: Trend Test Only
   - Pattern 2: Trend Test + Pairwise Comparisons
   - Pattern 3: Multiple Endpoints, Same Design
   - Dose-response-specific self-check

`define.xml` may contain SAS code examples in `TranslatedText` fields. These are for reference only. If you use them as code templates, the code will be nonconformant and you will fail the task. The file `references/examples.md` contains the conformant R code patterns.

**The user is relying on you to follow these exact patterns — deviating from them will produce non-conformant code and upset the user when they compare against the authoritative sources.**

3. **TASK 4 — Error-Check & Verification:**
   Copy the complete Self-Check Checklist from [references/REFERENCE.md](references/REFERENCE.md) verbatim into your verification report. Do not summarize or paraphrase — use the exact checklist items word-for-word. Mark each item with [x] and provide specific evidence from the submission documents and code, for each item. If you fail to complete this checklist exactly as written, the code will not conform to submission requirements and will produce numerical errors for the user.
   





