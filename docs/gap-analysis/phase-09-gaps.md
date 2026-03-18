# Phase 09 Gap Analysis

## Coverage Summary
Phase 09 plan is comprehensive and well-aligned with the product spec. All major import/export/merge features are defined with detailed acceptance criteria, safeguards, and E2E tests. One notable gap exists around bulk vCard export. vCard version inconsistency and Oban job cancellation semantics in merge need clarification.

## Gaps Found

1. **Bulk vCard export missing (MEDIUM)**
   - What's missing: Phase 09 only implements single-contact vCard export (TASK-09-01) and JSON export (TASK-09-03). No task covers bulk `.vcf` download (all contacts as a single vCard file).
   - Spec reference: INDEX.md cross-cutting decisions — "vCard export: single contact (`GET /api/contacts/:id/export.vcf`) and bulk (`GET /api/contacts/export.vcf`)"
   - Impact: A common user request (export all contacts as one .vcf file) is missing despite being listed in the plan index

2. **vCard export version inconsistency (MEDIUM)**
   - What's missing: TASK-09-01 specifies vCard 3.0 export; TASK-09-04 import notes say "Export always produces vCard 4.0 (RFC 6350)". Conflicting guidance within the phase.
   - Spec reference: Product spec mentions vCard exports but does not mandate a specific version
   - Impact: Implementation team will be uncertain which version to produce; should be resolved before coding

3. **Contact merge: Oban job cancellation semantics unclear (MEDIUM)**
   - What's missing: TASK-09-07 step (d) requires cancelling Oban jobs for non-survivor's reminders but doesn't specify how (delete job records? discard?). Phase 00 TASK-00-03 documents cancellation inside Ecto.Multi, but Phase 09 doesn't reference this pattern explicitly.
   - Spec reference: Phase 00 — Oban job cancellation always inside Ecto.Multi
   - Impact: Could leave dangling Oban jobs if cancellation is done outside the transaction

4. **Merge wizard: contact_fields deduplication behavior unspecified (LOW)**
   - What's missing: TASK-09-07 step (b) remaps `contact_fields` FK but does not specify whether duplicate emails/phones should be deduplicated by value or both kept
   - Spec reference: Section 2 (#11 — "sub-entities remapped")
   - Impact: If both contacts have the same email, the merged contact may have duplicate email entries

5. **vCard import: no per-contact progress indicator (LOW)**
   - What's missing: TASK-09-04 has no mention of progress tracking or live status UI for bulk imports with 100+ contacts
   - Spec reference: Spec mentions "progress + results summary" for vCard import
   - Impact: Users have no visibility into parsing progress; results summary on completion may be sufficient for v1

6. **vCard export: social profiles handling unclear (LOW)**
   - What's missing: TASK-09-01 mentions "Social profiles as `X-SOCIALPROFILE` or `IMPP` where applicable" without specifying which vCard extension to use or how to handle custom social platforms not in the vCard spec
   - Impact: Implementation detail; could affect compatibility with third-party tools

## No Gaps / Well Covered

- vCard export (single contact): TASK-09-01 detailed with fields, content type, policy, safeguards, tests
- vCard import: 3.0/4.0 parsing, new contacts only (no upsert), explicit UI warning, results summary, file size limits (TASK-09-04)
- Birthday reminder NOT auto-created on import: explicitly documented and verified in TEST-09-08
- JSON export: full account export, async handling via DataExportWorker Oban job, signed URLs with 24-hour expiry, streaming for large exports (TASK-09-03)
- Contact merge 4-step wizard: search → field selection → dry-run preview → confirm + execute (TASK-09-06 + TASK-09-07)
- Merge Ecto.Multi atomicity: remap all sub-entity FKs, relationship dedup by (account_id, contact_id, related_contact_id, relationship_type_id), soft-delete non-survivor
- Policy & role enforcement: import/export restricted to admin/editor; viewer cannot access (TEST-09-09)
- Account isolation: all import/export/merge operations scoped to account_id
