# WS Biller (Salesforce-native) — Architecture & Roadmap

A standalone Salesforce project: a car workshop billing app that lives **entirely
inside Salesforce** — no separate mobile codebase, no sync layer, no offline mode.
Staff use the native Salesforce Mobile App (custom LWC components) and Lightning
Experience on desktop. Salesforce is the single, permanent system of record.

This is a from-scratch org, but **not a from-scratch schema or business-logic
design** — it reuses the proven schema, GST math, invoice-numbering pattern, and
stock-ledger pattern from an earlier Flutter+Salesforce-sync version of this app.
What's new here is removing everything that existed only because of that old
two-system split, and building a proper custom **LWC-first UI** in its place.

---

## 0. One-paragraph summary

The org already has (or will be audited for) the core objects this app needs —
**reuse what exists in `force-app/main/default/objects/` before creating anything
new**; only add objects/fields genuinely missing from that existing schema. On top
of that schema, every user-facing workflow — billing, estimates, the jobs board,
reports — is a **custom LWC**, assembled into one cohesive custom Lightning App.
Staff should never need to touch a standard object tab or default Salesforce list
view; the whole experience is purpose-built, mobile-first, and visually consistent
with the Salesforce Lightning Design System (SLDS) so it feels like a real product,
not a stock CRM. Photo capture/upload is explicitly **out of scope** for this build.
Two invariants carry over unchanged from the earlier project and matter even more
now that Salesforce is the *only* writer: invoice numbers are assigned atomically
and sequentially at creation time (no placeholder/reconciliation state — there's
no second system to reconcile against), and inventory stock is always a **derived**
sum over an append-only movement ledger, never a directly-writable field.

---

## A. Schema policy — reuse first

