# CLAUDE.md — WS Biller (Salesforce-native)

A standalone SFDX project. No mobile app, no sync layer, no offline mode —
Salesforce is the single system of record. Read `architecture.md` in full before
any work; it defines the schema-reuse policy, the LWC-only UI rule, and the
staged build plan this project follows.

## Before writing any metadata

1. **Check `force-app/main/default/objects/` for an existing object/field before
   creating a new one.** This project reuses a proven schema from an earlier
   version of this app — the expected object set is listed in `architecture.md`
   §A. Creating a duplicate or near-duplicate of something that already exists
   is a bug, not a shortcut.
2. If a needed object/field genuinely doesn't exist, say so explicitly before
   adding it — don't silently assume it's missing without checking.
3. If you find a field or trigger that only makes sense in a two-system,
   offline-sync context (`External_Id__c`, any placeholder/pending-assignment
   field on `Bill__c`, defensive out-of-order-write handling), flag it per
   `architecture.md` §A before deciding whether to remove it or leave it
   unused — don't carry it forward unexamined.

## Hard rules

- **No `Job_Photo__c`, no photo capture/upload, in any form.** Out of scope —
  see `architecture.md` §E. Don't wire a photo field into the Job LWC even if
  the object exists in old reference metadata.
- **Invoice numbering is atomic and synchronous at insert — no placeholder
  state.** There's no offline writer to reconcile against in this project; if
  you find yourself building a "pending" or "draft" number state, stop — that
  pattern belongs to the old mobile-sync project, not this one.
- **Stock lives directly on `Part__c.Current_Stock__c` — there is no
  `Stock_Movement__c` ledger and no per-bill audit trail.** This reverses the
  original design (removed 2026-10-10 per explicit product decision, see
  `architecture.md` §F). `PartStockService.adjustStock` is the only code path
  allowed to write `Current_Stock__c`, and it locks the affected `Part__c`
  rows with `FOR UPDATE` before applying each delta so two concurrent bill
  creations against the same part can't race. Don't reintroduce a movement
  ledger or reason/source tracking without the user asking for it back.
- **No standard object tabs or default list views as the primary UI.** Every
  staff-facing workflow is a custom LWC on a custom Lightning page, inside one
  custom Lightning App. If a stage's "UI" ends up being a standard record page
  or a default related list, that stage isn't done yet.
- **Build and test mobile-first.** Check how an LWC renders in the Salesforce
  Mobile App before polishing its desktop appearance — the reverse order tends
  to produce layouts that look fine on a laptop and are unusable on a phone.
- **Use SLDS properly** — `lightning-*` base components and SLDS utility
  classes/icons, not raw unstyled HTML or ad hoc CSS that fights the platform's
  design system. The bar is "looks like a real product," not "functionally
  works."

## Working style

- Follow the staged roadmap in `architecture.md` §D — confirm each stage's
  objective and exit criteria before starting it, don't start a stage before
  the previous one's exit criteria are met.
- Apex unit tests (`Test.startTest()/stopTest()`) are mandatory every stage,
  including concurrency tests for the invoice-numbering lock (Stage 1) and the
  stock ledger (Stage 2). Jest tests are mandatory for LWC logic from Stage 4
  onward. Show actual test output, not just a claim that tests pass.
- Log real platform issues (deploy failures, metadata quirks, anything that
  cost real debugging time) in `architecture.md` §F as they're hit, with what
  broke and what fixed it — this project should not have to rediscover a quirk
  the old project already hit once.

## Repo layout

```
<project-root>/
├── architecture.md                  ← source of truth (schema policy, UI rule, roadmap)
├── CLAUDE.md                        ← this file
└── force-app/main/default/
    ├── objects/                     ← reused schema (audit before adding)
    ├── classes/                     ← Apex: numbering, stock ledger, GST calculator
    ├── triggers/
    ├── lwc/                         ← all staff-facing UI lives here
    ├── flows/                       ← estimate approval (if Flow-based)
    └── reports/ , dashboards/       ← native, embedded into the custom app
```
