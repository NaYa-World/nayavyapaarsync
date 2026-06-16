# TallyDroid — Full Implementation Roadmap

---

## ✅ Phase 1 — Completed
- Tally XML import (version detection, idempotency, multi-company logging)
- Dashboard Tally-style Gateway Header (Current Period + Company Name)
- Conflict resolution (field-level, sync_conflicts v2)
- Audit logs, GDrive backup/restore

---

## 🚧 Phase 2 — Executing Now
**Goal**: Additive must-have metadata features. Zero breaking changes.

| # | Feature | Key Files |
|---|---|---|
| 1 | **Companies table** (DB v8) | `companies`, seeded from current settings |
| 2 | **Financial Years table** (DB v8) | `financial_years` per company |
| 3 | **User Roles** (DB v8) | `app_users` with ADMIN/CA/ACCOUNTANT/MANAGER |
| 4 | **FY Lock Guard** | Rejects voucher entry on locked periods |
| 5 | **Cheque Tracking** | 4 new columns on `payments` + UI fields |

### Branch & Commits
```
feat/multi-company-schema   →  feat: add companies and financial_years schema (DB v8)
feat/user-roles             →  feat: add app_users table with role-based access
feat/fy-lock-guard          →  feat: add financial year lock guard for voucher entry
feat/cheque-tracking        →  feat: add cheque fields to payments table and UI
```

---

## 📋 Phase 3 — Double-Entry Engine & Advanced Reports
**Goal**: Transform from simplified trading tables to CA-grade double-entry ledger.

### 3.1 Double-Entry Voucher Engine (DB v9)
New tables replacing simplified `sales/purchases` (keeping old tables for backward compat):

```sql
-- Ledger groups (like Tally groups)
CREATE TABLE ledger_groups (id, name, parent_id, nature CHECK IN ('ASSETS','LIABILITIES','INCOME','EXPENSES'));

-- Ledgers (like Tally ledgers — each party, bank, cash is a ledger)
CREATE TABLE ledgers (id, name, group_id, opening_balance, balance_type CHECK IN ('DR','CR'), company_id);

-- Master voucher header
CREATE TABLE vouchers (
  id, voucher_no, type CHECK IN ('SALE','PURCHASE','RECEIPT','PAYMENT','CONTRA','JOURNAL','CREDIT_NOTE','DEBIT_NOTE'),
  date, narration, company_id, fy_id, is_locked, created_at
);

-- Double-entry lines (every voucher must balance: SUM(DR) = SUM(CR))
CREATE TABLE voucher_lines (id, voucher_id, ledger_id, dr_amount, cr_amount, narration);

-- Bill allocation (link payment vouchers to invoices)
CREATE TABLE bill_allocations (id, voucher_id, against_voucher_id, amount, bill_date, due_date);
```

### 3.2 Bank Reconciliation (BRS) Module (DB v9)
```sql
CREATE TABLE bank_instruments (
  id, voucher_id, instrument_type CHECK IN ('CHEQUE','DD','NEFT','RTGS','UPI'),
  instrument_no, bank_name, instrument_date, amount,
  status CHECK IN ('ISSUED','PRESENTED','CLEARED','BOUNCED','CANCELLED'),
  cleared_date, bank_ref_no
);
CREATE TABLE bank_reconciliation (id, ledger_id, statement_date, closing_balance_bank, closing_balance_book, difference, reconciled_by, reconciled_at);
```

### 3.3 Missing Reports
- **Trial Balance** — Ledger-wise debit/credit totals
- **Profit & Loss** — Income vs Expense ledger groups
- **Balance Sheet** — Assets vs Liabilities
- **BRS Report** — Uncleared instruments vs bank statement

### 3.4 FTS5 SmartFind
```sql
CREATE VIRTUAL TABLE fts_vouchers USING fts5(narration, party_name, voucher_no, content='vouchers');
CREATE VIRTUAL TABLE fts_ledgers  USING fts5(name, content='ledgers');
```

### Branch & Commits
```
feat/double-entry-schema    →  feat: add vouchers, voucher_lines, ledgers schema (DB v9)
feat/brs-module             →  feat: add bank reconciliation module and instruments table
feat/advanced-reports       →  feat: add trial balance, P&L and balance sheet reports
feat/fts5-smartfind         →  feat: add FTS5 virtual tables for smart voucher search
```

---

## 📋 Phase 4 — Security, Encryption & Import
**Goal**: Harden the app for CA/enterprise use.

### 4.1 SQLCipher Encryption
- Replace `sqflite` → `sqflite_sqlcipher` in `pubspec.yaml`
- Generate a 256-bit AES key on first run, store in `flutter_secure_storage`
- Run `PRAGMA key = '...'` after every `openDatabase` call
- One-time DB re-key for existing installations (plain → encrypted)

### 4.2 Biometric Unlock
- Add `local_auth: ^2.x` to `pubspec.yaml`
- On app resume: show lock screen → biometric → PIN fallback
- Store "biometric enabled" flag in `flutter_secure_storage`

### 4.3 CSV / Excel Import Template
- Add `excel: ^4.x` and `csv: ^6.x` to `pubspec.yaml`
- Upload wizard: pick file → map columns → preview 5 rows → confirm import
- Templates for: Parties, Items, Opening Balances, Vouchers

### 4.4 Per-Company DB Files (Option A)
- Migrate `DbHelper` singleton to `CompanyDbManager` that opens `{companyId}.db`
- Move all existing data from `godown_management.db` → `{company1Id}.db`
- Company picker on launch and company switcher in drawer

### Branch & Commits
```
feat/sqlcipher-encryption   →  feat: encrypt database with SQLCipher AES-256
feat/biometric-unlock       →  feat: add biometric and PIN lock screen
feat/csv-excel-import       →  feat: add CSV/Excel import wizard for parties and items
feat/per-company-db         →  feat: migrate to per-company database files
```

---

## Summary Table

| Phase | Features | Status |
|---|---|---|
| **Phase 1** | XML import, Dashboard header, Conflict resolution | ✅ Done |
| **Phase 2** | Company metadata, User roles, FY lock, Cheque tracking | 🚧 In Progress |
| **Phase 3** | Double-entry engine, BRS, FTS5, Advanced reports | 📋 Planned |
| **Phase 4** | Encryption, Biometric, CSV import, Per-company DB | 📋 Planned |