Before any stage below creates a new object or field, **audit
`force-app/main/default/objects/` for an existing match**. The expected core set,
carried over from the prior project (confirm exact API names/fields against the
actual metadata, don't assume):

`Workshop_Profile__c` · `Customer__c` · `Vehicle__c` · `Part__c` ·
`Job_Status_Stage__c` · `Job__c` · `Job_Mechanic__c` ·
`Mechanic__c` · `Surveyor__c` · `Bill__c` · `Bill_Line_Item__c` ·
`Bill_To_Party__c` · `Payment__c` · `Estimate__c` · `Estimate_Line_Item__c`

`Stock_Movement__c` was part of this list through Stage 2 but was removed
2026-10-10 — see §F. Stock now lives directly on `Part__c.Current_Stock__c`.

`Vehicle_Make_Model__c` was added 2026-10-10 (§F, Nineteenth) — a pure
autocomplete-suggestion table for the vehicle Make/Model fields. `Vehicle__c`
itself has no lookup to it.

**Fields/objects that existed only for the old mobile-sync split should be
identified and either removed or left unused, not ported forward as-is**:
`External_Id__c`, any `pending_number_assignment`/placeholder-style field on
`Bill__c`, any trigger or validation logic written defensively around
out-of-order sync writes. Flag each one found before changing it.

`Job_Photo__c` and any photo-capture/upload logic: **explicitly out of scope**
for this build — do not create it, do not wire it into the Job LWC, even if it
exists in the reference metadata.

**Stage 0 resolution (2026-10-02):** audited the reference metadata at
`D:\WS_biller\salesforce\force-app\main\default\` against this project's
schema (`D:\SF_WSBiller\SF_WSBiller\force-app\main\default\`, already
deployed 1:1 to the `SF_WSBiller` org). Removed, from local source and from
the org:
- `External_Id__c` — present on all 17 objects, pure sync-match-key, dropped everywhere.
- `Is_Deleted__c` — present on 15 of 17 objects, soft-delete flag for offline reconciliation, dropped everywhere (Salesforce's own delete/recycle bin replaces it).
- `Bill__c.Pending_Number_Assignment__c` — the placeholder field this file already called out; dropped along with the reference project's `InvoiceNumberingService.reconcilePlaceholder()` and `InvoiceNumberRestService` REST endpoint (neither ported — both existed solely for the Flutter app to request/reconcile numbers over HTTP).
- `Job_Photo__c` — entire object, tab, app nav entry, and permission-set grants removed (hard rule, §E).
- `Estimate__c.Signature_Path__c`, `Workshop_Profile__c.Logo_Path__c`, `Workshop_Profile__c.Signature_Path__c` — same shape as `Job_Photo__c.File_Path__c` (a local device file path from the Flutter app), not covered by an explicit hard rule but matching the same sync-era pattern; dropped. Re-add as real Salesforce Files if/when estimate sign-off or workshop branding features need them.

Kept as-is: `Part__c.Current_Stock__c` and `Part__c.Is_Oversold__c`. As of
2026-10-10 (§F) `Current_Stock__c` is a directly-written field — the
`Stock_Movement__c` ledger this paragraph originally described has been
removed. `PartStockService.adjustStock` is the sole code path that writes it.

---

## B. UI principle — LWC end-to-end, no standard tabs

This is a hard constraint, not a preference to balance against convenience:

- **No standard object tabs, no default list views, no out-of-the-box record
  pages as the primary way staff interact with data.** Every workflow — creating
  a bill, moving a job through its stages, approving an estimate, looking up a
  part — is a **custom LWC** on a **custom Lightning page**, assembled into **one
  custom Lightning App** with its own custom navigation items.
- Standard objects/record pages may still exist underneath (Salesforce requires
  this for data storage and admin/reporting access), but staff's day-to-day
  navigation should never surface them — the custom app *is* the product.
- **Design quality is a real requirement, not polish-later**: use SLDS
  components/styling (`lightning-*` base components, SLDS utility classes,
  SLDS icons) rather than raw unstyled HTML, so the app looks native to
  Salesforce and professional, not like an unstyled internal tool. Favor
  card-based layouts, clear visual hierarchy, and touch-friendly target sizes
  given the Salesforce Mobile App is the primary surface for field/counter
  staff.
- **Mobile-first, explicitly.** Build and test every LWC against the Salesforce
  Mobile App's rendering first, then confirm it still works well on desktop
  Lightning Experience — not the reverse. Use the Mobile App's native
  capabilities where relevant (barcode scanner API for part lookup) rather than
  a generic web-based scan workaround.
- Reports/Dashboards (native Salesforce) are the one deliberate exception to
  "no standard Salesforce surfaces" — but should still be **embedded into the
  custom app's navigation** (e.g., a dashboard component on an LWC-built home
  page) so staff never have to leave the custom app to see them.

---

## C. The two carried-over invariants

### C.1 — Invoice numbering: atomic, no placeholder state

Unlike the old split-system version, there is now exactly one writer, so this is
simpler than before — but still needs real concurrency protection, since two
staff members (or two tabs) can submit a bill at nearly the same moment.

- Number assigned **synchronously, at insert, in the same transaction**, via a
  locking read (`FOR UPDATE`-equivalent — a `SELECT ... FOR UPDATE` on a
  per-financial-year counter record) so two concurrent inserts can never
  receive the same number or skip one.
- No `pending_number_assignment` field, no reconciliation logic — that
  complexity existed solely for the offline-mobile case, which doesn't exist
  here. If any such field is found in the reused schema, remove it.

### C.2 — Inventory stock: direct field, no ledger (revised 2026-10-10)

**Superseded design, kept here for history:** stock was originally derived
from an append-only `Stock_Movement__c` ledger via aggregate SOQL, so every
restock/correction/bill-deduction was individually traceable. That object,
its trigger, and the `PartStockService.recomputeStock`/`BillStockService`
ledger-insert logic were removed 2026-10-10 at the user's explicit request —
see §F for the full rationale and the row-locking replacement.

**Current design:**

- `Part__c.Current_Stock__c` is written directly. There is no ledger and no
  per-bill audit trail — intentionally, per the user's request not to trace
  which bill deducted which part.
- `PartStockService.adjustStock(Map<Id, Decimal> deltaByPartId)` is the only
  code path allowed to write it. It locks the affected `Part__c` rows with
  `FOR UPDATE` before adding each delta — the same lock-then-read-then-write
  shape as `InvoiceNumberingService`/`PaymentStatusService` — so two
  concurrent bill creations against the same part serialize instead of one
  silently clobbering the other's deduction. This is what replaces the old
  ledger's concurrency safety now that there's no aggregate recompute to
  fall back on.
- `BillStockService` aggregates each bill's line-item deltas per part
  **before** calling `PartStockService.adjustStock`, so multiple lines
  against the same part in one transaction net out to a single delta rather
  than racing against each other inside the same request.
- Negative stock is still allowed, not blocked (two legitimate concurrent
  deductions can both be valid) — `Is_Oversold__c` (a formula on
  `Current_Stock__c`) still flags it rather than rejecting the transaction.

### C.3 — GST type: per-part default, per-line override (not state-based)

Confirmed 2026-10-02: CGST+SGST vs IGST is **not** derived from comparing
customer state to workshop state (an earlier draft of this document assumed
that, and the reference project's own contract never decided either way —
it scoped IGST out entirely). The actual rule:

- `Part__c.Gst_Type__c` (picklist: `CGST_SGST` / `IGST`, default `CGST_SGST`)
  holds each part's default GST treatment.
- When a line is added to a bill or estimate, `Bill_Line_Item__c.Gst_Type__c`
  / `Estimate_Line_Item__c.Gst_Type__c` is copied from the part's value —
  staff can see and change it per line at creation time.
- Each line's GST type is independent: a single bill can legitimately mix
  CGST+SGST parts with IGST parts, and `GstCalculatorService.calculateBill`
  sums both buckets correctly across mixed-type lines (see
  `GstCalculatorInterstateTest.calculateBill_mixedSupplyTypesWithinOneBill_eachLineTaxedIndependently`).
- The copy-from-part-and-override wiring itself (reading `Part__c.Gst_Type__c`
  when a line is created) is Stage 4/5 billing-LWC work, not Stage 3's
  calculator — Stage 3 only needed the field to exist and the calculator to
  accept a per-line supply type.

### C.4 — No approval process; versioning instead (confirmed 2026-10-03)

§E's original default (a simple status-field transition, as a lighter-weight
stand-in for native Salesforce Approval Process) turned out to be the wrong
question — the client doesn't want an approve/reject workflow on estimates
at all. The actual, confirmed model for **both** `Estimate__c` and `Bill__c`:

- Create and save — no approval step.
- "Changing" an existing estimate or bill never edits it in place. It always
  creates a **new record** that supersedes the one it's based on:
  `Previous_Version__c` (self-lookup) links to what it supersedes,
  `Root_Estimate__c`/`Root_Bill__c` (self-lookup, null on the first version)
  lets the whole chain be fetched in one query instead of walking
  `Previous_Version__c` recursively, `Version_Number__c` numbers it for
  display, and `Is_Latest_Version__c` flips to false on the superseded
  record the moment a new version is created.
- Each version gets its own real, incrementing document number for free,
  simply because it's a genuinely new record — `Bill__c.Invoice_Number__c`
  via Stage 1's existing atomic locking (completely unaffected by any of
  this: immutability of an *assigned* number was never in question, only
  whether editing in place vs. creating new was the right model — it's the
  latter), and `Estimate__c.Name` via its existing AutoNumber field
  (`EST-{0000}`), already reusable schema needing zero new numbering logic.
- `Bill_Date__c` / `Estimate_Date__c` (new fields, defaulting to `TODAY()`)
  are freely staff-editable independently of `CreatedDate`, confirmed
  explicitly as a requirement.
- Versioning a **bill** has a real side effect versioning an estimate
  doesn't: inventory. `BillController.createNewVersion` reverses the
  superseded version's stock deductions (`BillStockService`, the same
  mechanism a line deletion already used) before the new version's own line
  items deduct again — otherwise a near-identical new version would double-
  count both bills' worth of parts against stock.
- Payments are deliberately **not** carried forward to a new bill version —
  they stay on the superseded bill for its own audit trail; the new version
  starts Unpaid. This is a judgment call, not something the client specified
  either way — revisit if it turns out payments should transfer.
- Converting an estimate to a bill: `Bill__c.Source_Estimate__c` (new field)
  records which estimate (and which specific version) a bill came from;
  `Estimate__c.Status__c` gains a `Converted` value, set automatically when
  a bill is created from that estimate. The conversion itself just prefills
  the billing LWC's line items from the estimate's — nothing about the
  estimate becomes immutable or special at that point, a further version of
  it can still be created independently.
- Editing an **existing, already-saved** version's line items in place
  (as opposed to superseding the whole record with a new version) is not
  supported, by design — it would reopen exactly the stock-double-counting
  problem versioning was built to avoid, for no real benefit over "just make
  a new version."

---

## D. Development roadmap & implementation sequence

Exact object/field names are Claude Code's decision, made by reading the actual
reused schema first (§A) — the stages below describe required behavior and exit
criteria, not field-level schema.

| # | Stage | Objective | Key components | Depends on | Tests | Exit criteria |
|---|---|---|---|---|---|---|
| 0 | **Schema audit & gap-fill** | Confirm which objects/fields already exist and match this app's needs; add only genuinely missing pieces; identify and flag sync-era fields for removal | Review of `force-app/main/default/objects/*`; gap-fill object/field metadata only where needed | — | Deploy succeeds clean against a fresh org; manual record creation per object | Full object model confirmed present and correct; sync-era fields explicitly listed and resolved (removed or left unused, documented) |
| 1 | **Invoice numbering (atomic)** | Race-safe sequential assignment at insert, no placeholder state | Apex trigger/class with locking read on a per-FY counter | Stage 0 | Apex concurrency test: N simultaneous bill inserts → N unique sequential numbers, zero collisions/gaps | Verified under simulated concurrent creation |
| 2 | **Stock ledger** | Append-only movements, aggregate-derived current stock | Trigger/class using aggregate SOQL, no per-row Apex loops | Stage 0 | Concurrency test: simultaneous movements from "different sources" all persist; negative-stock flag fires correctly | Derived stock always correct under concurrent writes; no governor-limit risk at realistic volume |
| 3 | **GST calculator** | CGST/SGST vs IGST per §C.3 (part-level default, per-line override — not state-based); intra-state math at exact parity with prior project's logic | Apex class, verified against supplied test vectors | Stage 0 | Run every supplied test vector, assert exact match | 100% of test vectors pass |
| 4 | **Billing — LWC** | Create/edit a bill end-to-end: line items, optional Bill-To-Party, payments | Custom LWCs + custom Lightning page, SLDS styling, mobile-first | Stages 1–3 | Jest tests for LWC logic; manual UAT in Salesforce Mobile App | A bill is fully created and paid from a phone, GST correct, number assigned atomically, no standard tab touched |
| 5 | **Estimates + versioning + PDF** | Estimate/line items (no approval flow — §C.4); versioning for both estimates and bills; convert an estimate to a bill; PDF generation for both | `estimateCreate` LWC (+ `billCreate` extended for versioning/estimate-conversion), `EstimateController`/`BillController` versioning methods, `InvoicePdfController`/`InvoicePdf.page` (Visualforce PDF) | Stage 4 | Apex tests for versioning/conversion/stock-reversal logic; Jest tests for LWC logic; manual UAT: generate and visually check a PDF (byte-level rendering can't be asserted in an Apex test) | An estimate converts cleanly into a bill from the custom LWC flow; a new version of either gets its own incrementing number without disturbing the one it supersedes; PDF renders correctly for both document types, including mixed CGST+SGST/IGST lines |
| 6 | **Jobs pipeline — Kanban LWC** | Custom board driven by admin-editable `Job_Status_Stage__c` records (not a fixed picklist), mechanic/surveyor assignment | Custom Kanban LWC (drag-and-drop where feasible, tap-to-advance as mobile fallback) | Stage 0 | Manual UAT: move a job through all configured stages on mobile and desktop | Job board fully usable on phone; stage changes persist correctly; no reliance on Path or standard Kanban list views |
| 7 | **Reports & dashboards** | Revenue summary, mechanic-wise job counts, low-stock report | Native Salesforce Reports (+ `Is_Low_Stock__c` formula field, + a hand-authored `Mechanics_with_Jobs__c` custom report type since the junction object gets none automatically) | Stages 1–6 (needs real data to validate against) | Compare report totals to a seeded dataset (seeded 2026-10-03; verified via direct SOQL reconciliation and by running each report over REST) | **Partially met** — Revenue Summary and Low Stock Parts are built, deployed, and verified exact against seeded data; Mechanic Job Counts deployed but without a working Mechanic-name column/grouping (real, reproducible metadata-API limitation, not a syntax error — see §F); the combined Dashboard was not hand-authored via metadata (see §F) but the exit criterion "accessible without leaving the custom app" is still met via the pre-existing `standard-report`/`standard-Dashboard` tabs |
| 8 | **End-to-end UAT & polish pass** | Full workflow regression + UI/UX consistency review | `BillController.createCustomer`/`EstimateController`+`JobController` customer-creation and job-linkage additions (see below — this stage's own regression pass found and fixed two real gaps, it didn't just confirm existing behavior) | All above | Live end-to-end script through the real deployed controllers: new customer → job → estimate → convert to bill → payment (no "approval" step — removed per §C.4); automated Apex (98/98) + Jest (29/29) regression; manual on-phone walkthrough still needed from the user, can't be done from here | Met for everything verifiable from this side: no custom-app step requires a standard tab (the regression pass found and closed the one real gap — customer creation — that would have forced one); UI/UX consistency reviewed and one real inconsistency fixed (search-result row styling in `jobBoard` didn't match `billCreate`/`estimateCreate`); governor-limit usage checked on the full live chain (21 SOQL queries, 195 of 10,000 CPU time) — no warnings. **Still needs you:** the actual on-phone walkthrough in the Salesforce Mobile App — the exit criteria explicitly call for mobile verification, which isn't something achievable from this environment |
| 9 | **Full custom navigation — close the "related list" gap** | User-reported regression after using the Stage 8 build on-device: the app's nav still exposed standard object tabs (`Customer__c`, `Vehicle__c`, `Part__c`, `Mechanic__c`, `Surveyor__c`, `Bill_To_Party__c`, `Job_Status_Stage__c`, `Workshop_Profile__c`, …), so creating a vehicle under a customer, or adding a part to an estimate's related list, still routed through standard record pages — a direct violation of §B. Closed by building an LWC for every one of those screens and removing every standard object tab from the app's nav entirely | 5 new Apex controllers (`CustomerController`, `PartController`, `DirectoryController`, `WorkshopProfileController`, `JobStageController`) + `BillController.listBills`; 13 new LWCs (`customerList`, `customerDetail`, `inventoryList`, `inventoryDetail`, `billingList`, `moreMenu`, `directoryMenu`, `mechanicList`, `surveyorList`, `billToPartyList`, `settingsMenu`, `workshopProfile`, `jobStages`) + matching custom tabs/FlexiPages; `WS_Biller.app-meta.xml` nav rebuilt to 5 primary tabs (Jobs, Customers, Billing, Inventory, More) matching the reference app's bottom-nav structure, with every secondary screen reached by in-app navigation from there | Stages 4–8 | Apex: 129/129 passing (`sf project deploy ... --test-level RunLocalTests`). Jest: 59/59 passing across all 17 LWC bundles. Live sanity script against the real deployed org exercised every new controller end-to-end (customer list/detail/vehicle-add, part list/detail/create/adjust-stock, mechanic/surveyor/bill-to-party create+toggle, workshop profile get/save singleton, job stage create/reorder, bill list all/dues-only) with zero exceptions and governor-limit usage nowhere close to a warning; sanity-check records deleted afterward | All Stage 4–8 screens now reachable without a single standard-tab hop — vehicles are added inline from Customer Detail, parts are added inline from Inventory, mechanics/surveyors/bill-to-parties each get their own list+create LWC, Workshop Profile and Job Stages (admin-only screens previously only reachable via their standard tabs) are now custom LWC forms. Deliberately **not** carried over from the reference Flutter app's Settings screen: Backup, Google Account, PIN Lock, Salesforce Sync, Device ID — these are sync-era/second-writer concepts that don't apply to this Salesforce-only, single-writer app (§E) and were dropped rather than built. Job-stage reordering uses up/down buttons instead of drag-and-drop — more reliable on a touch/LWC surface and the only reorder operation the UI actually needs. **Still needs you:** the on-phone walkthrough of this new navigation in the Salesforce Mobile App (same caveat as Stage 8) |

---

## E. Explicitly out of scope

- Photo capture/upload (`Job_Photo__c` or equivalent) — not built in this phase.
- Any mobile-sync concept: `External_Id__c`, offline queues, placeholder/
  reconciliation states, Drive-style backup/restore. None of this applies —
  Salesforce's own org-level data protection is sufficient.
- Any approval workflow for estimates at all — confirmed out of scope
  2026-10-03 (§C.4). Neither native Approval Process nor a custom Flow/
  status-field approve-reject transition is built; estimates are created and
  saved directly, with versioning (not approval) as the mechanism for
  "this estimate changed."

---

## F. Platform gotchas log

Keep this section running as real issues are hit during the build (the old
project's own `architecture.md` logged its share — e.g., metadata elements that
silently failed to deploy, Path not supporting a lookup-based status field).
Append entries here as they're discovered, each with: what was tried, what broke,
and what worked instead — so the same quirk isn't rediscovered on a future
project.

**Metadata-API-deployed custom fields have zero FLS by default, even for the
running admin user, and the resulting symptom looks like a missing field, not
a permissions error.** Hit during Stage 1: every custom field that existed
only in the `WS_Biller_Full_Access` permission set (not yet assigned to
anyone) was completely invisible to SOQL/Apex — `sobject describe`,
`FieldDefinition` queries, and plain `SELECT X FROM Object__c` all reported
"No such column," identical to the field not existing at all. Metadata API
`retrieve`/`deploy` showed the fields present and successfully deployed the
whole time — the discrepancy is entirely a data-layer FLS thing, unrelated to
whether the field exists. Unlike Setup-UI-created fields (which default
System Administrator to visible), fields created via Metadata API deploy grant
FLS to no profile or permission set automatically. Fix: `sf org assign
permset --name WS_Biller_Full_Access --target-org <alias>` for whichever user
needs to query/write the new fields — do this immediately after any deploy
that introduces new custom fields, not just once at project setup, since a
field added later and not yet covered by an assigned permission set will
reproduce the exact same "No such column" symptom.

**Corollary hit during Stage 2: a `required=true` custom field (and likewise
any `MasterDetail` field) must NOT get an explicit `<fieldPermissions>` entry
in a PermissionSet at all** — deploying one fails with "You cannot deploy to
a required field: Object__c.Field__c". This isn't a bug to work around, it's
the platform's actual rule: required/master-detail fields are implicitly
always readable and editable to any user with object-level access, so an
explicit FLS grant is redundant and rejected outright. Practical effect: when
auditing a permission set for gaps (per the gotcha above), only add entries
for fields where `required` is absent/false and the type isn't
`MasterDetail` — a field missing from the permission set is not automatically
a bug, check its `required`/type first before "fixing" it.

**Apex identifiers are case-insensitive, so a parameter can silently shadow a
type name that differs only in case.** Hit writing Stage 3's GST calculator:
a method parameter named `supplyType` on `calculateLine(input, SupplyType
supplyType)` collided with the enum type `SupplyType` itself — writing
`SupplyType.INTER_STATE` inside that method compiled as if it were
`supplyType.INTER_STATE` (an instance accessing a static field), failing
with "Static field cannot be referenced from a non static context," and the
reported error line/column pointed at an unrelated line in a dependent test
class, not the actual parameter declaration. Fix: never name a parameter or
local variable the same as a type name even with different casing — renamed
the parameter to `supply` instead of `supplyType`.

**A custom Lightning App with no explicit `Small` `formFactors` entry won't
reliably surface in the Salesforce Mobile App.** `WS_Biller.app-meta.xml` had
only `<formFactors>Large</formFactors>` — presumably the default from however
it was originally scaffolded. For an app whose hard rule is "build and test
mobile-first," this would have silently undermined every later stage's mobile
testing. Fixed by adding a second `<formFactors>Small</formFactors>` entry
(multiple `formFactors` elements are valid, not a replace). Worth checking on
any future custom app creation, since it's not something a deploy failure
ever surfaces — the app just quietly doesn't show up where expected.

**FlexiPage `componentInstance` identifiers reject hyphens.** Tried
`c_billCreate-1` as a `<identifier>` for an LWC's `componentInstance` (a
natural-looking value, similar to how `aura`/`lwc` DOM ids often get
written) — rejected at deploy with "can contain only underscores and
alphanumeric characters." Use `c_billCreate1` (digits/underscores only, no
hyphens) instead.

**A custom LWC's `targetConfig` for `lightning__RecordPage` object scoping
is a child `<objects>` element, not an `objects` attribute on
`<targetConfig>`.** `<targetConfig targets="lightning__RecordPage"
objects="Customer__c" />` deploys with "The 'targetConfig' tag doesn't
support the 'objects' attribute" — needs the nested
`<objects><object>Customer__c</object></objects>` form instead. A FlexiPage
referencing the same LWC fails in the same deploy with an unrelated-looking
"couldn't retrieve the design time component information" error — that's
just the cascading symptom of the LWC itself failing to deploy, not a
second, separate problem to chase.

**LWC's synthetic shadow DOM rewrites static `id` attributes with a
per-instance suffix, breaking `#id` selectors in Jest tests.** An element
written as `<lightning-input id="customer-search">` renders at runtime as
`id="customer-search-0"` (the suffix is an instance counter, not guaranteed
stable) — needed so ids stay globally unique across multiple component
instances on one page, since synthetic shadow doesn't give true DOM
encapsulation the way native shadow DOM does. `element.shadowRoot.querySelector('#customer-search')`
in a test returns `null`, not the element with a mismatched id, which
reads just like "element didn't render." Keep `id` attributes for their
real purpose (label `for=` association, a11y) but never rely on them for
test queries — add a parallel `data-id="..."` attribute instead (`data-*`
attributes are left untouched by the rewrite) and query by that.

**Separately, Jest-stubbed base Lightning components don't reflect
`@api` properties as real DOM attributes.** `type`, `label`, and `variant`
set in a template (e.g. `lightning-input type="search"`,
`lightning-button variant="brand"`) become JS properties on the stub, not
literal HTML attributes — `querySelector('lightning-input[type="search"]')`
also returns `null` even though the element is right there. Only
DOM-native attributes (`id`, `class`, `data-*`) are queryable this way in
tests; this is the same underlying fix (`data-id` hooks) as the id-rewrite
issue above, just a different root cause arriving at the same symptom.

**Independent promise chains in `connectedCallback` can silently race, and a
Jest test is the thing that actually caught it.** `jobBoard`'s
`connectedCallback` fired `loadBoard()` (via `getBoardData`) and a separate
`getActiveMechanics()` call side by side. The original code pre-computed each
job card's `mechanicCheckboxes` once, inside `loadBoard()`'s `.then`, reading
`this.allMechanics` at that moment — if `getActiveMechanics()` hadn't resolved
yet (which it reliably hadn't, in both the Jest run and presumably in a real
slow-network load), every card rendered with zero mechanic checkboxes and
no error, because `this.allMechanics` was still `[]`. Fixed by storing only
the raw Apex results (`rawStages`, `rawJobs`, `allMechanics`) as fields and
making `columns` (the decorated, template-facing shape) a **getter** computed
fresh from all three every time — so whichever promise resolves last still
produces a correct render, instead of baking in whatever was available first.
Worth the general lesson: any LWC view built by combining two independent
`@salesforce/apex` calls should either compute the final shape from a getter,
or explicitly sequence the calls — never decorate-and-cache inside just one
of the two `.then` callbacks.

**Report/ReportType/Dashboard metadata field-reference syntax is
inconsistent, undocumented-feeling, and in at least one case appears to be
a genuine platform bug — budget real time for this, or build by hand in
the UI instead.** Hit building Stage 7's reports:

- A **junction object with two master-detail relationships gets no
  auto-generated report type at all** (confirmed by listing
  `/services/data/vNN.0/analytics/reportTypes` — `Job_Mechanic__c` is
  absent while every other custom object has one). Needed a hand-authored
  `ReportType` with an explicit `join`/`sections` block.
- The `<reportType>` value for an **auto-generated** single-object report
  type is `CustomEntity$<Object__c>` (e.g. `CustomEntity$Bill__c`) — not
  the object name alone. For a **custom** report type it's
  `<DeveloperName>__c` (e.g. `Mechanics_with_Jobs__c`) — found only by
  querying the same `analytics/reportTypes` REST endpoint and grepping the
  `type` field; guessing cost several failed deploys first.
- Inside `ReportType.sections`, a joined object's `<table>` value is the
  **base object + relationship name** (`Mechanic__c.Job_Mechanics__r`), but
  inside an actual `Report`'s `<columns>`/`<groupingsDown>`, the same joined
  field is referenced via the **child object's own API name**
  (`Job_Mechanic__c.Job__c`), not the relationship name
  (`Job_Mechanics__r.Job__c` — looks equally plausible, silently wrong).
  Two different metadata types, two different conventions, for what's
  conceptually the same join.
- A field already used in `groupingsDown` must **not** also appear in
  `columns` ("You can't include groupings in the selected columns list") —
  easy to do by accident when columns are added for display and a grouping
  is added separately later.
- A custom object's own **Name field could not be deployed in any form**
  tried against `Mechanic_Job_Counts` — `Name`, `NAME`, `Mechanic__c.Name`,
  `MECHANIC__C.NAME`, `Mechanic.Name` all failed with "Invalid field name,"
  **even though** the live `analytics/report-types/.../describe` endpoint
  explicitly listed `Mechanic__c.Name` as a valid `detailColumnInfo` entry
  with `bucketable: true`. Worse: a field reference that deployed
  successfully in one attempt (`Job_Mechanic__c.Job__c` as a column, paired
  with other fields) failed with "Invalid field name" on an **immediately
  following, unmodified retry** — not a one-time fluke, reproduced twice.
  This smells like a real caching/propagation bug in the metadata deploy
  validator for custom report types, not a syntax mistake — logged here
  rather than "fixed," since no syntax change resolved it. **Net effect:**
  `Mechanic_Job_Counts` shipped as a plain Tabular report with only
  `Job_Mechanic__c.Job__c` as a column (the one field reference that
  survived testing) and no Mechanic-name column or grouping at all — it
  reconciles against the Job_Mechanic__c junction correctly (verified via
  direct SOQL: Deepak 3, Vikram 1) but doesn't display mechanic names.
  **To finish this report properly**, open it in Lightning Report Builder
  (not metadata), add "Mechanic Name" as a column/group — the interactive
  UI almost certainly resolves the field the deploy API couldn't.
- `Dashboard` component metadata (`DashboardComponent`) rejected every
  attempted `componentType` chart value, required `indicatorLowColor`/
  `indicatorHighColor`/`indicatorMiddleColor` (not `indicatorMidColor` —
  another plausible-but-wrong name) for `Table` components, then reported
  `textColor` as a "required field" while rejecting it as "invalid at this
  location" in every position tried. Abandoned hand-authoring the combined
  dashboard entirely rather than continue open-ended trial and error — the
  two underlying reports are built, deployed, and verified correct;
  combining them into one dashboard view is a two-minute manual action in
  Dashboard Builder (drag each report in as a component) rather than
  something worth more unbounded metadata-guessing time. The Stage 7 exit
  criterion "accessible without leaving the custom app" is still met via
  the `standard-report`/`standard-Dashboard` tabs already present in
  `WS_Biller.app-meta.xml` since the project's initial scaffold.

**A SOQL bind expression (`:expr`) can't dot-walk through a plain Apex
class's public instance field — only through SObject fields or a simple
local variable.** Hit writing a live end-to-end verification script:
`[SELECT ... WHERE Job__c = :job.id]`, where `job` is a
`JobController.JobCard` (a plain `@AuraEnabled`-wrapper class, not an
SObject) with a public `id` field, fails to compile with "Variable does not
exist: id" — not a typo, `job.id` resolves fine as an ordinary expression
anywhere *outside* a bind. Fix: assign to a local variable first
(`Id jobId = job.id;`) and bind that instead. Easy to misdiagnose as a
field-name typo (which is also a real, more common cause of the same
message) — check for this specifically when the referenced field
demonstrably exists and resolves fine elsewhere in the same method.

**ListView metadata has no Kanban-grouping element.** A `<kanbanSettings>`/
`groupingField` child on a `ListView` was tried (inherited from the reference
project's `Job__c` list view, `All_Jobs_Kanban`) at every position inside the
`<ListView>` element — start, end, either side of `<filters>` — and rejected
every time as "invalid at this location in type ListView." Confirmed genuine
platform limitation, not an ordering issue: an otherwise-identical list view
deploys cleanly once the element is removed. Kanban display itself still
works as a one-time manual UI toggle ("Display As" → Kanban, picking the
grouping field) but can't be pre-configured via deployed metadata — not
relevant for Stage 6's custom Kanban LWC, which won't use a standard list
view at all, but worth knowing if a standard list view is ever added for
admin use.

**`number` is a reserved Apex identifier — can't be used as a wrapper
class's `@AuraEnabled` field name.** `CustomerController.DocumentItem` was
first written with a field named `number` (for an invoice/estimate number);
deploy failed with "Identifier name is reserved: number," and every
dependent class (including its own test class) failed to compile as a
cascading symptom with the same underlying message. Not documented anywhere
obvious ahead of time — found only by reading the deploy error. Renamed to
`documentNumber`. Worth a mental list of Apex's reserved-but-not-obviously-
keyword identifiers (`number`, `limit`, `group`, `object`, `type` are all in
this category) before naming a wrapper-class field.

**`String.escapeSingleQuotes(null)` throws, not returns an empty string —
easy to miss when a search method's "no term" case is the untested path.**
Every `list*(String searchTerm)` method built in Stage 9
(`CustomerController.listCustomers`, `PartController.listParts`,
`DirectoryController.listBillToParties`) builds a SOQL `LIKE` term up front
via `'%' + String.escapeSingleQuotes(searchTerm) + '%'`, then branches on
`String.isBlank(searchTerm)` to decide whether to use it. The term-building
line ran unconditionally, so a blank/null search (the normal "show
everything" case a list screen loads with on first render) threw
`System.NullPointerException: Argument cannot be null` before the blank
check was ever reached — caught immediately by each controller's own Apex
test (`list*_blankTerm_returnsAll`), not by manual testing, which is the
point of writing that test in the first place. Fixed by guarding the
input to `escapeSingleQuotes` itself:
`String.escapeSingleQuotes(String.isBlank(searchTerm) ? '' : searchTerm)`.

**A Lightning App's per-user nav personalization (`isNavPersonalizationDisabled:
false`, the scaffold default) silently overrides the admin-defined `<tabs>`
order with whatever the user previously pinned/reordered/hid themselves —
server-side stored state, not a client cache, so it survives app-meta.xml
redeploys and clearing the mobile app's cache.** Hit right after Stage 9:
redeployed `WS_Biller.app-meta.xml` with the new 5-tab order (Jobs,
Customers, Billing, Inventory, More), confirmed "Succeeded," and both the
Salesforce Mobile App and desktop Lightning Experience kept showing an old,
unrelated nav bar (Jobs Board / New Estimate / New Bill / Reports / Menu) —
not even the *previous* 21-tab order, something personalized from earlier
in the build. Clearing the mobile app's device-level cache had no effect,
which was the tell that this isn't a cache problem: `NavigationLinkSet`-style
per-user nav preferences are a Salesforce *server-side* record tied to the
user + app, read instead of the app's own `<tabs>` order whenever
personalization is allowed. Fixed by flipping
`<isNavPersonalizationDisabled>` to `true` in `WS_Biller.app-meta.xml` and
redeploying — for a line-of-business app with one intended staff workflow,
there's no good reason to let a tap-and-drag accident (or old test-session
leftover) silently diverge from the admin-defined nav going forward. Users
with an existing personalization may still need one manual "reset to
default" the first time (pencil/edit icon on the nav bar, both web and
mobile) since the flag stops *new* personalization but doesn't necessarily
retroactively clear something already saved.

**Correction to the entry above — the actual root cause was tab visibility,
not nav personalization.** The `isNavPersonalizationDisabled` fix didn't
resolve it: the user still couldn't find the Customers tab anywhere, even
via App Launcher search, which a per-user nav *reorder* can't explain (a
reordered/hidden-from-nav tab is still searchable in App Launcher; a
genuinely invisible one isn't). Checked `WS_Biller_Full_Access
.permissionset-meta.xml` and found the real cause: **none of the 13 new
custom tabs from Stage 9 had a `<tabSettings>` entry at all** — only
`Jobs_Board`/`New_Bill`/`New_Estimate` and the original standard-object
tabs did. This is the exact same class of gotcha as the Stage 1 FLS issue,
one setting over: a custom **Tab**, like a custom **field**, gets zero
visibility to any profile/permission set by default when deployed via
Metadata API — "doesn't show up anywhere, not even in search" is the tab
equivalent of "No such column." It also fully explains the earlier
confusing nav bar (Jobs Board / New Estimate / New Bill / Reports / Menu):
those were exactly the tabs that already *did* have `tabSettings` entries
(plus the standard `standard-report` tab, visible by default) — nothing to
do with personalization at all. Fixed by adding a `<tabSettings>` block
(`<visibility>Visible</visibility>`) for all 13 new tabs to the permission
set and redeploying. **Lesson for next time:** whenever a new custom tab is
added, immediately check it's also added to the permission set's
`tabSettings` — don't wait for a "where did my tab go" report to catch it,
the same way FLS audits became a standing habit after Stage 1.

**When an LWC passes an object to an Apex parameter of a custom wrapper
type, only `{ get; set; }` properties get populated — plain
`@AuraEnabled public String x;` fields arrive as `null`, with no error.**
Hit on-device after Stage 9: adding a vehicle from Customer Detail failed
with "A registration number is required" even though the LWC's Save button
is disabled until that field has a value. `createVehicle` received a
non-null `input` object whose every field was `null`. Every wrapper class in
the project (221 fields across 8 controllers) had been written as plain
fields since Stage 4 — so *every* LWC call that sends an object
(`createCustomer`, `createBill`, `createEstimate`, `createJob`,
`updatePart`, `saveProfile`, …) was silently affected. Why no test caught
it: Jest mocks the Apex import (no serialization happens), and every live
verification in this project ran through anonymous Apex, which constructs
the wrapper directly in Apex and never goes through the LWC→Apex
deserializer. Fixed by converting all `@AuraEnabled` wrapper members to
`{ get; set; }` properties. **Rule going forward:** always declare
`@AuraEnabled` wrapper members as properties, and when verifying a new
LWC→Apex call live, test it through the actual LWC (or the UI on device),
not only through anonymous Apex.

**`@AuraEnabled(cacheable=true)` + an imperative call = stale reads after
every save.** Hit immediately after the fix above: adding a vehicle now
saved (confirmed by SOQL), but Customer Detail never showed it. Every LWC in
this project calls Apex imperatively and re-runs the read after a write
(`loadDetail()`, `loadParts()`, `loadBoard()`, …) — but a `cacheable=true`
method is served from the client-side Lightning cache, so that re-read
returned the pre-save response. `refreshApex` can't help because it only
works on `@wire`-provisioned data, and no LWC here uses `@wire` for Apex.
Fixed by removing `cacheable=true` from all 20 read methods. **Rule going
forward:** only mark a method `cacheable=true` if the LWC consumes it via
`@wire` and calls `refreshApex` after mutations; for imperative
load-after-save patterns, leave it non-cacheable.

**Opening a Visualforce PDF via `standard__webPage` (`/apex/InvoicePdf?id=…`)
kicks the user out of the Salesforce Mobile App into the phone's external
browser, which has no Salesforce session — so nothing renders.** Worked
fine as a concept on desktop, broke on the primary (mobile) surface. Fixed
with `DocumentPdfService.generatePdf`: renders the same page server-side
via `PageReference.getContentAsPDF()`, stores it as a `ContentVersion` on
the bill/estimate (one `ContentDocument` per record, a new version on each
regenerate so it reflects current payments), and the LWC opens it with
`standard__namedPage` / `pageName: 'filePreview'` — the native file
previewer, which stays inside the app on mobile and desktop. Two related
traps: `getContentAsPDF()` can't run in Apex tests (guarded with
`Test.isRunningTest()`, so real rendering must be checked live), and invoice
numbers contain `/`, which must be stripped from the file title.

**Follow-up: `filePreview` didn't fix it on the phone either.** Salesforce's
docs confirm `filePreview` opens a modal in the browser but only *triggers
a download* in the mobile app, with "depending on the device" native
preview — on the user's Android phone, nothing visible happened. Final
design (replacing the save-to-Files approach): a `documentPreview` LWC
popup (SLDS modal) that iframes `InvoicePdf.page` with `?format=html` —
the page's `renderAs` is now a controller property (`'pdf'` by default,
`''` for `format=html`), so the preview is the exact same template, just
not converted to PDF (Android's in-app WebView can't render a PDF inline,
so iframing the PDF itself would fail the same way). Its Download button
calls `DocumentPdfService.getPdfDownload`, which returns the PDF as base64
plus a filename, and the LWC starts the download itself from a `Blob` URL
— no URL is handed off to the external browser at any point.

**Follow-up: there is no supported way for an LWC to save a file to disk
inside the Salesforce Mobile App at all** (confirmed by search — the
officially supported mobile file-handling APIs cover uploads, not
LWC-generated downloads). The in-page `Blob`-URL download above works on
desktop but does nothing on the phone. Resolved per the user's choice of a
public-link workaround over a from-scratch PDF-viewer component:
`DocumentPdfService.getPublicLink` saves the rendered PDF as a `ContentVersion`
(reusing the Stage 9 PDF-as-File logic) and wraps it in a `ContentDistribution`
— an expiring public link with no Salesforce login required, which is why it
survives the hand-off to the phone's external browser. One file and one
distribution per record: regenerating adds a new file version and pushes the
link's `ExpiryDate` out another `LINK_VALID_DAYS` (30) rather than minting a
new link, so a link already sent to a customer keeps working and always
resolves to the latest version. `documentPreview`'s `isPhone` getter (reads
`@salesforce/client/formFactor`) branches the Download button between the
in-page `Blob` download (desktop) and the public link opened via
`standard__webPage` (phone) — same button, different mechanism depending on
device. A WhatsApp share button reuses the same public link.
**Security tradeoff, explicitly accepted by the user 2026-10-03:** a bill/
estimate's PDF (customer name, GSTIN, address, amounts) is reachable by
anyone with the link for up to 30 days, not just the intended recipient —
acceptable here since it already exists for the feature's other purpose
(sending it to the customer on WhatsApp).

**Test gotcha: a Jest-mocked scalar module value (`@salesforce/client
/formFactor`) gets bound into the component once, at the test file's first
import — reassigning the backing variable mid-file does not reach it.**
Tried a `let mockFormFactor` + a mock factory returning a getter, swapping
the value between tests in the same file; the component kept seeing
whatever value was set when the file's imports were first evaluated (Babel's
commonjs interop binds `import X from 'y'` to a plain value read at that
import, not a live binding). Fixed by splitting into two test files —
`documentPreview.test.js` (desktop, mocks `'Large'`) and
`documentPreview.mobile.test.js` (phone, mocks `'Small'`) — one fixed mock
value per file, the only pattern that reliably works for a scalar
`@salesforce/*` module in this test setup.

**Second follow-up: the public link still didn't download on the phone,
because `standard__webPage` opens Salesforce's own embedded browser tab,
not the phone's real browser — and that embedded tab doesn't complete file
downloads.** Switched the phone download path to the OS share sheet
(`navigator.share({ url })`) instead of opening the URL — Chrome, Drive,
Files, WhatsApp etc. all run outside Salesforce's embedded tab, so handing
the link to one of them is what actually lets the phone save the file.
Two things had to be handled to make this reliable, both unverifiable from
this environment (no physical device) and worth re-checking if the share
sheet itself ever stops appearing:
- `navigator.share()` is gated on a recent, real user gesture — awaiting
  an Apex round-trip first (to fetch the public link) typically burns that
  window before `share()` ever runs, so it silently does nothing. Worked
  around by pre-fetching the link the moment the popup opens
  (`connectedCallback`) rather than on the Download tap — by the time the
  user actually taps Download, that promise has almost always already
  resolved, so the subsequent `.then()` runs as a same-tick microtask
  instead of a fresh network call, keeping it inside the gesture window.
- `navigator.share()` rejects with `AbortError` when the user simply closes
  the share sheet without picking anything — must not be treated as a
  failure (no error toast, no fallback-open). Any other rejection, or the
  API being absent entirely (older WebView), falls back to the previous
  direct-open behavior rather than leaving the user with nothing.

**Third follow-up: on the actual device, `navigator.share` wasn't
available at all, and the fallback — opening the public link via
`NavigationMixin`'s `standard__webPage` — failed with "Page doesn't exist.
Enter a valid URL and try again," even though the link was a genuine,
working, anonymously-accessible URL (confirmed with `curl` outside
Salesforce entirely: HTTP 200 for both `DistributionPublicUrl` and
`ContentDownloadUrl`).** So the rejection is Salesforce's own
`standard__webPage` URL validator, not the destination — plausibly because
that navigation type is documented as being for *external* pages and
doesn't expect a URL on the org's own domain. Fixed by bypassing
`NavigationMixin` for this fallback entirely: a real `<a href target="_blank">`
click (the same hidden-anchor mechanism the desktop `Blob` download already
used) instead of a PageReference. A native DOM action doesn't go through
Salesforce's own URL classification at all. The WhatsApp button still uses
`standard__webPage` for `wa.me` links, confirmed working on-device — this
fallback-only change doesn't touch that path.

**Fourth: `toWhatsAppNumber` didn't prepend the `91` country code for a
10-digit number whose stored value was short by one digit (9 digits
instead of 10) — it just returned the number as-is, and WhatsApp couldn't
resolve the resulting bare number.** The original logic only added `91`
when the digit count was *exactly* 10, which silently does nothing for any
other length instead of still attempting to reach the right contact.
Changed to always prepend `91` unless the number already visibly carries
one (12+ digits already starting with `91` — note a plain 10-digit Indian
mobile number can itself start with the digits "91", e.g. `9131360083`, so
length is what actually disambiguates the two, not just the prefix).
Logging this as a data-quality note, not just a code fix: the customer
phone number that triggered this (`626847199`, 9 digits) looks like a
genuine typo in that record — worth checking Keshav's phone number in
Customer__c, since prepending `91` to a short number still doesn't make it
correct, it just stops the share from going out with no country code at
all.

**Fifth: opening an existing bill or estimate showed none of View PDF,
Start New Version, or its version history — that whole box only appeared
after actually saving a new version in the same session.** Root cause:
`billCreate`/`estimateCreate`'s View PDF / version-history box is gated on
`lastCreatedSummary`, which `handleSubmit`'s success callback sets after a
fresh save — but `loadBillForVersioning`/`loadEstimateForVersioning` (the
path taken when opening an *existing* record via `c__recordId`, e.g. from
Billing List or Customer Detail) only called `applySummaryToForm` and
`loadVersionHistory`, never `lastCreatedSummary` itself. The form loaded
correctly either way, so the bug was invisible unless you specifically
looked for the PDF/version controls on a record you hadn't just created.
Fixed by also setting `lastCreatedSummary = summary` in both load
methods — this is also what `handleCreateBillFromThis` on the estimate side
reads, so opening an existing estimate now correctly offers "Create Bill"
too, not just View PDF. Caught a test-isolation bug while adding coverage
for this: `jest.clearAllMocks()` (used throughout this project's LWC
tests) clears a mock's call history but not a `mockResolvedValue` already
configured on it — a test that configures `getBillVersions`/
`getEstimateVersions` with specific data must reset it back to `[]` at the
end, or that data silently leaks into every later test in the same file
that also triggers `loadVersionHistory`, independent of whether that later
test ever mentions version history itself.

**Sixth: the "bill to a different party" toggle on both `billCreate` and
`estimateCreate` only ever let staff type in a brand-new party — there was
no way to search for and reuse an already-saved `Bill_To_Party__c` record
for the current bill/estimate, even though `CreateBillRequest`/
`CreateEstimateRequest` have always had a `billToPartyId` field for exactly
that.** The LWCs simply never built the search side of it — turning the
toggle on unconditionally showed the create-new fields, and the submit
request always sent `billToPartyId: null` whenever the toggle was on. Fixed
by reusing `DirectoryController.listBillToParties` (already built for the
Bill-To-Parties list screen) to add the same search → select pattern used
everywhere else in the app (customers, parts, vehicles): the toggle now
shows a search box first, with a "This is a new party" sub-toggle revealing
the create-new fields only when actually needed. Selecting an existing
party sends its id as `billToPartyId`; creating a new one still sends
`newBillToParty` as before — never both.

**Seventh (a redesign, not a bug fix): opening an existing bill or estimate
dropped straight into the full create/edit form — every field editable at
once, no distinction between "look at this" and "change this."** User
feedback 2026-10-03, with mockups for the three screens wanted: a read-only
**Bill/Estimate Details** view by default, a pencil icon into a simplified
**edit** screen, and tapping a line item opens a focused popup instead of
showing every line's fields inline. Built as:
- `billDetail`/`estimateDetail` (new, read-only view — the new default
  landing screen for an existing record, reached from `billingList` and
  `customerDetail` instead of routing straight into the edit form): status,
  bill-to, line items, totals, and for bills, payment history + a Record
  Payment action (`BillController.recordPayment`, a plain `Payment__c`
  insert — `PaymentTriggerHandler` already recomputes `Status__c`, nothing
  new needed there) + Print (`documentPreview` popup) + Share (same public
  link + `wa.me` flow `documentPreview` already uses, factored out as
  `toWhatsAppNumber`, a named export alongside `documentPreview`'s default
  class export — already proven to work this way on-device since Stage 9).
- `lineItemEditor` (new, shared by both `billCreate` and `estimateCreate`):
  a popup for one line at a time, replacing the old always-expanded
  per-line field grid. Reuses the existing "From inventory: X → Change"
  search pattern, now scoped to one line instead of the whole form.
- `billCreate`/`estimateCreate` simplified for the "editing an existing
  record" case specifically: customer becomes a static label (changing who
  a bill is for isn't really "editing" it — that's a new bill), the
  new-customer and payment-at-creation sections disappear (payment now
  lives on the view screen's Record Payment instead), and the old
  "View PDF / Start New Version / version history" box is gone entirely —
  that's the view screen's job now. On success, both navigate straight to
  the record's new Details screen instead of resetting in place.
- `BillSummary`/`EstimateSummary` gained `billToPartyName` (resolved
  server-side via `Bill_To_Party__r.Name`/`Estimate__r...Bill_To_Party__r
  .Name` — the LWCs previously had no way to display it at all), and
  `BillSummary` gained `payments`/`amountPaid`/`amountDue`.
- Two new tabs (`Bill_Detail`, `Estimate_Detail`) with the same
  tab-visibility gotcha as every other tab in this project (§F, "custom
  Tabs work exactly like custom fields") — added to the permission set
  immediately this time rather than as a follow-up fix.

**Eighth: opening an existing bill or estimate that was already billed to
a party showed the "Bill to a different party" toggle off and nothing
selected — looked like the party had been lost, even though it was still
being carried forward correctly underneath.** `applySummaryToForm` (and
`loadFromEstimate`'s equivalent inline logic) set `carriedBillToPartyId`
from the loaded record but never set `showBillToParty`/
`selectedBillToParty` to reflect it in the UI — those only ever got set by
the Stage 9 search-and-select feature itself, which has no reason to run
on page load. Saving without touching the toggle would still have sent
the right `billToPartyId` (the submit logic falls back to
`carriedBillToPartyId` when the toggle is off), but the screen looked
wrong and inspired zero confidence it actually would. Fixed by also
populating `showBillToParty`/`selectedBillToParty` from
`summary.billToPartyId`/`billToPartyName` wherever a bill or estimate is
loaded for editing.

**Ninth: "Import from Contact" on Customers/Mechanics/Surveyors, built as a
progressive enhancement rather than a straight feature add — checked
support before writing a line of UI, not after shipping it.** The browser
Contact Picker API (`navigator.contacts.select`) is the only web-standard
way to pull a name/phone from the device address book, but support is
narrow: **no iOS Safari support at all**, not even behind a setting, and
only Chrome/Android-family browsers on Android. Given this project already
hit an Android-only API (`navigator.share`) silently failing specifically
inside Salesforce's own embedded webview — a stricter environment than
"any Android Chrome" — there was no reason to assume Contact Picker fares
better there, and a button that looks real but does nothing is worse than
no button. Built `c/contactPicker` (a plain utility module, the same
"no-UI JS file" pattern as `c/gstMath`) exporting
`isContactPickerSupported()` and `pickContact()`; every one of the three
list screens checks support in `connectedCallback` and only renders the
"Import from Contact" button when it's genuinely available — never shown,
rather than shown-and-broken, on an unsupported device.

**Follow-up, same day — this one is a genuine dead end, not just an
unverified risk, and the feature was removed entirely.** The button
appeared on-device (feature detection passed) but did nothing on tap, with
no error surfacing — because the first version's `pickContact()` swallowed
every rejection. Changed it to propagate rejections instead of catching
them, added temporary diagnostic toasts at each stage (opened / resolved /
rejected) directly in the three calling components, and asked the user to
reproduce. That surfaced the real error: `TypeError: Unable to open a
contact selector`. Per the Contact Picker spec and confirmed by other
implementers hitting the identical message, `ContactsManager.select()`
unconditionally refuses to run from any non-top-level browsing context —
same-origin or not, no `Permissions-Policy: contacts` header or iframe
`allow` attribute makes an exception. Every LWC page renders inside
Salesforce's own iframe, in Lightning Experience and inside the Salesforce
Mobile App alike, which is platform architecture no amount of app-level
code can change. This is therefore not fixable from within this project,
on any device, now or later, short of Salesforce itself changing how LWC
pages are framed. Removed `c/contactPicker` and all three call sites
entirely rather than leave a feature that can only ever render a disabled
or absent button — a permanently-dead `isContactPickerSupported()` check
would itself have been confusing to find later with no way to tell "not
supported on this device" apart from "can never be supported, anywhere, by
construction." If Salesforce ever changes LWC's framing model, this is
where to look again — until then, there is no supported way to let staff
pick a device contact from inside this app.

**Correction, same day — that conclusion was wrong. There is a supported
way; it's just not the browser API.** User pointed at `lightning/
mobileCapabilities` specifically, which this project hadn't checked before
concluding the feature was impossible — a real miss, since Salesforce ships
exactly this as a first-party capability (`ContactsService`, API 48.0+),
built on their own native bridge (Nimbus) rather than the browser's DOM
APIs. That's the actual, structural reason it sidesteps the iframe
restriction that killed the first attempt: it never goes through the
browser's permissions model at all. Rebuilt `c/contactPicker` on top of it:

```js
import { getContactsService } from 'lightning/mobileCapabilities';
```

`getContactsService().isAvailable()` is a real runtime check — unlike the
old `'contacts' in navigator` check (which reported "supported" in the
exact container where it then failed), this one reflects whether the LWC
is actually running inside a supported native mobile container with the
capability compiled in, so it should correctly read `false` on desktop/web
and `true` only where the feature can actually work.
`getContactsService().getContacts()` returns `Contact[]` with a nested
`name` object (`givenName`/`familyName`/`middleName`/`namePrefix`/
`nameSuffix` — assembled into one display string by `c/contactPicker`) and
a `phoneNumbers` array of `{ label, value }` (first entry used). Kept the
same external shape (`isContactPickerSupported()`, `pickContact()`) so the
three call sites barely changed. No stub exists for `lightning/
mobileCapabilities` in `sfdx-lwc-jest` (unlike `lightning/navigation` etc.)
— mocked it the same way as an `@salesforce/apex` import, with `{ virtual:
true }`. **Lesson for next time a "this can't be done in Salesforce"
conclusion is reached: check whether `lightning/mobileCapabilities` covers
it before concluding that — it exists precisely to reach native device
features that the standard browser-API route can't, for exactly this
class of problem.**

**Final correction, same day — `isAvailable()` returned `false` on the
user's actual device, and the feature has been removed a third time, for
good this time.** The `lightning/mobileCapabilities` rebuild deployed
cleanly and the button rendered (confirmed the live `LightningComponentResource`
in the org matched local source, ruling out a stale-cache explanation), but
the user's own diagnostic report was unambiguous: `getContactsService().
isAvailable() = false`. Researched Salesforce's documented compatibility
matrix for `ContactsService` directly (not inferred): it is supported only
in **Salesforce Mobile App Plus (iOS only)** and **Mobile Publisher** apps —
it is explicitly **not supported in the standard Salesforce Mobile App**
(Android or iOS) or Field Service Mobile, regardless of device OS, device
capability, or any org/user setting. This project targets the standard
Salesforce Mobile App, so `isAvailable()` reading `false` here is not a bug,
not a misconfiguration, and not something a permission, org setting, or
code change can flip — it is a hard product-tier boundary. This is a
different kind of dead end than the first one (browser `navigator.contacts`
in an iframe, architecturally impossible everywhere): `ContactsService`
itself is real and works correctly as documented, just not inside the
specific app product this project's users actually run. Removed
`c/contactPicker` (module + tests) entirely for the third time, reverted
`customerList`/`mechanicList`/`surveyorList` (`.js`/`.html`/tests) to their
pre-feature state, redeployed all three, and deployed a destructive-changes
removal of the orphaned `contactPicker` `LightningComponentBundle` from the
org. **Lesson for next time a native-capability `isAvailable()` check comes
back `false`:** the compatibility question has two independent layers —
"does this capability exist at all" (what the first correction above was
about) and "is it enabled in the specific Salesforce app product/edition the
actual users run" (what killed it this time) — checking only the first layer
and assuming the second is a hollow win. If this app is ever distributed via
Salesforce Mobile App Plus (iOS only) or Mobile Publisher instead of the
standard Salesforce Mobile App, the `lightning/mobileCapabilities`
`ContactsService` approach documented above (code no longer present in this
project — this directory has no version control, so there is no history
copy to restore from; it would need to be rebuilt from this description)
would work unmodified.

**Tenth: stale record shown after navigating A → back → B within the same
tab (customerDetail reported first; same bug found by inspection in
billDetail, estimateDetail, inventoryDetail, billCreate, estimateCreate).**
All six screens read their target record id from `@wire(CurrentPageReference)`
state (`c__customerId`/`c__recordId`/`c__partId`), but guarded the handler
with a one-time `_initializedFromPageRef` flag — intended to stop the wire
from re-running on unrelated page-reference churn, but it also permanently
ignored every *subsequent* navigation once set. Salesforce reuses the same
LWC instance for repeat visits to the same `standard__navItemPage` tab
rather than tearing it down and recreating it (this is also why the much
earlier tab-visibility bug surfaced the way it did — tabs are
longer-lived than they look), so opening Customer A, going back, and
opening Customer B kept rendering Customer A's already-loaded `detail`
until a hard refresh forced a full remount. Fixed by comparing the
incoming id against the currently-loaded one (`billCreate`/`estimateCreate`
compare a `JSON.stringify` of the whole relevant state object, since they
branch on several different keys — `c__recordId` / `c__sourceEstimateId` /
`c__jobId` / `c__customerId`) and only reloading — resetting all transient
UI state (edit-mode flags, in-progress forms, previous `detail`/`summary`)
first — when it actually changes, rather than gating on "has this component
ever initialized." **Lesson: a `@wire(CurrentPageReference)` handler on any
screen reachable by navigating to the same tab with different record state
must key its reload on "did the identifying id change," never on
"have I already run once" — the latter is only safe if the platform
guarantees a fresh component per navigation, which it does not.**

**Eleventh: the invoice PDF never showed the vehicle, and Buyer's Name
printed as the literal text "Buyer's Name: {0}" — two unrelated bugs hit
and fixed together because the user reported them in one message.**

*Vehicle missing entirely:* `InvoicePdfController` predates the Bill/
Estimate `Vehicle__c` field added for the vehicle-picker feature — it only
ever read a vehicle via `Job__r.Vehicle__c`, which is null for the common
case (a bill/estimate with no linked `Job__c` at all). Adding a field that
a *different*, already-existing read path needs to know about is easy to
miss — the new picker worked and the summary screens showed the vehicle
correctly, so nothing *looked* broken until someone opened the actual PDF.
Fixed by having `loadBill`/`loadEstimate` prefer the record's own
`Vehicle__c` and fall back to `Job__r.Vehicle__c` only when that's null
(covers bills/estimates created before this field existed). **Lesson: when
a new field duplicates information an older feature already derives a
different way (here, "the vehicle" via a Job lookup vs. a direct field),
grep every existing reader of that concept, not just the screens the new
feature itself touches.**

*`{0}` not substituted, apostrophe-adjacent:* `InvoicePdf.page` uses
`<apex:outputText value="...{0}..."><apex:param value="{!field}"/></apex:outputText>`
throughout — standard Visualforce MessageFormat-style substitution, and it
works for every other label on the page (`Contact No.:`, `GSTIN Number:`,
`State:`, `Date:`). Only `Buyer's Name: {0}` broke, because the underlying
`java.text.MessageFormat` engine treats an unescaped single quote as the
start of a quoted-literal span — so `Buyer's Name: {0}` is parsed as
"Buyer", then a quoted span beginning at the `'` that swallows `s Name:
{0}` as literal text with no substitution, which is exactly the verbatim
`{0}` the user saw. Fixed by doubling the apostrophe (`Buyer''s Name:
{0}`), the standard MessageFormat escape. **Lesson: any
`apex:outputText`+`apex:param` `{0}`-style string on this page needs its
apostrophes doubled — a literal apostrophe anywhere before a placeholder
silently breaks that placeholder, with no error, just literal `{0}` in the
output.** No Apex test can catch this class of bug — `PageReference.
getContent()` cannot be called from a test method (already noted in
`InvoicePdfControllerTest`), so the page body itself is only ever verified
by opening `/apex/InvoicePdf?id=<recordId>` in a browser. The existing
`billToPartyPresent_printsBuyersNameSeparatelyFromBillTo` test already
proved `controller.buyersName` itself was correct — the bug was entirely
in the page markup, invisible to the one layer Apex tests can reach.

**Twelfth: Back from a Bill/Estimate opened from a Customer always landed
on the generic list, never on that customer.** `billDetail.handleBack()`
and `estimateDetail.handleBack()` hard-coded their destination
(`Billing_List` / `Customer_List`) with no awareness of where the user had
actually come from — correct for the common case (opened from the list
itself) but wrong whenever the bill/estimate was reached via
`customerDetail`'s "+ New Bill"/document-row links, since those are a
*different* entry point into the same screen. Fixed by threading a new
`c__fromCustomerId` page-state key end to end: `customerDetail.
navigateToRecord` now sets it alongside `c__recordId`; `billDetail`/
`estimateDetail` capture it in their id-change branch (right next to the
stale-record fix from the tenth entry above) and `handleBack` prefers
navigating to `Customer_Detail` with it when present, falling back to the
old hard-coded destination only when it's absent. Also carried through
`handleEdit` (→ `New_Bill`/`New_Estimate`) and `estimateDetail.
handleCreateBill` (→ `New_Bill`), and from there through `billCreate`/
`estimateCreate`'s own `handleBack` (versioning mode) and their
submit-success navigation back to `Bill_Detail`/`Estimate_Detail` — so the
customer context survives a full open → edit → save round trip, not just
a single hop. **Lesson: any screen reachable from more than one entry
point needs its "Back" destination threaded through navigation state as
data, not hard-coded as a single destination — the same mistake as the
tenth entry's stale-id bug, just one layer up (wrong *destination* instead
of wrong *data*). When adding a new entry point into an existing detail
screen, grep every `handleBack`/`handleEdit` on that screen for hard-coded
`apiName` values before assuming the existing ones still make sense.**

**Thirteenth: the "+" FAB on every list screen (Customers, Billing,
Inventory, Mechanics, Surveyors, Bill-To Parties) scrolled away with the
content on mobile instead of staying pinned bottom-right.** All six used
plain `position: fixed; bottom: 1.5rem; right: 1.5rem;` on the button
itself — correct CSS for "pin to the viewport" on an ordinary web page,
but `position: fixed` is only ever fixed relative to the *viewport*, and
it silently becomes fixed relative to the nearest ancestor that creates a
new containing block instead (any ancestor with a `transform`,
`will-change: transform`, `filter`, `perspective`, or `contain` applied —
exactly the kind of wrapper the Salesforce Mobile App's own rendering
shell is liable to apply to each tab's content for its own scrolling/
transition handling, which is outside this project's control and not
something `sf project deploy` surfaces). When that ancestor is itself the
thing that scrolls, a "fixed" descendant drifts with it instead of
staying glued to the screen — exactly the reported symptom, and a problem
invisible in desktop Lightning Experience (confirmed working there),
which is why it shipped unnoticed. Fixed by replacing `position: fixed`
on the button with a dedicated zero-height wrapper
(`<div class="fab-anchor">`) using `position: sticky; bottom: 1.5rem;
height: 0;` as the *last* element in the scrollable content, with
`display: flex; justify-content: flex-end` to park the button at the
right edge. The zero height means the wrapper consumes no layout space —
its "natural" flow position is already past the sticky threshold the
instant any content taller than the viewport exists, so the button
appears pinned from the first scroll pixel rather than only snapping into
place once scrolled to the literal end of the list (the usual caveat with
sticky-positioned elements). `position: sticky` sticks relative to the
nearest *scrolling* ancestor specifically, which is the one thing that's
guaranteed to still be correct even inside whatever transformed wrapper
the platform adds — unlike `fixed`, it doesn't need to reach the true
viewport to behave correctly. **Lesson: never use `position: fixed` for
an always-visible floating control in an LWC meant to run inside the
Salesforce Mobile App — it depends on reaching the true viewport, which
Salesforce's own shell may prevent for reasons outside this project's
code. Use the zero-height `position: sticky` wrapper pattern instead, and
grep for `position: fixed` across the whole LWC tree whenever adding a
new persistent/floating control, since this mistake is easy to
copy-paste forward into the next list screen.**

**Correction, same day — the `position: sticky` fix above did not work
either, and the floating-button approach has been abandoned entirely.**
User report after retesting: the button no longer floats at all; it now
renders inline immediately *after* the last row in the list. That's the
tell that `position: sticky` never engaged — sticky only visually differs
from a plain static element once the user has scrolled *past* the point
where the element's natural flow position would otherwise leave the
sticky offset's bound; for a list short enough to fit on one screen (or
even one that doesn't scroll far), that threshold is never crossed, so
the "zero-height last-child" element just sits wherever it naturally
falls — immediately after the last row — instead of pinned to a fixed
corner of the screen. This is a real, structural limitation of `sticky`
for this use case, not a mistake in the wrapper markup: sticky is built
for "stay in view *while scrolling past* this point," never for "always
pinned to a corner regardless of scroll position or content length,"
which is what a FAB actually needs. Combined with the eleventh entry's
`position: fixed` failure (fixed needs to reach the true viewport, which
something in the Salesforce Mobile App's rendering prevents), this
project has now exhausted both CSS positioning strategies for an
always-visible floating button inside this platform's tab rendering.
**Abandoned the floating-button pattern entirely** and replaced all six
"+" buttons (Customers, Billing, Inventory, Mechanics, Surveyors,
Bill-To Parties) with a plain `lightning-button-icon` sitting inline in
each screen's header row, next to the `<h1>` title — exactly the pattern
`jobBoard` already used successfully for its own "New Job" action (a
`lightning-button` in the card's `actions` slot), which never had this
bug because it was never positioned via `fixed`/`sticky` in the first
place. The button is visible immediately on load (no scroll needed to
reach it, since it's the first thing on screen) and simply scrolls out of
view with the rest of the header when the user scrolls down — identical
to how every other header element on these screens already behaves, and
a deliberately unglamorous trade against trying a third CSS trick blind.
**Lesson: for a Salesforce Mobile App LWC, don't reach for `position:
fixed`/`sticky` to build a FAB at all — put the action in the header
instead, matching whatever pattern already works elsewhere in the same
project, rather than spending a third attempt on positioning tricks this
platform's rendering has twice already defeated in ways this project has
no way to test locally before shipping.**

**Fourteenth: PDF Files are now disposable scratch artifacts, not shared
documents — WhatsApp sharing removed, and two layers of cleanup added.**
Decision, not a bug: since customers are no longer sent a link (the
"Share on WhatsApp" flow is gone entirely — `documentPreview`'s WhatsApp
button, `billDetail`/`estimateDetail`'s own "Share" button, and the
now-dead `toWhatsAppNumber` helper all removed together, along with the
`PublicLink.viewUrl`/`expiresAt`/`customerName`/`customerPhone` fields
nothing reads anymore), the File `DocumentPdfService.getPublicLink`
creates exists for one purpose only: handing the Mobile App's native
share sheet a real URL so `navigator.share()` can hand the device an
immediate download (it can't share raw bytes). Nothing needs that File
to keep existing afterward. Two-layer cleanup, both new:
- `BillEstimateFileCleanupBatch`, invoked with a specific
  `Set<Id>` of one ContentDocument — scheduled via `System.scheduleBatch`
  for five minutes after every `getPublicLink` call, the primary
  mechanism.
- The same batch's no-arg constructor runs a broader nightly sweep (any
  Bill/Estimate-linked File created "yesterday"), via
  `BillEstimateFileCleanupScheduler`, registered once with
  `System.schedule('Bill/Estimate File Cleanup (Nightly)', '0 0 2 * * ?',
  new BillEstimateFileCleanupScheduler())` — a safety net for anything
  that slips past the five-minute cleanup, not the primary mechanism.

**Platform quirk hit building the nightly sweep's query — two failed
deploys before landing on the working shape.** First attempt: `SELECT Id
FROM ContentDocument WHERE Id IN (SELECT ContentDocumentId FROM
ContentDocumentLink WHERE ...)` — rejected at deploy time: *"Entity
'ContentDocumentLink' is not supported for semi join inner selects."*
Second attempt, querying `ContentDocumentLink` directly first to collect
Ids before filtering `ContentDocument` by them — rejected too, with a
different, more specific error: *"ContentDocumentLink requires a filter
by a single Id on ContentDocumentId or LinkedEntityId using the equals
operator or multiple Id's using the IN operator."* This is a real,
documented implementation restriction specific to this one junction
object — unlike virtually every other SOQL object, `ContentDocumentLink`
refuses to be queried broadly (e.g. filtered only by `LinkedEntity.Type`)
at all; it insists on an `=`/`IN` filter keyed on one of its two lookup
columns specifically. Fixed by inverting the query direction: first
collect candidate Bill__c/Estimate__c record Ids (bounded to the last
`CANDIDATE_RECORD_LOOKBACK_DAYS` = 2 days, a deliberate, documented limit
since this is the safety-net path, not the primary one), *then* query
`ContentDocumentLink WHERE LinkedEntityId IN :candidateRecordIds` (a
valid filter shape), collect the linked `ContentDocumentId`s from that,
and only then filter `ContentDocument` by `CreatedDate` and that Id set.
**Lesson: `ContentDocumentLink` cannot be the source of a semi-join, and
cannot be queried by a loose filter like `LinkedEntity.Type` either — any
query touching it must start from a bounded, already-known set of
specific record Ids on one side (`ContentDocumentId` or
`LinkedEntityId`), never the other way around.**

**Also while here: the "same link keeps working across regenerations"
test assertion from the original WhatsApp-era design no longer holds,
and that's correct, not a regression.** `PublicLink.viewUrl`
(`ContentDistribution.DistributionPublicUrl`) was stable across repeated
`getPublicLink` calls because `PreferencesLinkLatestVersion = true` makes
that one URL always resolve to the newest version — exactly what a link
already texted to a customer needs. `downloadUrl`
(`ContentDistribution.ContentDownloadUrl`), the only field callers still
read now, is different: it's a direct link to one specific
`ContentVersion`, so it changes every time a new version is added.
That's fine for the current use (hand the share sheet a URL, download it
immediately, done) — but it means `DocumentPdfServiceTest`'s old
"reuses same link" assertion had to change from comparing URL equality to
comparing the underlying File/Distribution identity instead
(`getPublicLink_calledAgain_reusesSameFileAndDistributionButAFreshVersionLink`).

**Fifteenth: Record Payment disabled across the app — commented out, not
deleted, specifically so it can come back with zero backend work.**
User request, explicit about wanting it reversible ("comment that part so
if i need that again i will uncomment that"). Touched only the LWC and
VF-page layers: the Record Payment button/form on `billDetail`, the
Paid/Partial/Unpaid status badge everywhere it showed (`billDetail`,
`billingList`, `customerDetail`'s bills list — *not* `estimateDetail` or
`customerDetail`'s estimates list, since Estimate statuses are
Draft/Approved/Converted/Rejected, an unrelated concept that just happens
to share one badge-class map with bills in `customerDetail.js`), the
Billing list's All/Dues Only filter, and the PDF's Received/Balance/
Payment Mode block. **Deliberately left every bit of Apex untouched** —
`BillController.recordPayment`, `Bill__c.Status__c` and
`PaymentTriggerHandler`, `BillSummary.status/payments/amountPaid/
amountDue`, `InvoicePdfController.showPayment/amountPaid/amountDue/
paymentMode`, `listBills(filter, searchTerm)`'s `DuesOnly` branch — all
of it keeps computing exactly as before, it's just never rendered or
invoked from the UI anymore. That was the deliberate design call: since
nothing on the Apex side needed to change, restoring this later is purely
"uncomment the commented blocks," with no risk of Apex/LWC shape drift
between now and whenever that happens.

**Missed on the first pass: `billCreate` has its own separate "Record a
payment now" toggle for recording an initial payment at bill-creation
time** — a different code path from `billDetail`'s post-creation Record
Payment button, easy to miss precisely because the two don't share any
component. User caught it on a follow-up ("still getting record payment
toggle... on new bill creation page"). Commented out the same way:
`recordPaymentNow`/`paymentAmount`/`paymentMethod` fields, the toggle +
amount/method markup, `handleToggleRecordPayment`/
`handlePaymentAmountChange`/`handlePaymentMethodChange`, and the three
reset sites (`resetForm`, `applySummaryToForm`, post-submit) — with
`initialPaymentAmount`/`initialPaymentMethod` in the `createBill`/
`createNewVersion` request hardcoded to `null` rather than removed, since
`BillController.createBill` still accepts (and does nothing wrong with)
those params. **Lesson: when a feature has more than one entry point into
the same backend action (here, "record a payment" exists both as its own
button after the fact, and as a toggle during creation), grep the
*action* (`recordPayment`, `initialPayment`, `Payment__c`) across the
whole `lwc` tree before declaring removal done — don't stop at the first
screen that obviously has it.**

**Real gotcha hit commenting out the PDF's payment block: a plain HTML
`<!-- -->` comment does NOT stop Visualforce from evaluating `<apex:...>`
tags inside it.** First instinct was to wrap the `<apex:outputPanel
rendered="{!showPayment}">...` block in an ordinary HTML comment — looks
like it should obviously work, since the commented text never reaches
the rendered page. It doesn't: Visualforce parses and evaluates
`<apex:...>` components as part of building the component tree *before*
final HTML serialization, so components inside a literal `<!-- -->`
stay fully live — rendered and merge-field-evaluated server-side — only
the resulting *output* ends up sitting inside an HTML comment in the
final page source, not suppressed at all. The correct way to comment out
Visualforce markup containing `<apex:...>` tags is the triple-dash VF
comment syntax, `<!--- ... --->`, which *is* stripped by the VF compiler
itself before any component evaluation happens. **Lesson: never use a
plain `<!-- -->` to disable a block of Visualforce page markup that
contains `<apex:...>` components — use `<!--- --->` instead, every time,
or the "disabled" code keeps running exactly as before with nothing to
show for it except a slower page.**

**Sixteenth: a manually-typed line item on a Bill/Estimate now creates a
real, searchable Part__c behind the scenes — no LWC changes needed at
all.** New `PartUpsertService.fillManualPartIds(lineItems)`, called once
at the top of `BillController.createBill`/`createNewVersion` and
`EstimateController.createEstimate`/`createNewVersion`, right after
`validate(request)`: for every line with no `partId`, it finds an
existing `Part__c` with the same name or creates one from that line's
own price/tax/GST/HSN/unit, and sets `li.partId` before the usual
`insertLineItems` call runs — so from that point on the line is
indistinguishable from one picked via Inventory search. That's also why
no LWC work was required: `billCreate`/`estimateCreate`/`lineItemEditor`
already send a manual line's full description/price/tax/GST/HSN/unit
with `partId: null`, which is exactly the shape the service consumes —
the whole feature lives entirely server-side, triggered by the existing
submit action. Bulk-safe (one SELECT + at most one INSERT per request,
not per line) and dedupes lines sharing a description within the same
request so two "Labour" lines in one bill don't create two parts. Because
the line's `Part__c` is now genuinely set, a manual line on a **bill**
deducts stock through the exact same `BillStockService`/trigger path a
real inventory line already uses (confirmed by
`createBill_withManualLine_createsSearchablePartAndDeductsStock` —
Current_Stock__c goes to -2 for a never-before-seen part, same as if it
had been picked from search with zero opening stock); a manual line on an
**estimate** creates the Part just the same but never touches stock,
since estimates don't touch inventory at all (confirmed by the parallel
estimate test). **Design note: matching is by exact `Part__c.Name`
equality** (SOQL text comparison, which is case-insensitive by default,
so "oil filter" matches an existing "Oil Filter") — no fuzzy matching, so
a differently-worded manual entry for the same real-world item (e.g.
"Oil Filter" vs "Engine Oil Filter") will still create a second Part__c.
That's an accepted tradeoff for staying simple and predictable, not a
bug — the whole point of the feature is that typing the *exact same*
description a second time no longer requires re-creating it.

**Seventeenth: new Job Detail screen (`c:jobDetail`, `Job_Detail` tab),
reachable from both the Jobs board and a customer's Jobs list — same
page-reference/back-navigation pattern as `billDetail`/`estimateDetail`.**
`JobController.getJobDetail(jobId)` returns job number, created date,
stage, customer (name/phone/address), vehicle (reg/make/model/year/
color), surveyor, mechanics, notes, and the job's own linked bills/
estimates (reusing `CustomerController.DocumentItem` directly, so those
rows render identically to the ones on Customer Detail). `CustomerController.
getCustomerDetail` grew a parallel `jobs` list (id/jobNumber/stageName/
vehicleLabel/createdDate) alongside vehicles/bills/estimates. Both
`customerDetail.js`'s existing generic `navigateToRecord()` (already sets
`c__recordId` + `c__fromCustomerId`) and `billDetail`/`estimateDetail`'s
`c__recordId`-based page-ref convention were reused as-is — Job Detail
just reads the same `c__recordId` key, no new state-key naming needed.
From the Jobs board, the job's own number is now a tappable link into
this same screen (previously just a `<p>`), navigating with `c__recordId`
only (no `fromCustomerId`), so its own Back falls back to the `Jobs_Board`
tab — consistent with how `billingList`'s bill rows behave the same way
for Bill Detail.

**Real regression caught before it reached a commit: turning the Jobs
board's job-number `<p>` into a `<button data-job-id={job.id}>` made an
existing test's `querySelector('button[data-job-id="job1"]')` silently
start matching the wrong element.** That selector was written when the
"Mechanics…" toggle was the *only* `<button data-job-id="…">` on the
card; it was never scoped tighter because it didn't need to be. Adding a
second button earlier in the DOM meant `querySelector` (which returns the
first match in document order) silently started returning the new
job-number link instead — the test still ran, still clicked *something*,
but the wrong thing, so the mechanics panel never expanded and the next
line (`querySelector` for the now-never-rendered checkbox) failed with a
null-dereference one line later, not where the real cause was. Fixed by
giving the "Mechanics…" button its own `data-id="toggle-mechanics"` and
tightening the test's selector to match on both attributes together.
**Lesson: a `data-job-id`-only (or any single shared, non-unique)
attribute selector is only safe as long as it's the *only* element on
the card carrying that attribute — the moment a second one is added
anywhere earlier in the DOM, `querySelector` silently repoints without
any error at the actual point of divergence. Any element added to an
existing repeated-row/card template should get its own unique `data-id`
from the start, specifically so a later addition to that same card can
never create this kind of silent collision.**

**Eighteenth (2026-10-10): `Stock_Movement__c` removed entirely — a
deliberate reversal of this project's own original hard rule — at the
user's explicit request.** The user's stated reasoning: the ledger was
"unnecessary" for this app's actual needs — they don't want to trace which
bill deducted which part, they just want to set a part's stock count
directly and have bill creation decrement it in place. This directly
contradicted the CLAUDE.md rule in force until this entry ("Stock is always
derived from `Stock_Movement__c` via aggregate SOQL, never a
directly-writable field"), so before touching anything the user was told
explicitly what deleting the object would cost (permanent loss of all
historical stock-movement records, no audit trail going forward) and asked
to confirm; they chose full deletion over leaving the object in place
unused. CLAUDE.md's hard rule and this file's §A/§C.2 have been updated to
describe the new design as current, not flagged as a violation.

What changed:
- `Stock_Movement__c` (object, its 4 fields, its tab, `StockMovementTrigger`,
  `StockMovementTriggerHandler`, `StockMovementTriggerHandler`'s test class)
  deleted outright — from local source, the permission set
  (`objectPermissions`/`tabSettings` entries), and the live org (via
  `sf project delete source`, which removed every historical movement
  record with it).
- `PartStockService.recomputeStock(Set<Id>)` (aggregate-SOQL recompute from
  the ledger) replaced by `PartStockService.adjustStock(Map<Id, Decimal>
  deltaByPartId)` — a direct read-add-write on `Part__c.Current_Stock__c`,
  guarded by `SELECT ... FOR UPDATE` on the affected parts so concurrent
  bill creation against the same part can't lose an update. This mirrors
  `InvoiceNumberingService`/`PaymentStatusService`'s existing locking shape
  rather than inventing a new pattern.
- `BillStockService.deductForNewLineItems`/`restoreForRemovedLineItems` no
  longer insert ledger rows; they aggregate each batch's per-part delta
  first, then call `PartStockService.adjustStock` once per batch.
- `PartController.createPart` sets `Current_Stock__c` directly on the new
  `Part__c` at insert (no separate opening-stock ledger row needed — a
  brand-new record has no concurrent readers yet). `PartController.
  adjustStock` dropped its `reason`/`source` parameters (they only ever
  existed to label ledger rows that no longer exist) — signature is now
  just `adjustStock(Id partId, Decimal quantityDelta)`.
- `PartController.getPartDetail`/`PartDetail` dropped `recentMovements`/
  `StockMovementItem` entirely — nothing to show without a ledger.
  `inventoryDetail` LWC's "Recent Stock Movements" section and the adjust-
  stock form's Reason/Note inputs were removed for the same reason, not
  commented out — unlike the Record Payment removal (Fifteenth), there is
  no backing data to restore even if this screen's UI were uncommented
  later, so there was nothing to preserve.
- Deploy order mattered: the old `StockMovementTriggerHandler` still called
  the old `recomputeStock(Set<Id>)` signature, so deploying the rewritten
  `PartStockService` first (before deleting the handler) failed with
  "Dependent class is invalid and needs recompilation." Fixed by deleting
  `StockMovementTrigger`/`StockMovementTriggerHandler`/its test first
  (while the still-unmodified `PartStockService` in the org still matched
  them), then deploying the rewritten classes, then deleting the
  `Stock_Movement__c` object/tab last. Three separate operations, in that
  order, not one combined deploy.

Verified after: 178/178 Apex tests, 23/23 Jest suites (122/122 tests), both
at 100%.

**Nineteenth (2026-10-10): vehicle Make/Model autocomplete, backed by a new
`Vehicle_Make_Model__c` reference table.** User request: preload common
Indian car brands/models as typing suggestions on the vehicle Make/Model
fields, with **no lookup field on `Vehicle__c`** (it stays plain text,
unconstrained — free typing always allowed), and any make/model typed
manually that isn't already known gets remembered automatically so it's
offered as a suggestion next time. The user said they'll populate the
table's starting data themselves (similar to the earlier Parts Data Loader
question) — nothing was seeded here.

- New object `Vehicle_Make_Model__c` (`Make__c`, `Model__c`, both plain
  Text(100), no relationship to `Vehicle__c` in either direction) — purely
  a suggestion source, never referenced by any trigger or validation rule.
- `VehicleMakeModelController.searchMakes(term)` / `searchModels(make,
  term)` — simple `LIKE` + `GROUP BY` lookups, LIMIT 10, no caching (matches
  this codebase's existing `searchCustomers`/`searchVehicles`/`searchParts`
  convention of plain `@AuraEnabled`, not `cacheable=true`). `searchModels`
  scopes to the given make when one is present, falls back to searching
  across all makes when it's blank, so the two fields work in either fill
  order.
- `VehicleMakeModelService.rememberIfNew(make, model)` — one SELECT + at
  most one INSERT, called once per vehicle creation (not bulkified; vehicles
  are always created one at a time from the UI, same as `PartController.
  createPart`). Wired into all four places a new `Vehicle__c` gets inserted:
  `BillController.resolveVehicleId`, `EstimateController.resolveVehicleId`,
  `CustomerController.createVehicle`, `JobController.createJob`.
- New reusable child LWC `c:vehicleMakeModelField` (one component, a
  `source="make"|"model"` prop picks which Apex method it calls) replaces
  the plain `lightning-input` for Make and Model in all four "new vehicle"
  forms (`jobBoard`, `billCreate`, `estimateCreate`, `customerDetail`). It
  exposes a public `value` getter/setter and fires a plain `change` event,
  so it's a drop-in replacement — none of the four parents' existing
  generic `data-field`-keyed change handlers needed to change at all;
  `event.target.value`/`event.target.dataset.field` resolve exactly the
  same way on this custom element as they did on the `lightning-input` it
  replaced. The suggestion list reuses the same inline (non-overlay)
  `.search-results`/`.search-result-row` SLDS pattern already used by the
  customer/vehicle/part search dropdowns elsewhere in this app, for visual
  consistency. Suggestion selection uses `onmousedown` with
  `event.preventDefault()` rather than a click handler plus a blur-delay
  timeout — this keeps the input focused so the suggestion button is still
  in the DOM when the selection logic runs, with no timing hack needed.
- **New platform gotcha:** deploying a brand-new custom object + its fields
  + Apex that queries/inserts against it, all in one `sf project deploy
  start` with `--test-level RunSpecifiedTests`, failed every test touching
  the new object with `System.QueryException: No such column 'Make__c'...`
  and `System.DmlException: ...fields being inaccessible...` — even though
  the deploy itself reported all components deployed successfully. Root
  cause turned out to be twofold and compounding: (1) the object/fields
  need a moment to finish propagating before Apex in the *same* deploy can
  query them reliably (confirmed by splitting the deploy into "object+tab+
  permission set first" then "Apex+tests second" as two separate `sf
  project deploy start` calls), and (2) **the permission set's
  `objectPermissions` block alone does not grant field-level access** —
  without an explicit `fieldPermissions` entry per custom field (the same
  `<editable>true</editable><field>Object__c.Field__c</field><readable>
  true</readable>` block every other custom field in this permission set
  already has), the running user's Apex SOQL/DML against those fields fails
  outright. Both new fields were missing their `fieldPermissions` entries
  entirely on the first pass. **Lesson: adding a new custom object always
  needs an object permission block AND one field permission block per
  field in the permission set — object-level CRUD is necessary but not
  sufficient — and the object+field metadata should be deployed and
  allowed to settle in its own `sf project deploy start` call before a
  same-session deploy runs Apex tests against it.**

Verified after: 70/70 of the directly affected Apex tests (`BillController
Test`, `EstimateControllerTest`, `CustomerControllerTest`, `JobController
Test`, `VehicleMakeModelControllerTest`, `VehicleMakeModelServiceTest`) and
the full local Apex/Jest suites, all passing.

**Twentieth (2026-10-10): full completeness audit of `WS_Biller_Full_Access`,
so a brand-new user with only this permission set assigned (no System
Administrator profile) can use every part of the app with zero additional
setup.** Prompted by the user asking explicitly whether every piece of the
project is covered. Systematically enumerated every custom object (16),
every custom field (105), every Apex class (51), and every custom tab (35)
against what the permission set actually granted, rather than trusting it
had kept up with each feature as it was built incrementally.

Two real, previously-undetected gaps, both invisible in all prior testing
because testing always ran as the authenticated CLI/admin org user, who
bypasses Apex class access and (per the FLS gotcha earlier in this section)
apparently doesn't bypass FLS the same way a lower-privilege user would hit
it even harder:
- **`classAccesses` was completely empty — zero Apex classes granted.** A
  non-admin user would have gotten "You do not have access to the Apex
  class" on every single `@AuraEnabled` call, i.e. the entire app. Added all
  51 classes (every `.cls` file in the project, test classes included for
  simplicity — a single "full access" permission set has no reason to be
  selective here).
- **`applicationVisibilities` had no entry for `WS_Biller` at all.** Added
  one (`visible: true`). Note: unlike a *Profile's* `ApplicationVisibility`,
  a *PermissionSet's* version of this type has no `default` field — trying
  to set one fails deploy with "Element {...}default invalid at this
  location in type PermissionSetApplicationVisibility." Only Profiles can
  set a default app; a permission set can only make one visible.

The `fieldPermissions` side of the audit looked at first like ~26 missing
grants spanning nearly every object (`Bill__c.Invoice_Number__c`,
`Bill_Line_Item__c.Unit_Price__c`, all of `Payment__c`, all of
`Job_Mechanic__c`, etc.) — but every single one of them turned out to be a
`required=true` field or a `MasterDetail` field, which — per the corollary
already logged earlier in this section — **cannot** take an explicit
`fieldPermissions` entry at all (deploy rejects it: "You cannot deploy to a
required field"). Confirmed by trial: adding them failed deploy three times
in a row, each time trimming down to the next subset, until the only
genuine action was realizing none of the 105 fields needed a new entry —
the original 79 `fieldPermissions` blocks were already complete, and the
"gaps" were an audit false-positive from not checking `required`/type
first. This is the same lesson the corollary already states, just hit from
the opposite direction this time (auditing for missing entries, rather than
adding a new field and discovering the rule) — worth remembering that an
apparently-missing `fieldPermissions` entry is only a real gap once you've
confirmed the field is neither required nor master-detail.

Objects (16/16), fields (105/105 — i.e. every non-required/non-master-detail
field already had an entry), classes (51/51, newly complete), and tabs
(35/35) are now all fully and correctly covered.

Verified after: 188/188 Apex tests, 24/24 Jest suites (127/127 tests), both
at 100%, plus a clean `sf project deploy start` of the permission set alone.

**Twenty-first (2026-10-10): any Apex deploy is flatly rejected once this
app's own nightly scheduled job is running in the target org — confirmed
while building the client-deployment scripts in §G.** `sf project deploy
start --source-dir force-app` against the dev org (which already had
`BillEstimateFileCleanupScheduler`'s nightly job registered, per Stage 9's
`post-install.apex`-equivalent step) failed on every single Apex class in
the payload — not just the scheduled one — with "This schedulable class
has jobs pending or in progress ... You can bypass this error by allowing
deployments with Apex jobs in the Deployment Settings page in Setup."
Tried fixing it via metadata first (an `ApexSettings.settings-meta.xml`
with `enableDeployWithPendingJobs`, guessing at the field name) — deploy
rejected it outright ("invalid at this location in type ApexSettings"), so
that specific field doesn't exist; left unresolved whether *any*
metadata-deployable setting does, rather than keep guessing. **Fix that
does work, fully scriptable:** `System.abortJob()` the specific
CronTrigger by name immediately before deploying, then re-register it
immediately after (the existing idempotent `post-install.apex` already
does this) — confirmed with a real dry-run that failed before the abort
and passed clean after. Matching by job name rather than aborting every
`CronTrigger` in the org matters: the dev org had three unrelated
scheduled jobs already running (two "Program ... Cron Job" entries and a
"Metalytics Data Loader Job," none of which belong to this app) that must
never be touched by a deploy script. This will hit **every** deploy to a
client org after the first one (the first deploy to a brand-new org has
nothing scheduled yet, so it won't surface there) — codified as step 1 of
`Deploy-ToClientOrg.ps1` in §G specifically so it's never rediscovered the
hard way mid-deploy to an actual client.

---

## G. Deploying to a new client org

This dev org (`wsbiller01@gmail.com`) is where the app is built and tested.
Every new client gets their own separate org, deployed to from this same
source tree. A plain `sf project deploy start --source-dir force-app
--test-level RunLocalTests` is **not** sufficient against a genuinely
blank org, and **splitting Apex out of the deploy to work around that is
not safe either** — confirmed the hard way twice (§F, Twenty-second and
Twenty-third). The corrected, portable design: deploy everything together
in one payload (so every cross-reference resolves within that same
transaction regardless of which validation a given org enforces), skip
Apex tests during the deploy itself, assign the permission set for real,
then separately *run* (not deploy) the tests to confirm the code actually
works now that FLS exists. `scripts/deploy/Deploy-ToClientOrg.ps1` runs
this full sequence:

1. `scripts/apex/unschedule-jobs.apex` — aborts this app's own scheduled
   job(s) by name (§F, Twenty-first) so the deploy itself isn't rejected.
   A no-op on a brand-new org.
2. Validate (`--dry-run`), then deploy for real, the entire `force-app`
   tree in one payload with `--test-level NoTestRun`. No Apex tests run
   during this deploy at all, so the FLS-dependent failures (§F,
   Twenty-second) never occur, and nothing is split out, so the
   cross-reference validation failures (§F, Twenty-third) never occur
   either. **Confirmed safe for Developer Edition and Sandbox only** —
   Salesforce rejects `NoTestRun` for a Production deploy that contains
   Apex, and this gap has not yet been addressed (see the open risk noted
   in §F, Twenty-third).
3. `sf org assign permset --name WS_Biller_Full_Access --on-behalf-of
   <admin>` — for real, against the org, right after the deploy succeeds.
   Not idempotent — a repeat run fails with "Duplicate
   PermissionSetAssignment"; the script treats that specific message as
   success rather than a real failure.
4. A **standalone** `sf apex run test --test-level RunLocalTests` (not a
   deploy — the code is already live in the org from step 2) to prove it
   actually passes now that the admin has FLS from step 3. A failure here
   means a real bug, not the chicken-and-egg problem, since the permission
   set is already assigned.
5. `scripts/apex/post-install.apex` — re-registers the nightly cleanup job
   (idempotent).
6. `scripts/apex/smoke-test.apex` — runs a real `BillController.createBill`
   end to end (customer → inline new vehicle → GST line item → invoice
   numbering) inside a savepoint/rollback, so it catches a live-only
   problem (most importantly a missing `Workshop_Profile__c` singleton,
   which `InvoiceNumberingService` throws on immediately and clearly)
   without leaving any data behind.
7. Prints the remaining checklist that genuinely can't be scripted:

   - **Seed `Workshop_Profile__c` (exactly one row) and
     `Job_Status_Stage__c` (the pipeline stages) per client** — copy
     `scripts/apex/seed-required-data-template.apex`, fill in that client's
     real business details, run once. These are data, not metadata, so no
     deploy ever creates them; without `Workshop_Profile__c`,
     `InvoiceNumberingService.assignNextInvoiceNumber` throws on the very
     first bill; without an active `Job_Status_Stage__c`, the Jobs board
     renders with zero columns and `JobController.createJob` throws.
   - Assign the permission set to every staff user, not just the admin.
   - **If this is a Production org**: step 2's `NoTestRun` deploy would
     have been rejected by Salesforce. Stop and resolve the open risk
     noted in §F, Twenty-third, before using this script against a live
     Production org — it has not been adapted or tested for that case.
   - Confirm the client's Salesforce edition actually supports every
     feature this app uses (Lightning Apps, custom Report Types, Scheduled
     Apex) — some of this is gated on edition/license in older or
     restricted orgs, and a metadata deploy won't surface that until it's
     tried.
   - The on-device Salesforce Mobile App walkthrough — nothing scripted
     substitutes for actually opening the app on a phone, per §B's
     mobile-first requirement.
   - (Optional) seed `Vehicle_Make_Model__c` with common makes/models via
     Data Loader — a convenience only; the app works correctly empty, just
     with no autocomplete suggestions yet (§F, Nineteenth).

All three Apex scripts were run against the dev org while building this and
confirmed working: `smoke-test.apex` passes and leaves zero residual data
(verified by a direct `Customer__c` count query after rollback);
`post-install.apex` correctly no-ops when the job is already scheduled;
`unschedule-jobs.apex` + re-registering via `post-install.apex` was what
unblocked the dry-run deploy in the Twenty-first entry above.

**Twenty-second (2026-10-10): the single-combined-deploy approach in §G was
never actually tested against a genuinely blank org, and it fails there —
found immediately when the user connected a real second org
(`Ws_biller02`) and ran the documented command.** `sf project deploy start
--source-dir force-app --test-level RunLocalTests` against a brand-new
Developer Edition org failed 127 of 177 Apex tests, overwhelmingly with
`System.DmlException: ... fields being inaccessible` and `System.
QueryException: No such column`. Root cause: this is the **same FLS gotcha
already logged earlier in this section** ("Metadata-API-deployed custom
fields have zero FLS by default, even for the running admin user"), just
never experienced at full-app scale before. On the dev org, the connected
user had been assigned `WS_Biller_Full_Access` months earlier (Stage 1),
long before this session's work — so every later incremental deploy this
session inherited that assignment and never hit this at scale, only in the
small, already-understood doses (2 fields at a time) documented in the
Nineteenth/Twentieth entries. A genuinely new org has no such history: the
very first deploy's own Apex test run executes as a user who cannot have
been assigned the permission set yet, because assignment is a **data**
action that (per every version of §G written before this entry) was
scheduled to happen *after* the metadata deploy — but the metadata deploy's
own test run needs it *during* the deploy. A real circular dependency, not
a flake.

**The fix, verified end-to-end against `Ws_biller02`:** split the deploy
into two passes along the Apex/non-Apex boundary, with the permission set
assignment sandwiched in between.
- **Pass 1** deploys every non-Apex metadata type (`objects`, `tabs`,
  `applications`, `flexipages`, `layouts`, `contentassets`, `lwc`,
  `reportTypes`, `reports`, `staticresources`, `permissionsets`) with no
  `--test-level` at all. Confirmed by direct experiment that this succeeds
  even though the permission set's 51 `classAccesses` entries reference
  Apex classes that don't exist anywhere in the org yet — Salesforce does
  **not** validate `classAccesses` target existence at deploy time (unlike
  Visualforce's `controller=` attribute, which does validate and is why
  `pages/InvoicePdf.page` must stay out of Pass 1 and move to Pass 2
  instead — it references `InvoicePdfController`).
- Then `sf org assign permset` runs for real, against the org, before
  anything else.
- **Pass 2** deploys the three Apex-dependent metadata types (`classes`,
  `triggers`, `pages`) with `--test-level RunLocalTests` — by now the
  deploying user already has FLS on every field via the assignment that
  just happened, so the same tests that failed 127/177 in the combined
  attempt pass 177/177 here.

This works identically on Developer Edition, Sandbox, and Production,
since Pass 1 contains zero Apex and therefore never triggers Production's
mandatory-test-level requirement in the first place — the split avoids the
circular dependency rather than trying to find a loophole in it.

**A second, independent bug found while scripting this fix:** `sf org
assign permset` is **not idempotent** — re-running it against a user who
already has the assignment (e.g., a second deploy to the same org, or
re-running the script after a partial failure) fails outright with
`Duplicate PermissionSetAssignment`, not a success/no-op. `Deploy-
ToClientOrg.ps1` now captures that command's output and treats this
specific message as success, continuing the pipeline, instead of letting
a perfectly-fine "already assigned" state abort the whole deploy.

**A third bug, purely in the PowerShell script itself, caught by actually
running it rather than just reading it:** piping `2>&1` on a native
command (here, capturing `sf org assign permset`'s output into a variable
so its text could be inspected for the message above) throws a terminating
`NativeCommandError` in Windows PowerShell 5.1 — even for an exit-code-0
success, and even for completely harmless stderr noise like the CLI's own
"update available" banner — the moment the script also has
`$ErrorActionPreference = "Stop"` set (which it does, deliberately, so
real failures stop the pipeline). Fixed by toggling
`$ErrorActionPreference` to `"Continue"` only around that one capturing
call, then restoring it immediately after. Every other `sf` invocation in
the script is called plainly (no `2>&1`), which never triggers this —
confirmed by the fact that only the one line using `2>&1` ever failed this
way, across several real runs.

`Deploy-ToClientOrg.ps1`'s step numbering and §G's step list have both been
rewritten to match this corrected order (unschedule → validate+deploy Pass
1 → assign permset → validate+deploy Pass 2 → post-install → smoke test →
checklist). The SOP document (`WS_Biller_Deployment_SOP.docx`) was
regenerated to match.

Verified after: a full real run of the corrected `Deploy-ToClientOrg.ps1`
against `Ws_biller02` end-to-end, exit code 0, Pass 2 reporting 177/177
Apex tests passing, and `post-install.apex` correctly registering the
nightly job on a true first run.

**Twenty-third (2026-10-10): the Twenty-second entry's two-pass split
(non-Apex metadata first, Apex second) is itself not safe on every org —
found immediately when the user tried it against a third, genuinely blank
org (`ws_biller03`) and Pass 1 failed outright.** Errors: `PermissionSet
WS_Biller_Full_Access — In field: apexClass - no ApexClass named
AmountInWordsService found` and, repeated for every LWC bundle, `Unable to
find Apex action class referenced as 'DirectoryController'`. Both of
these were specifically things the Twenty-second entry had verified as
*safe* on `Ws_biller02` — a permission set's `classAccesses` referencing
not-yet-existing classes, and (implicitly, never actually tested) an LWC's
`@salesforce/apex/Class.method` import referencing a class not in the same
deploy. `ws_biller03` enforces both as hard deploy-time validation
failures; `Ws_biller02` did not. Since **every single LWC in this project**
imports an Apex controller this way (confirmed: 39 files across all 23
bundles), there is no safe way to split Apex out of a deploy that also
includes the LWCs or the permission set — the two-pass design from the
Twenty-second entry is not portable across orgs/releases and must not be
used.

**Corrected design, replacing the two-pass split entirely:** never split
Apex out of the deploy at all. Objects, fields, classes, triggers, pages,
LWCs, and the permission set all deploy together, in one transaction, so
every cross-reference — Apex-to-field, LWC-to-Apex, permission-set-to-Apex
— resolves within that same payload regardless of which checks a given
org happens to enforce. The original blocker this was all working around
(§F Twenty-second: a blank org's deploying user has no FLS yet, so
bundling Apex tests into the same deploy fails them en masse) is solved
differently: deploy the single combined payload with `--test-level
NoTestRun` (no Apex tests execute during the deploy at all, so the
FLS-dependent failures never occur), assign the permission set for real,
then run a **standalone** `sf apex run test --test-level RunLocalTests`
(not a deploy — the code is already live in the org from the deploy that
already succeeded) to actually prove the deployed code passes, now that
FLS genuinely exists. A failure at that standalone-test step means a real
bug, not the chicken-and-egg problem, since the permission set is already
assigned by the time it runs.

**Open, unresolved risk, flagged rather than guessed at:** `--test-level
NoTestRun` is not accepted by Salesforce for a deploy to a **Production**
org that contains Apex — confirmed by general Salesforce platform
documentation, not independently tested here (no Production org has been
involved in this project yet). This script and SOP are therefore confirmed
safe for Developer Edition and Sandbox only. The standard fix for a real
Production first-deploy — bundling FLS grants directly onto the admin
user's own Profile metadata (deployed in the same transaction as
everything else, so that user already has FLS without a separate
assignment step, since profile-level grants don't need "assigning" the way
a permission set does) — has not been built or verified. Do not use this
script unmodified against a live Production client org; address this gap
first when that need actually arises, with a real org to verify against,
rather than shipping an untested guess now.

`Deploy-ToClientOrg.ps1` and `WS_Biller_Deployment_SOP.docx` were both
rewritten to the single-combined-deploy design. Per explicit instruction,
the fix was verified against `Ws_biller02` only — `ws_biller03` was left
untouched for the user to deploy themselves.

Verified after: a full real run of the rewritten `Deploy-ToClientOrg.ps1`
against `Ws_biller02`, exit code 0 — single deploy succeeded, duplicate
permission-set assignment correctly treated as success, and the standalone
post-deploy test run reported 188/188 passing.

**Twenty-fourth (2026-10-10): added `WS End User Profile` — the Profile
every non-admin staff user is assigned, paired with `WS_Biller_Full_Access`
(the permission set carries 100% of this app's actual access; the profile
is deliberately almost empty).** `force-app/main/default/profiles/WS End
User Profile.profile-meta.xml` — just `<custom>true</custom>` and
`<userLicense>Salesforce</userLicense>`, nothing else. No
`userPermissions` block at all, which is a blank "no" on every one of
them, confirmed by direct query after deploy: `PermissionsModifyAllData`,
`PermissionsViewSetup`, `PermissionsCustomizeApplication`,
`PermissionsManageUsers`, `PermissionsAuthorApex` all `false` — zero Setup
access, as required. No object/field/class/tab/app grants on the profile
either; those are additive from any assigned permission set regardless of
what the profile itself grants, so the already-audited permission set
(§Twentieth: 16/16 objects, 105/105 fields, 51/51 classes, 35/35 tabs, app
visibility) is sufficient on its own. This file is now part of `force-app`,
so every future client deploy (§G) creates this same profile automatically
— no extra step needed per client, just assign it + the permission set to
each new user.

Two things learned while building this, logged so neither is rediscovered
the hard way:
- **A Profile's `Name` field is taken literally from the metadata
  filename — underscores are NOT converted to spaces the way some other
  display-vs-API-name splits might suggest.** First attempt used
  `WS_End_User_Profile.profile-meta.xml`, which deployed successfully but
  left the profile literally named "WS_End_User_Profile" (confirmed via
  `SELECT Name FROM Profile`), not "WS End User Profile" as intended.
  Unlike `CustomObject`/`CustomField` (which have a separate `<label>`
  from the API name) or `PermissionSet` (which has a separate `<label>`
  too), `Profile` metadata has no such split — the filename *is* the
  display name. Fixed by using a literal space in the filename itself
  (`WS End User Profile.profile-meta.xml`), which Salesforce accepts for
  Profile specifically (most other metadata types forbid spaces in their
  API-name-bearing file names) and deploys with the exact name requested.
  The wrongly-named profile was deleted via `sf project delete source -m
  "Profile:WS_End_User_Profile"` before creating the correctly-named one,
  since a Profile's Name can't be changed after creation.
- **A near-miss, not an actual incident: `sf project delete source`
  without an explicit `--target-org` silently used the CLI's configured
  default org — which had, at some point after the previous session's
  work, been changed to `ws_biller03`** (the org explicitly off-limits
  this session, per the user's own instruction, since they wanted to run
  deploys there themselves). The delete command ran against
  `ws_biller03` by default and only failed harmlessly because the
  mis-named profile had never been deployed there in the first place —
  if it had existed there, it would have been deleted without any
  confirmation prompt, against an org the user explicitly said not to
  touch. Caught immediately via `sf config get target-org`, and every
  subsequent command in this task was given an explicit `--target-org`.
  **Lesson: once a session has been told an org is off-limits, never
  trust the CLI's configured default for *any* command afterward — always
  pass `--target-org` explicitly, every time, no exceptions** — the
  default can change from under you without any action on this session's
  part (the user changing it locally while testing is exactly what
  happened here).

Verified after: direct `Profile` query confirming `Name`, `UserLicense`,
and all five checked Setup/admin permissions, run against
`wsbiller01@gmail.com` (the dev org) only.

**Twenty-fifth (2026-10-25): added a Chassis Number field to `Vehicle__c`,
and — since the user's request implied one should already exist — built
the Vehicle Detail screen that didn't exist before this.** Before this
entry, a vehicle had no detail/edit screen of its own at all: Customer
Detail's Vehicles section rendered each vehicle as a small, non-clickable
box (registration number + make/model only), with no way to view or edit
anything about a vehicle after creating it. Confirmed via a dedicated
Explore pass over all 23 LWCs (the same pass that later fed the user
manual, §F's next entry) before assuming otherwise.

- `Vehicle__c.Chassis_Number__c` (Text(30)) — new field.
- `VehicleController.cls` (new) — `getVehicleDetail(vehicleId)` /
  `updateVehicle(vehicleId, input)`, mirroring `PartController`'s
  view-then-edit shape exactly. `updateVehicle` also calls
  `VehicleMakeModelService.rememberIfNew` on whatever Make/Model the edit
  lands on, same as every other vehicle-writing path — editing a vehicle's
  make/model to something new should feed the autocomplete table the same
  way creating one does.
- New `c:vehicleDetail` LWC + `Vehicle_Detail` tab/FlexiPage, reachable by
  tapping a vehicle row on Customer Detail (previously non-interactive,
  now a `document-row` button like Jobs/Bills/Estimates already were) and
  wired through `customerDetail`'s existing generic `navigateToRecord`/
  `c__fromCustomerId` convention — Back returns to the customer it was
  opened from, falling back to `Customer_List` otherwise, identical to
  every other Detail screen's Back behavior in this app.
- `Chassis_Number__c` threaded through every path that creates or edits a
  vehicle: `CustomerController.VehicleItem`/`NewVehicleInput`,
  `JobController`'s own separate `NewVehicleInput`, and the inline
  new-vehicle insert blocks in `BillController.resolveVehicleId` /
  `EstimateController.resolveVehicleId` (both of which reuse
  `CustomerController.NewVehicleInput` directly, so extending that one
  class covers both). On the LWC side: a new "Chassis Number" field added
  to all four existing "new vehicle" forms (`customerDetail`, `jobBoard`,
  `billCreate`, `estimateCreate`) — `billCreate`/`estimateCreate` needed
  no JS change at all, since their submit logic already spreads the whole
  `newVehicle` object rather than listing fields individually;
  `customerDetail`/`jobBoard` list fields explicitly and needed one line
  added to each.
- Permission set: `fieldPermissions` for `Vehicle__c.Chassis_Number__c`,
  `classAccesses` for `VehicleController`/`VehicleControllerTest`,
  `tabSettings` for `Vehicle_Detail` — all three gaps this project has
  twice now found the hard way (§F, Twentieth/Twenty-second) checked and
  closed in the same pass as adding the feature, not as an afterthought.
- Same Jest-stub gotcha hit again while writing `vehicleDetail`'s tests
  (already logged earlier in this section, under a different component):
  `lightning-button-icon[alternative-text="Back"]` doesn't resolve against
  the Jest stub, since `alternative-text` isn't reflected as a real DOM
  attribute there — fixed by adding `data-id="back"` and querying that
  instead, same fix as always.

Verified after: 193/193 Apex tests, 25/25 Jest suites (132/132 tests), both
at 100%, deployed and tested against the dev org (`wsbiller01@gmail.com`).
