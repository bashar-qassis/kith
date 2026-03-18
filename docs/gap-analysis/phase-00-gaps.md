# Phase 00 Gap Analysis

## Coverage Summary
Phase 00 is generally well-aligned with the product spec. The 5 core tasks (ERD, Frontend Conventions, Oban Transactionality, ADRs, Dependency Audit) address major architectural decisions and pre-code gates. There are 7 notable gaps where the spec describes requirements that Phase 00 doesn't explicitly gate or document.

## Gaps Found

1. **Email Configuration & SMTP Testing (MEDIUM)**
   - Missing in Phase 00: No ADR or audit task for email adapter selection or SMTP backend testing
   - Spec reference: Section 8 lists email services (SMTP, Mailgun, SES, Postmark via Swoosh)
   - Impact: Devs won't have guidance on which adapter to use first, environment variable setup, or mailpit integration testing in docker-compose.dev.yml

2. **Error Tracking / Sentry Integration Documentation (LOW)**
   - Missing in Phase 00: No ADR or configuration audit for Sentry setup
   - Spec reference: Section 13 mentions `sentry-elixir` (production only)
   - Impact: No pre-code clarity on Sentry DSN handling, filtered events, or privacy concerns for self-hosted

3. **Rate Limiting Backend Configuration Decision (MEDIUM)**
   - Missing in Phase 00: No ADR specifically deciding ETS vs Redis backend upfront
   - Spec reference: Section 9 defines `RATE_LIMIT_BACKEND` env var (ets default, redis for multi-node)
   - Impact: Dependency audit covers both, but no architectural decision explaining when/why to switch; could lead to inconsistent implementation

4. **LocationIQ / Geolocation Integration Scope (MEDIUM)**
   - Missing in Phase 00: No ADR or gate confirming LocationIQ service integration behavior
   - Spec reference: Section 8 lists LocationIQ for address → GPS; Section 9 defines `ENABLE_GEOLOCATION` flag
   - Impact: No pre-code clarity on API key handling, fallback behavior if disabled, or test fixtures for geolocation

5. **Account/Instance-Level Configuration Audit (MEDIUM)**
   - Missing in Phase 00: TASK-00-05 (dependency audit) doesn't cover environment variable defaults or instance configuration documentation
   - Spec reference: Section 9 lists 10 instance-level config variables (DISABLE_SIGNUP, SIGNUP_DOUBLE_OPTIN, MAX_UPLOAD_SIZE_KB, etc.)
   - Impact: No pre-code gate ensuring config defaults align with spec; developers must infer defaults from code review

6. **File Storage Strategy & MinIO/S3 Testing (LOW)**
   - Missing in Phase 00: No ADR or audit for local disk vs S3-compatible storage testing strategy
   - Spec reference: Section 8 specifies `ex_aws` direct wrapper (no Waffle), local disk for dev (MinIO), S3 for production
   - Impact: No pre-code guidance on docker-compose storage mocking or test fixtures; dependency audit lists packages but not storage strategy testing

7. **API Serialization & Pagination Format Standards (MEDIUM)**
   - Missing in Phase 00: No API conventions document specifying REST response format, `?include=` implementation, cursor pagination structure
   - Spec reference: Section 11 mentions REST, `?include=` compound docs, cursor pagination, RFC 7807 errors
   - Impact: Frontend conventions document covers LiveView but not API consumers; mobile app will need API docs Phase 00 should gate

## No Gaps / Well Covered

- ERD (27 tables, soft-delete scope, audit_logs non-FK, relationship uniqueness) — TASK-00-01 explicitly addresses all spec entities
- Oban transactionality & job guarantees — TASK-00-03 covers all 7 operations with pseudocode Multi pipelines
- Frontend component hierarchy & Alpine.js boundaries — TASK-00-02 fully specifies 3-level hierarchy and micro-interaction-only scope
- Authorization model (Kith.Policy.can?/3) — TASK-00-02 documents admin/editor/viewer roles and usage patterns
- Multi-tenancy & account_id isolation — ERD task explicitly requires account_id FK on all tables
- Auth stack (phx_gen_auth, assent, pot, wax) — ADR-003 gates PKCE verification; dependency audit lists all 4 libraries
- Soft-delete scope (contacts only) — ADR-006 enforces constraint; ERD task lists it
- Immich read-only & exact-name matching — ADR-007 documents constraint; spec aligned
- Reminder types & stay-in-touch semantics — Spec detailed; Phase 06 will implement; Phase 00 gates Oban foundation
- Customizable reference data (genders, relationship types, field types) — ERD lists as seeded tables with nullable account_id FKs
