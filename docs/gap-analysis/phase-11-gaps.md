# Phase 11 Gap Analysis

## Coverage Summary
Phase 11 plan is comprehensively aligned with the product spec. All 10 key screens from the spec are present and detailed with corresponding tasks (TASK-11-01 through TASK-11-32). RTL enforcement, component architecture, auth screens, settings sub-pages, and advanced features (Immich review, contact merge, trash) are all covered. Minor gaps exist around explicit scoping of contact create/edit and invite acceptance flow.

## Gaps Found

1. **Contact Create/Edit screens not listed as separate tasks (MEDIUM)**
   - What's missing: No dedicated frontend tasks for contact create and edit LiveViews; assumed to be embedded in TASK-11-18 (Contact Profile) but not explicitly scoped
   - Spec reference: Section 3 (Contact entity — create/edit as core feature)
   - Impact: Create/edit form complexity (dynamic contact fields, avatar upload, birthdate) warrants its own task breakdown

2. **Invite acceptance LiveView not explicitly scoped (MEDIUM)**
   - What's missing: No dedicated task for the invite acceptance screen (`/users/invitations/:token`) that users land on after clicking invite email
   - Spec reference: Section 6 (Invitation flow — accept via unique key → join account)
   - Impact: This is a pre-login unauthenticated screen; may fall between Phase 02 and Phase 11 with neither explicitly owning the UI

3. **Contact Fields display/edit in profile sidebar not sub-tasked (MEDIUM)**
   - What's missing: TASK-11-18 includes the contact profile sidebar but no explicit sub-task breakdown for inline CRUD of addresses, contact_fields, and relationships
   - Spec reference: Section 3 (Contact Profile — sub-entities in sidebar)
   - Impact: These components have non-trivial edit flows (dynamic contact field types, LocationIQ geocoding trigger, bidirectional relationship UI)

4. **Settings > Custom Data — light on detail (LOW)**
   - What's missing: TASK-11-25 (Settings — Custom Data) exists but description is minimal; no sub-task for custom genders CRUD + drag-to-reorder, contact field types CRUD
   - Spec reference: Section 8 (custom genders with drag-to-reorder; custom contact field types)
   - Impact: Implementation detail gaps; task exists

5. **Contact Merge: modal vs full page not clarified (LOW)**
   - What's missing: TASK-11-31 implies a full-page LiveView at `/contacts/:id/merge` but spec doesn't specify UI pattern
   - Spec reference: Section 11 (dry-run confirmation screen)
   - Impact: Minor spec ambiguity; full-page is a reasonable choice

6. **Activity/Calls/Notes LiveComponents not re-scoped in Phase 11 (LOW)**
   - What's missing: Notes, Activities, and Life Events LiveComponents are Phase 05 deliverables; Phase 11 lists them as dependencies but doesn't verify/re-test integration on the profile page
   - Spec reference: Section 3 (Contact Profile — tabbed view: Life Events / Notes / Photos)
   - Impact: Integration testing responsibility unclear between Phase 05 and Phase 11

7. **RTL enforcement lint check not confirmed as deliverable (LOW)**
   - What's missing: TASK-11-03 mentions "consider adding a custom Credo check or CI lint that flags banned directional Tailwind utilities" but acceptance criteria don't confirm it as a required deliverable
   - Spec reference: Phase 11 safeguards — RTL from day one
   - Impact: Soft requirement; enforcement depends on team discipline without automated check

## No Gaps / Well Covered

- All 10 key screens present: Dashboard, Contact List, Contact Profile, Upcoming Reminders, Settings (8 sub-pages), Auth screens, Immich Review, Contact Merge wizard, Trash
- RTL enforcement: Tailwind logical properties (`ms-`, `me-`, `ps-`, `pe-`) mandated from day one; Arabic locale test in TEST-11-18
- Dashboard: recent contacts, 30-day reminder count, activity feed, Immich badge, stats — all 5 sections
- Auth screens: registration, login, email verification, TOTP challenge/setup, recovery codes, WebAuthn, password reset (TASK-11-08 through TASK-11-15)
- All 8 Settings sub-pages: Profile, Security, Account (admin), Users (admin), Custom Data, Immich, Export/Import, Audit Log
- Upcoming Reminders: 30/60/90-day window selector, mark resolved/dismiss inline, role-based visibility
- Immich Review: batch confirm/reject, thumbnail display, empty state (TASK-11-30)
- Contact Merge wizard: 4 steps with dry-run preview (TASK-11-31)
- Trash: 30-day countdown, admin restore, permanent delete with confirmation (TASK-11-32)
- Component library: 11 core function components documented (TASK-11-04)
- Navigation: desktop sidebar, mobile bottom nav, active highlighting, user dropdown (TASK-11-05)
- Policy integration: authorization checks at `mount/3` and template level; viewer restrictions enforced (TASK-11-06)
- Alpine.js boundary: UI chrome only, no server state mutations
- No N+1 safeguards on dashboard and list pages; tab content lazy loading
