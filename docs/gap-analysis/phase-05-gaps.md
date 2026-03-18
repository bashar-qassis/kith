# Phase 05 Gap Analysis

## Coverage Summary
Phase 05 addresses all nine sub-entity types mentioned in the product spec (Notes, Life Events, Photos, Documents, Activities, Calls, Addresses, Contact Fields, Relationships). The plan is well-structured but has two missing major feature implementations, blocking dependencies on other phases, and insufficient test coverage for private notes.

## Gaps Found

1. **Documents LiveComponent missing (MEDIUM)**
   - What's missing: Phase 05 lists Documents as a sub-entity but provides NO task, acceptance criteria, UI spec, or implementation guidance
   - Spec reference: Section 2 (v1 Feature Scope, #12) — file attachments, PDFs
   - Impact: Documents are a v1 feature with no implementation plan in the phase that owns sub-entities

2. **Life Events LiveComponent missing (MEDIUM)**
   - What's missing: Phase 05 provides no TASK-05-xx for the Life Events LiveComponent (graduation, wedding, birth — hard-coded types in v1)
   - Spec reference: Section 2 (v1 Feature Scope, #6)
   - Impact: Phase 03 defines reference data seeding but Phase 05 has no UI implementation plan

3. **Activities: Ecto.Multi side effects not verified (MEDIUM)**
   - What's missing: Phase 05 assumes the Interactions context handles `Ecto.Multi` for activity creation → `last_talked_to` update + `resolve_stay_in_touch_instance/1` within the same transaction, but provides no acceptance criterion in Phase 05 to verify transactional correctness
   - Spec reference: Section 7 (Stay-in-Touch Semantics)
   - Impact: Critical for data consistency; Phase 05 delegates without verification

4. **Calls: same Ecto.Multi concern (MEDIUM)**
   - What's missing: Phase 05 assumes Calls also use `Ecto.Multi` in Interactions context for `last_talked_to` + `resolve_stay_in_touch_instance/1` but provides no acceptance criteria to verify
   - Spec reference: Section 7 (Stay-in-Touch Semantics)
   - Impact: Same as Activities — data consistency gap

5. **Photos: `size_bytes` column dependency unclear (MEDIUM)**
   - What's missing: Phase 05 specifies `size_bytes` is "required by Phase 07" but the migration for this column is not assigned to Phase 05 or any explicit task
   - Spec reference: Section 8 (Storage — MAX_STORAGE_SIZE_MB enforcement)
   - Impact: Upload validation depends on this column; blocking if missing

6. **Addresses: GeocodingWorker dependency on Phase 07 with no mock (MEDIUM)**
   - What's missing: Phase 05 depends on Phase 07's `Kith.Geocoding` module; plan notes "use a local-disk mock to unblock" but provides no mock implementation
   - Spec reference: Section 8 (LocationIQ — address → GPS)
   - Impact: Blocking dependency; Phase 05 addresses section stalls if Phase 07 is delayed

7. **Notes: private note enforcement untested (MEDIUM)**
   - What's missing: Phase 05 states private notes are visible only to the author (even admins cannot see other users' private notes), but TEST-05-01 does NOT include a scenario testing private note isolation
   - Spec reference: Section 3 (Notes — private flag)
   - Impact: Security feature not verified by test plan

8. **Notes: markdown vs rich HTML storage contradiction (LOW)**
   - What's missing: Product spec states Notes are "markdown" (Section 3) but Phase 05 specifies Trix editor storing HTML. Plan mentions sanitizing HTML but doesn't address the spec contradiction.
   - Spec reference: Section 3 (Contact entity — notes are markdown)
   - Impact: Implementation works but spec/plan don't align on storage format

9. **Photos: `is_cover` uniqueness enforcement vague (LOW)**
   - What's missing: Phase 05 says "enforced by a partial unique index or application-level guard" without specifying which approach or providing migration details
   - Impact: Implementation detail unresolved

10. **Contact Fields: protocol link validation incomplete (LOW)**
    - What's missing: Phase 05 warns against `javascript:` URLs but doesn't specify validation rules for custom protocols (e.g., website URLs must start with http/https)
    - Impact: Security concern addressed but implementation vague

11. **Relationships: bidirectional query scope not verified (LOW)**
    - What's missing: Phase 05 states the query should include both forward and reverse relationships using UNION or OR, but provides no acceptance criterion validating the query works correctly
    - Impact: Could result in showing only one direction of relationships

12. **Call directions seeding not assigned (LOW)**
    - What's missing: Phase 05 says "seed the `call_directions` table with: inbound, outbound, missed" but no migration task is assigned
    - Impact: Unclear when/where this seeding happens

## No Gaps / Well Covered

- Notes CRUD with Trix: rich text, favoritable, private indicator, sanitization, and policy checks
- Activities many-to-many: multiple contacts, emotions multi-select, side effects delegation
- Calls single contact: correctly distinguishes from activities, call directions enum and emotion support
- Addresses with geocoding: async design (non-blocking save, enqueue worker, re-geocode on edit), "Open in Maps" link
- Contact Fields clickable links: protocol mapping (mailto, tel, Twitter, LinkedIn, Instagram, Facebook, GitHub, Website), icon and type sorting
- Relationships bidirectional: forward/reverse display logic, uniqueness index, self-relationship prevention
- Phase safeguards: XSS prevention (HtmlSanitizeEx), storage limits, account isolation, Alpine.js boundary
