# TallyDroid — CA-Grade Offline Accounting & Inventory App for Android
### Master Product Specification v1.0

> ⚠️ This document is the single source of truth. Any change must be version-bumped and reviewed by the CA lead and senior DB engineer before development begins.

---

## Table of Contents
1. [Overview and Strategic Goal](#1-overview-and-strategic-goal)
2. [Architecture and Data Flow](#2-architecture-and-data-flow)
3. [Must-Have Features](#3-must-have-features)
4. [Data Model and Drift Schema](#4-data-model-and-drift-schema)
5. [CA Accounting Rules and Validation](#5-ca-accounting-rules-and-validation)
6. [Inventory Engine](#6-inventory-engine)
7. [Import Engine](#7-import-engine)
8. [Google Drive Backup, Restore and Three-Way Merge](#8-google-drive-backup-restore-and-three-way-merge)
9. [Reports](#9-reports)
10. [UX and Android Design Requirements](#10-ux-and-android-design-requirements)
11. [PDF Generation and Export](#11-pdf-generation-and-export)
12. [Performance Targets and QA Acceptance](#12-performance-targets-and-qa-acceptance)
13. [Known Gaps](#13-known-gaps-documented-not-in-scope-for-v1)
14. [Deliverables Checklist](#14-deliverables-checklist)

---

## 1. Overview and Strategic Goal

Build a single-user, zero-server Android app in Flutter that replicates Tally-style accounting and inventory workflows (tax excluded), supports import of Tally `.xml` exports, stores each company in an encrypted per-company SQLite file, and provides Google Drive backup/restore with file-based merge.

The app must behave like a CA/accountant tool: accurate double-entry posting, bill-wise allocation, IMS-style invoice matching, full audit trail, CA-grade reports, and fast performance for **10,000+ vouchers per season**.

> **Scope boundary:** Tax computation (GST, TDS, etc.) is explicitly out of scope for v1. Tax fields may be stored as metadata but no tax logic, returns, or computation will be implemented.

---

## 2. Architecture and Data Flow

### 2.1 High-Level Stack

```
Flutter UI
  → Domain Layer (business rules)
  → Local DB Layer (Drift + SQLCipher per-company file)
  → Background Services (Workmanager)
  → Google Drive (OAuth2)
  → Export / Import / Merge Engine
```

### 2.2 Internal Service API (Dart Classes)

All business logic is exposed through a thin service layer. **No UI component calls the DB directly.**

| Service Method | Purpose | Returns |
|---|---|---|
| `postVoucher(v)` | Validate, post, audit-log a voucher | `VoucherResult` |
| `getTrialBalance(fy, asOf)` | Compute TB from ledger lines | `TrialBalanceDTO` |
| `getProfitLoss(fy, from, to)` | P&L from aggregates + live lines | `PLReportDTO` |
| `getBalanceSheet(asOf)` | BS with grouped ledgers | `BSReportDTO` |
| `getDaybook(from, to, page)` | Paginated voucher list | `PagedVouchers` |
| `getBuyerLedger(ledgerId, fy)` | Outstanding + history per party | `LedgerStatement` |
| `exportCompanyDb(companyId)` | Encrypt + export DB file | `File` |
| `importTallyXml(file)` | Parse, validate, dry-run, import | `ImportResult` |
| `mergeBackup(localDb, remoteDb)` | Three-way merge with conflict list | `MergeResult` |
| `lockFinancialYear(fy)` | Lock period; Admin only | `void` |
| `getBankReconciliation(ledgerId)` | Unreconciled entries vs bank | `BRSReport` |

### 2.3 Layered Flow

- User Actions → Flutter UI
- Flutter UI ↔ Domain Services (`VoucherEngine`, `InventoryEngine`, `ReportsEngine`, `BRSEngine`, `Importer`)
- Domain Services → Local DB Layer: Drift + SQLCipher per-company file
- Background Worker (Workmanager) → Backup Exporter → Google Drive App Folder
- User-triggered Restore/Merge → Download remote DB → Three-Way Merge Engine → Conflict UI → Commit

---

## 3. Must-Have Features

### 3.1 Core Features

- Multi-company with per-company encrypted SQLite DB files.
- User roles: Admin, CA, Accountant, Manager — single-user but roles control UI mode and permissions.
- Double-entry voucher engine: **Sales, Purchase, Receipt, Payment, Journal, Contra, Credit Note, Debit Note.**
- Financial year lock: Admin-only override; locked periods prevent any voucher alteration with full audit entry.
- Bill-wise allocation and IMS invoice matching for purchases and GRNs.
- Bank reconciliation (BRS): unreconciled entry list, mark-cleared workflow, BRS report.
- Cheque/instrument tracking: cheque number, bank name, clearing date on payment/receipt vouchers.
- Inventory: multi-godown, batch/expiry, FIFO/LIFO/Weighted Average, stock transfers, BOM (MVP).
- Reports: Daybook, Trial Balance, P&L, Balance Sheet, Monthly Sales/Purchase, Buyer-wise ledgers, BRS, Aging, Exception reports.
- FTS5 SmartFind with fuzzy matching across ledgers, narrations, and stock items.
- Import: Tally `.xml` (v7.2 / 9 / Prime / Prime 2.0) with version detection, idempotency keys, and duplicate guard.
- Import: CSV/JSON/Excel using canonical app templates (template schema defined in Section 7).
- Backup/Sync: Encrypted DB export/import to Google Drive; three-way merge with conflict UI.
- Audit: Immutable `audit_logs` with before/after JSON; source tag (`local`/`remote`/`imported`) on every row.
- Export/Share: PDF and Excel export, share via email, WhatsApp, other apps.
- Biometric lock on company open (Android `BiometricPrompt`).
- Performance: Daybook < 2s for 90 days; FTS5 search < 500ms; bulk import 10k rows < 30s.

> ⚠️ **Credit Note and Debit Note are separate voucher types, NOT negative invoices.** Sales returns post via Credit Note; purchase returns post via Debit Note. Mixing these with Sales/Purchase vouchers breaks ledger group reporting.

> ⚠️ **Contra vouchers are strictly for cash ↔ bank transfers only.** The voucher engine must enforce this constraint and reject any Contra that references a non-cash/non-bank ledger.

---

## 4. Data Model and Drift Schema

### 4.1 Design Principles

- UUID TEXT primary keys on all tables.
- `last_modified INTEGER` (epoch ms) and `version INTEGER` on all mutable tables.
- `source TEXT` on all rows: `'local'` | `'remote'` | `'imported'`; `import_manifest_id` FK.
- Append-only `audit_logs`; no UPDATE or DELETE on `audit_logs` ever.
- WAL mode, `synchronous = NORMAL`, `foreign_keys = ON`, `PRAGMA integrity_check` post-import.
- FTS5 virtual table for `fts_search` covering ledger names, stock names, narrations.
- Precomputed `monthly_aggregates` refreshed after each voucher post.
- Soft delete via `is_deleted BOOLEAN` + `deleted_at INTEGER`; cascade policy: deleting a voucher soft-deletes its lines, movements, and allocations atomically in one transaction.

### 4.2 Core Tables

| Table | Purpose | Key Columns / Notes |
|---|---|---|
| `companies` | Company metadata and DB file pointer | `id, name, fy_start, db_file_path, is_locked` |
| `users` | Local user profile and role | `id, name, role ENUM(Admin,CA,Accountant,Manager), pin_hash, biometric_enrolled` |
| `financial_years` | FY boundaries and lock state | `id, company_id, from_date, to_date, is_locked, locked_by, locked_at` |
| `ledgers` | Ledger master with opening balances | `id, name, group_id, opening_balance, opening_balance_type(DR/CR), fy_id, is_deleted` |
| `ledger_groups` | Hierarchical account groups | `id, name, parent_id, nature ENUM(Asset,Liability,Income,Expense)` |
| `stock_items` | Inventory master | `id, name, unit, sku, group_id, valuation_method ENUM(FIFO,LIFO,WA)` |
| `godowns` | Warehouses/storage locations | `id, company_id, name, address` |
| `vouchers` | Voucher header | `id, type ENUM(Sales,Purchase,Receipt,Payment,Journal,Contra,CreditNote,DebitNote), date, number, total, narration, fy_id, is_locked, created_by, last_modified, version, source, import_manifest_id` |
| `voucher_lines` | Double-entry lines | `id, voucher_id, ledger_id, dr_cr, amount, stock_item_id, qty, godown_id, narration (line-level), last_modified` |
| `stock_movements` | Stock in/out per godown | `id, stock_item_id, godown_id, ref_voucher_id, qty, rate, movement_type, batch_id, last_modified` |
| `bill_allocations` | Bill-wise links payment ↔ invoice | `id, voucher_line_id, ref_voucher_id, allocated_amount, outstanding_amount, status ENUM(Open,PartPaid,Closed)` |
| `batches` | Batch numbers and expiry | `id, stock_item_id, batch_no, expiry_date, mfg_date` |
| `bank_instruments` | Cheque/DD/NEFT tracking | `id, voucher_id, instrument_type, number, bank_name, amount, clearing_date, status ENUM(Issued,Cleared,Bounced)` |
| `bank_reconciliation` | BRS entries | `id, ledger_id, instrument_id, bank_date, is_reconciled, reconciled_at` |
| `bom` | Bill of Materials (MVP) | `id, finished_item_id, component_item_id, qty` |
| `monthly_aggregates` | Precomputed sales/purchase totals | `id, ledger_id, stock_item_id, month_year, dr_total, cr_total, last_refreshed` |
| `audit_logs` | Immutable audit trail | `id, entity_type, entity_id, action ENUM(INSERT,UPDATE,DELETE,LOCK), before_json, after_json, performed_by, performed_at, source` |
| `sync_changes` | Local change queue for merge | `id, entity_type, entity_id, change_type, payload_json, created_at, applied BOOLEAN` |
| `import_manifests` | Import session metadata | `id, source_type ENUM(TallyXML,CSV,JSON,Excel), file_hash, imported_at, status, original_file_path` |

### 4.3 Critical Indexes

> ⚠️ Missing these indexes is a junior mistake. Without `(company_id, date)` on vouchers, Daybook for 90 days on 10k+ records will full-scan. Define all indexes explicitly in the first migration; do not rely on Drift defaults.

```sql
CREATE INDEX idx_vouchers_company_date       ON vouchers(company_id, date);
CREATE INDEX idx_voucher_lines_ledger_date   ON voucher_lines(ledger_id, voucher_id);
CREATE INDEX idx_stock_movements_item_godown ON stock_movements(stock_item_id, godown_id);
CREATE INDEX idx_bill_alloc_status           ON bill_allocations(status, ref_voucher_id);
CREATE INDEX idx_audit_logs_entity           ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_sync_changes_applied        ON sync_changes(applied, created_at);
```

### 4.4 Opening Balance Rules

- `opening_balance` on ledgers applies only to the **first FY** created for that ledger.
- Subsequent FYs carry forward: closing balance of FY-n becomes opening of FY-(n+1), computed by `getTrialBalance()` at FY end — not stored manually.
- Balance Sheet verification: sum of all Asset DR must equal sum of all Liability CR + Capital. Enforce at FY-end lock.

### 4.5 Schema Migration Versioning

- Each encrypted per-company DB stores `schema_version INTEGER` in a `meta` table.
- On open, app compares DB `schema_version` to app `CURRENT_SCHEMA_VERSION`.
- If DB version < current: run pending migrations in sequence inside a transaction; if any migration fails, rollback and alert user.
- **Never run migrations on a DB opened for restore/merge until merge is committed.**
- Migration history must be append-only; no migration file may be modified after it ships.

---

## 5. CA Accounting Rules and Validation

### 5.1 Voucher Engine Constraints

- Every voucher must balance: `SUM(DR lines) == SUM(CR lines)`. Reject with descriptive error if not.
- Contra vouchers: only cash and bank ledgers permitted on both sides. Reject any other ledger.
- Credit Note: must reference original Sales voucher. Auto-reverse stock movement on post.
- Debit Note: must reference original Purchase voucher. Auto-reverse stock movement on post.
- Locked FY: any attempt to post, edit, or delete a voucher in a locked FY throws `FYLockedException`. Admin override creates an unlock audit entry before posting.
- Voucher number uniqueness: enforced per `company + FY + voucher type`. Preserve original numbers on Tally import.

### 5.2 Bank Reconciliation (BRS)

- Each bank/cash ledger has a BRS mode toggle.
- BRS screen shows: book balance, uncleared instruments, bank statement balance (manual entry), and difference.
- User marks instruments as Cleared with bank date; this writes to `bank_reconciliation` table.
- BRS Report: dated, printable, with CA signature block in PDF layout.

### 5.3 Aging Report

- Compute from `bill_allocations.outstanding_amount` grouped by age buckets: 0–30, 31–60, 61–90, 90+ days.
- Separate debtor aging (Sales ledger group) and creditor aging (Purchase ledger group).
- Available from Buyer-wise Ledger screen and as standalone report.

### 5.4 Narration

- **Voucher-level narration:** single text field on voucher header.
- **Line-level narration:** optional text field on each `voucher_line` (required for Journal vouchers by default).
- Both levels indexed in FTS5 for SmartFind.

### 5.5 Cost Centers (Deferred — Document Now)

> Cost centers and cost categories are not in v1 scope. The `ledger_groups` table must reserve a `cost_center_id FK` column (nullable) for future use without requiring a breaking migration.

---

## 6. Inventory Engine

- Valuation methods: FIFO, LIFO, Weighted Average — set **per stock_item**, not per company globally.
- Multi-godown: each `stock_movement` records `godown_id`. Stock summary aggregates per item + godown.
- Batch/expiry: `batch_id` on `stock_movements`; expiry alerts surfaced in CA dashboard exceptions.
- Stock transfers: Journal-type voucher with `stock_movement` pairs (OUT from source godown, IN to destination).
- Negative stock: flagged as exception in CA dashboard; soft-blocked by default (Admin can override).
- BOM (MVP): finished item + component list + qty; Manufacturing voucher type deducts components, adds finished item via `stock_movements`.

---

## 7. Import Engine

### 7.1 Tally XML Import

- **Version detection:** parse `TALLYMESSAGE/@TALLYBUILDNO` to branch between Tally 7.2, 9, Prime, Prime 2.0 XML schemas.
- **Multi-company XML:** if export contains multiple `COMPANY` elements, prompt user to select which company to import.
- **Idempotency key:** `(tally_voucher_number + date + company_name)`. Duplicate detected = skip + log, never double-post.
- **Parser flow:** Upload → Pre-scan → Mapping UI → Dry Run Validation → Single-Transaction Import → Post-Import Checks → Save Manifest.

### 7.2 Mapping Essentials

| Tally Element | App Entity | Notes |
|---|---|---|
| `LEDGER` | `ledgers` | `name, group, opening_balance`; group mapped via `ledger_groups` |
| `STOCKITEM` | `stock_items` | `name, unit, SKU`; valuation method from `COSTINGMETHOD` |
| `VOUCHER` | `vouchers + voucher_lines` | `VOUCHERENTRIES` → dr_cr lines; preserve `VOUCHERNUMBER` |
| `BILLALLOCATIONS` | `bill_allocations` | `NAME`=invoice ref, `AMOUNT`=allocated, compute outstanding |
| `BATCHALLOCATIONS` | `batches + stock_movements` | `BATCHNAME`, `EXPIRYPERIOD` → batch record |

### 7.3 Dry Run Validation Rules

- Each voucher must balance (DR == CR). Flag any that do not.
- Verify opening balances reconcile with ledger totals.
- Flag negative stock at any point in the timeline.
- Flag unmatched purchase invoices (`bill_allocations` with no matching voucher).
- Detect duplicate idempotency keys and list them separately (not errors — skips).
- `PRAGMA integrity_check` and `PRAGMA foreign_key_check` run after import transaction commits.

### 7.4 Canonical CSV / JSON / Excel Import Templates

All non-Tally imports must conform to the following schema. Any file deviating from this schema is rejected with column-level error messages.

| Template | Required Columns | Optional Columns |
|---|---|---|
| Voucher Import | `date, voucher_type, ledger_dr, ledger_cr, amount, narration` | `line_narration, stock_item, qty, godown, cheque_no` |
| Ledger Master | `name, group, opening_balance, dr_cr` | `cost_center, address, phone` |
| Stock Item | `name, unit, opening_qty, opening_rate, godown` | `sku, batch_no, expiry_date, valuation_method` |

---

## 8. Google Drive Backup, Restore and Three-Way Merge

### 8.1 Backup Flow

- Export encrypted DB: `company_<id>_backup_<ts>.enc` using AES-256; key in Android Keystore.
- Upload to dedicated app folder in Google Drive via Drive API (OAuth2 scope: `drive.appdata`).
- Store backup metadata locally: `file_id, timestamp, checksum, schema_version`.
- WorkManager schedules daily backup at user-configured time; failure triggers notification.

### 8.2 Restore / Merge Flow

1. Download remote backup, decrypt to temp DB.
2. If last common backup exists, use as base; otherwise treat remote as separate branch.
3. Three-way merge compares base, local, remote using `last_modified + version`.
4. Auto-resolve non-financial metadata (`last_modified` wins).
5. Flag financial conflicts (vouchers, opening balances, `stock_movements`) for manual resolution.
6. Conflict UI: side-by-side compact rows with voucher number, date, amounts, ledger names. Actions: **Accept Local / Accept Remote / Edit.**
7. Apply resolutions, append audit entries with `source='merge'`, commit merged DB.
8. Upload merged DB as new canonical backup.

> **NEVER auto-overwrite voucher amounts or stock_movements without manual approval.**

### 8.3 Conflict Resolution Policy

- Row-level versioning: `version INTEGER` increments on every UPDATE.
- Source tag on every row: `local` / `remote` / `imported` / `merged`.
- `import_manifest_id` FK provides provenance for every imported row.
- `sync_changes` queue: retain max 90 days or 50,000 rows, whichever comes first. Compact older entries after backup commit.
- Post-merge: run `PRAGMA integrity_check` before committing merged DB.

---

## 9. Reports

| Report | Source | Key Parameters |
|---|---|---|
| Daybook | `vouchers + voucher_lines` | date range, voucher type filter, page size |
| Trial Balance | ledger aggregates + opening balances | as-of date, FY |
| Profit & Loss | `monthly_aggregates` + live lines | FY, from/to date |
| Balance Sheet | ledger groups + TB | as-of date; must balance or show difference line |
| Monthly Sales/Purchase | `monthly_aggregates` | FY, item/ledger filter |
| Buyer-wise Ledger | `voucher_lines` per ledger | ledger, FY, outstanding-only toggle |
| Aging Report | `bill_allocations.outstanding_amount` | as-of date, bucket widths |
| Bank Reconciliation | `bank_reconciliation + bank_instruments` | ledger, statement date |
| Stock Summary | `stock_movements` aggregate | as-of date, godown filter |
| Exception Report | `audit_logs` + negative stock + unmatched bills | FY, exception type |

---

## 10. UX and Android Design Requirements

### 10.1 Core Screens

- **Voucher Quick Entry:** compact form, auto-complete for ledgers/stock, line-level narration, undo/redo within form session, templates for frequent vouchers.
- **CA Dashboard:** exceptions panel (negative stock, unmatched bills, expiring batches, BRS differences), trial balance snapshot, last backup status, reconciliation suggestions.
- **Import Wizard:** file select → version detection → mapping UI → dry run report → import summary.
- **Conflict Resolution UI:** side-by-side compact rows, Accept Local / Accept Remote / Edit actions, reason field, batch-accept option.
- **Backup Center:** backup list with timestamps, schedule config, manual upload/restore, sync status indicator.
- **BRS Screen:** book balance, uncleared instrument list, bank balance input, difference indicator, mark-cleared workflow.

### 10.2 Platform Considerations

- Biometric lock (`Android BiometricPrompt`) on company open; falls back to PIN.
- Tablet/landscape layout: voucher entry uses two-column layout on screens wider than 600dp.
- Offline status indicator: persistent banner showing last sync time and whether local DB is ahead of Drive.
- Deep link + notification for backup failures from WorkManager.
- Undo/redo within voucher entry form (in-session state management only — not audit trail).
- Print vs screen PDF layout: invoice PDFs use A4 portrait with header/footer/logo; report PDFs use landscape for wide tables.
- Share sheet: PDF and Excel via Android `ACTION_SEND` intent (email, WhatsApp, Drive, other apps).

---

## 11. PDF Generation and Export

- Use Flutter `pdf` package for all PDF generation.
- **Invoice PDF:** company letterhead, logo placeholder, party details, item table, total, narration, CA signature block.
- **Report PDF:** landscape A4 for wide reports (Trial Balance, Balance Sheet); portrait for Daybook and BRS.
- **BRS PDF:** CA signature block and statement date prominently displayed.
- **Excel export:** use `excel` package; formatted sheets with freeze panes and column auto-width.
- Share via Android `ACTION_SEND` intent; do not hard-code any app package names.

---

## 12. Performance Targets and QA Acceptance

| Test | Target | Method |
|---|---|---|
| Daybook load (90 days, 10k vouchers) | < 2s on mid-range device | Indexed query + pagination; benchmark with test dataset |
| FTS5 search (top 50 results) | < 500ms | FTS5 with tokenizer; measure p95 on 10k narrations |
| Bulk import (10k vouchers) | < 30s background | Single transaction; WorkManager progress notification |
| Backup/restore (5–20 MB DB) | < 60s on 4G | Drive API resumable upload; measure on throttled network |
| Memory (4 GB device) | No OOM | Paginated lists (LazyColumn); no unbounded result sets in RAM |
| Schema migration (any version gap) | < 5s | Benchmark migration chain on oldest supported schema |

### 12.1 Test Plan

- **Unit tests:** `VoucherEngine` (balance check, FY lock, Contra constraint), `InventoryEngine` (FIFO/LIFO/WA valuation), `BRSEngine`.
- **Integration tests:** Tally XML import end-to-end (valid, malformed, duplicate, multi-company), CSV import with canonical template.
- **Device tests:** backup/restore round-trip, three-way merge with and without conflicts, biometric lock flow.
- **Performance benchmarks:** automated test with 10k voucher dataset; CI gate must pass all targets.
- **CA validation tests:** TB must balance, BS must balance, Credit/Debit Note must reverse stock, Contra must reject non-cash/bank ledger.

---

## 13. Known Gaps (Documented, Not In Scope for v1)

| Gap | Impact if Skipped | Planned Version |
|---|---|---|
| Cost centers / categories | No project-wise P&L | v1.2 |
| GST / TDS computation | Tax returns not possible | v2.0 |
| Multi-currency | International clients not supported | v2.0 |
| Web / iOS app | Android-only | v2.0 |
| Tally Prime 3.x XML schema | Import may fail for Prime 3.x users | v1.1 |
| Auto bank statement import (PDF/CSV) | Manual BRS entry only | v1.1 |

---

## 14. Deliverables Checklist

- [ ] Flutter source with modular feature folders (`voucher`, `inventory`, `reports`, `import`, `backup`, `brs`).
- [ ] Drift entities and DAOs for all tables in Section 4.2.
- [ ] SQLCipher integration guide and keystore key management code.
- [ ] Tally XML import module with version-branched parser and idempotency guard.
- [ ] Google Drive backup/restore and three-way merge module.
- [ ] BRS module: mark-cleared workflow, BRS report, PDF export.
- [ ] Wireframes: voucher entry, CA dashboard, import wizard, conflict UI, BRS screen, backup center.
- [ ] Internal service layer API spec (methods in Section 2.2) with input/output types.
- [ ] Canonical CSV/JSON/Excel import templates with schema documentation.
- [ ] Test dataset: 10k vouchers across 3 companies, 2 FYs, with edge cases (negative stock, unmatched bills, locked FY).
- [ ] Performance benchmark report from CI run against test dataset.

---

> **Version history:** v1.0 — initial consolidated spec merging original vision document with CA/DB/UX review gaps. Next review trigger: any schema change, new voucher type, or scope change to BRS or import engine.
