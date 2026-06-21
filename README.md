# Naya Vyapaar Sync (TallyDroid)
A zero-server, CA-grade offline-first accounting and inventory management application for Android, built using Flutter. It is designed to mirror desktop Tally-style workflows on mobile devices, providing accountants and business owners with full double-entry bookkeeping, godown (warehouse) inventory tracking, and bank reconciliation, all without relying on a centralized server.

---

## 📖 Table of Contents
1. [Overview & Strategic Goal](#1-overview--strategic-goal)
2. [Accounting & Architecture for Beginners](#2-accounting--architecture-for-beginners)
3. [Directory & Module Layout](#3-directory--module-layout)
4. [Role-Based Access Control (RBAC)](#4-role-based-access-control-rbac)
5. [Architecture & Data Flow](#5-architecture--data-flow)
6. [Offline Synchronization Lifecycle](#6-offline-synchronization-lifecycle)
7. [Core Features & Modules](#7-core-features--modules)
8. [Database Schema & Structure](#8-database-schema--structure)
9. [Getting Started (Developer Guide)](#9-getting-started-developer-guide)
10. [Verification & Testing](#10-verification--testing)

---

## 1. Overview & Strategic Goal

### The Problem
Traditional business accounting systems (like Tally) are locked to desktop environments, making it extremely difficult for business owners, warehouse managers, and accountants to log transactions or inspect stock quantities in real time when on the move. Meanwhile, cloud-based accounting services require constant internet connectivity, pose data privacy risks, and incur recurring subscription fees.

### The Strategic Goal
**Naya Vyapaar Sync (TallyDroid)** is designed as a **zero-server, offline-first mobile companion** to Tally. The strategic objective is to offer a CA-grade double-entry ledger and inventory tracker directly on Android that:
1. **Ensures Data Ownership:** Stores all company financial records locally in an encrypted SQLite database on the device.
2. **Bridges Desktop & Mobile:** Supports direct import of Tally `.xml` exports to backfill years of accounting data in seconds.
3. **Collaborates Without Servers:** Utilizes users' private Google Drive storage for automated backup/sync and a robust **three-way merge engine** to resolve changes made offline on separate devices.
4. **Guarantees CA-Grade Accuracy:** Enforces strict accounting principles (balanced entries, locked periods, audit trails) to produce reports that Chartered Accountants can instantly verify and sign off on.

---

## 2. Accounting & Architecture for Beginners

If you are new to accounting or mobile app architecture, here are the core concepts that power this application:

### A. What is "Double-Entry" Bookkeeping?
Unlike simple logbooks where you write down only what you spent, professional accounting uses a double-entry system:
* **Every transaction affects at least two accounts:** a **Debit (DR)** side and a **Credit (CR)** side.
* **The Golden Rule:** The total amount of debits must always equal the total amount of credits for a transaction to be valid. 
* *Example:* If you sell goods for ₹5,000 in cash, cash is Debited (increased) by ₹5,000, and Sales Revenue is Credited (increased) by ₹5,000. The app strictly enforces this balancing check before saving any transaction.

### B. What does "Zero-Server" & "Offline-First" Mean?
* **Offline-First:** All operations—creating invoices, checking stock, and generating Balance Sheets—are performed directly on your Android device without needing the internet.
* **Zero-Server:** There is no central computer or server database (like AWS or Google Cloud) owned by the developers. Your data is stored on your own phone. If you want to sync multiple devices, the app uploads database snapshots to your *own* private Google Drive account.

### C. What is a "Three-Way Merge"?
When two different devices make changes offline (e.g., Device A adds an expense and Device B records a sale) and then sync, the app needs to combine their databases.
* It looks at a **Base version** (the last time they synced).
* It compares **Local changes** (on Device A) and **Remote changes** (on Device B).
* It merges non-conflicting entries automatically and prompts the user with a visual side-by-side comparison screen to resolve overlapping changes (conflicts) without losing financial data.

---

## 3. Directory & Module Layout

The codebase is structured under the `lib` folder as a clean, feature-modular layered architecture:

* **[lib/core/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/core/)**: Cross-cutting utilities and styles.
  * `theme/`: App colors, typography, and shape styling tokens.
  * `utils/`: Common formats, date parsed rules, and validation logic.
* **[lib/data/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/data/)**: Low-level database drivers, entities, and repository layers.
  * `database/`: Contains the SQLite core [db_helper.dart](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/data/database/db_helper.dart) driving schema upgrades.
  * `models/`: Models describing structural fields (e.g., `voucher.dart`, `app_user.dart`, `stock_movement.dart`).
  * `repositories/`: Repository implementations that fetch and format SQLite data for Riverpod providers.
* **[lib/domain/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/domain/)**: Business engines enforcing accounting rules.
  * `services/`: Contains the `voucher_engine.dart` (validating double-entries and financial year locks) and `reports_engine.dart` (aggregating ledger journals into Trial Balances, P&L, and Balance Sheets).
* **[lib/services/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/services/)**: Technical system-level interfaces.
  * `gdrive_service.dart`: Integrates Google Drive upload/download interfaces.
  * `sync_queue_service.dart`: Orchestrates incremental sync logging and Google Drive polling.
  * `tally_import_service.dart`: Reads, detects version, and sandbox-validates Tally XML files.
* **[lib/sync/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/sync/)**: Sync conflict management and merge engines.
  * `sync_applier.dart`: Handles incoming remote logs and triggers conflict-logging.
  * `device_registry.dart` & `manifest_manager.dart`: Coordinates device authorization roles and registers sync status.
* **[lib/ui/](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/ui/)**: User interfaces.
  * `screens/`: Individual views grouped by domain (e.g., `voucher/` for entry forms, `brs/` for bank reconciliation, `backup/` for sync settings).
  * `widgets/`: Reusable interface components.

---

## 4. Role-Based Access Control (RBAC)

The application enforces a granular security model to partition accountant entry from administrative and audit processes:

| Feature / Action | Admin | CA (Chartered Accountant) | Accountant | Manager |
|---|---|---|---|---|
| **View Reports & Aggregates** | Yes | Yes | Yes | Yes |
| **Record/Edit Vouchers** | Yes | Yes | Yes | No (Read-Only) |
| **Lock / Unlock Financial Years** | Yes | Yes | No | No |
| **Manage Users & Role Assignments** | Yes | No | No | No |
| **Trigger GDrive Sync & Restores** | Yes | Yes | Yes | No |

*Security Rule:* When a financial period is marked as locked by an Admin or CA, attempts to insert or modify a voucher will throw a `FYLockedException`, which prevents data changes and preserves audit integrity.

---

## 5. Architecture & Data Flow

### 5.1 The Technical Stack
* **Frontend:** [Flutter](https://flutter.dev/) (UI layer) + [Riverpod](https://riverpod.dev/) (for state management and reactive data updates).
* **Local Database:** SQLite (interacted through the `sqflite` package in [db_helper.dart](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/data/database/db_helper.dart)).
* **Search Engine:** SQLite FTS5 (Full-Text Search) virtual tables, synchronized via database triggers for instant, fuzzy searches.
* **Sync & Backup:** Google Drive API (OAuth2) using the user's secure application-data folder.
* **Exporting:** `pdf` package for professional invoice/report layout exports and `excel` package for spreadsheets.

### 5.2 High-Level Architecture Diagram
The app follows a clean, layered architecture separating the visual interfaces from data storage and cloud integration:

```
+-----------------------------------------------------------+
|                        Flutter UI                         |
|   (Screens: Dashboard, Voucher Entry, Reports, BRS, etc.)  |
+-----------------------------+-----------------------------+
                              |
                              | Read / Write State
                              v
+-----------------------------------------------------------+
|                  Domain Services Layer                    |
|   (VoucherEngine, InventoryEngine, BRS, SyncManager)      |
+-----------------------------+-----------------------------+
                              |
                              | SQL Queries / Transactions
                              v
+-----------------------------------------------------------+
|                   Local Database Layer                    |
|             (SQLite via sqflite, DB helper)               |
+-----------------------------+-----------------------------+
                              |
                              | Local Sync Change Queue
                              v
+-----------------------------------------------------------+
|                   Sync & Merge Engine                     |
|           (GDrive API, Three-Way Merge Applier)          |
+-----------------------------+-----------------------------+
                              |
                              | Secure OAuth2 Sync
                              v
+-----------------------------------------------------------+
|                  Google Drive App Folder                  |
|                 (Encrypted Remote Storage)                |
+-----------------------------------------------------------+
```

---

## 6. Offline Synchronization Lifecycle

Naya Vyapaar Sync operates without a central server database. Instead, it utilizes client-driven replication coordinated through a shared manifest file on Google Drive:

```
                  +-----------------------------------+
                  |      Google Drive Manifest        |
                  |  (Tracks device status & roles)   |
                  +-----------------+-----------------+
                                    |
            1. Pull Manifest        |   3. Push Local Logs
            & Apply Remote Logs     |   & Update Watermark
                                    v
                  +-----------------+-----------------+
                  |          Local Device             |
                  |     (Pending Queue in SQLite)     |
                  +-----------------+-----------------+
                                    |
                                    | 2. Detect Overlaps
                                    v
                  +-----------------+-----------------+
                  |      Conflict Resolution UI       |
                  |  (Accept Local / Remote / Edit)   |
                  +-----------------------------------+
```

### Sync Lifecycle Steps
1. **Queue (Offline):** When a user creates or modifies a voucher, the application commits the data to SQLite and adds an event record containing the change operation and JSON payload to the local `sync_queue` table with a state of `PENDING`.
2. **Pull (Online):** When a sync is triggered, the app downloads `manifest.json` from Google Drive. It reviews the watermark timestamp of logs submitted by other registered devices and downloads new log packages.
3. **Merge Application:**
   * If a downloaded remote change modifies a record that has **no** pending edits in the local `sync_queue`, it is applied to the local database table using `SyncApplier.applySyncItem`.
   * If a remote change modifies a record that **does** have a pending local change (overlap), a conflict is identified. The remote change is halted, and details are logged to the `sync_conflicts` table. The UI prompts the user to resolve the conflict.
4. **Push:** Once remote changes are applied, the local `PENDING` logs are bundled into a JSON file (`sync_log_{deviceId}_{timestamp}.json`), uploaded to Google Drive, and marked as `DONE` in the local DB.
5. **Snapshot Consolidation:** To keep history clean, the `SnapshotCoordinator` prompts a device to consolidate logs by uploading the entire SQLite DB as a baseline snapshot and pruning older logs from Google Drive.

---

## 7. Core Features & Modules

### 7.1 Double-Entry Voucher Engine
Supports standard commercial transaction types matching Tally's conventions:
* **Sales & Purchases:** For logging client invoices and supplier bills.
* **Receipts & Payments:** For cash/bank inflows and outflows.
* **Contra:** Strictly for internal bank transfers (e.g., withdrawing cash from the bank).
* **Journals:** For non-cash adjustment entries.
* **Credit Notes & Debit Notes:** For sales and purchase returns (not negative invoices).

### 7.2 Godown & Batch Inventory
Tracks physical items per-location with accounting precision:
* **Multi-Godown:** Trace stock transfers and balances across multiple warehouses.
* **Valuation Methods:** Supports FIFO (First-In-First-Out), LIFO, and Weighted Average costing per-item.
* **Batch Tracking:** Expiry and manufacturing dates are attached to item batches for food/chemical stock rules.

### 7.3 Tally XML Import Engine
Enables importing data exported from Tally:
1. **Version Detection:** Reads the `<TALLYBUILDNO>` attribute to distinguish XML formats between Tally 7.2 and Tally Prime.
2. **Idempotency Guard:** Builds a signature from the voucher number, date, and company name to reject duplicate postings.
3. **Transaction Sandbox:** Validates voucher integrity before applying edits.

### 7.4 Bank Reconciliation (BRS)
Matches the bank book ledger with the actual bank statement. Users record instrument details (cheques, UPI IDs) and mark transactions as "Cleared" when they appear on the bank statement, generating a reconciliation sheet.

---

## 8. Database Schema & Structure

All database interactions are defined in [db_helper.dart](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/data/database/db_helper.dart). Key tables include:

| Table Name | Primary Responsibility | Key Fields |
|---|---|---|
| `companies` | Represents distinct business entities. | `id`, `name`, `gstin`, `address`, `state` |
| `financial_years` | Restricts accounting operations within specific boundaries. | `id`, `company_id`, `label`, `is_locked` |
| `ledgers` | Individual ledger accounts. | `id`, `name`, `group_id`, `opening_balance` |
| `ledger_groups` | Hierarchical groupings like Assets, Liabilities, etc. | `id`, `name`, `parent_id`, `nature` |
| `vouchers` | Headers for double-entry transactions. | `id`, `voucher_no`, `type`, `date`, `is_locked` |
| `voucher_lines` | Debit/credit line entries containing amounts. | `id`, `voucher_id`, `ledger_id`, `dr_amount`, `cr_amount` |
| `stock_movements` | Log of item transfers in/out of specific godowns. | `id`, `stock_item_id`, `godown_id`, `qty`, `rate`, `movement_type` |
| `sync_queue` | Queue of offline modifications waiting to sync. | `id`, `operation`, `table_name`, `record_id`, `payload`, `status` |
| `sync_conflicts` | Unresolved conflict entries displayed in the UI. | `id`, `table_name`, `record_id`, `local_payload`, `remote_payload`, `resolved` |

---

## 9. Getting Started (Developer Guide)

Follow these instructions to run the project on your local machine.

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.12.2 or higher recommended)
* [Dart SDK](https://dart.dev/get-started)
* Android SDK (for compiling the Android app)
* A physical Android device or emulator

### Installation
1. Clone this repository to your workspace.
2. Fetch the packages and dependencies:
   ```bash
   flutter pub get
   ```
3. Generate the required Riverpod annotations and model code:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
4. Run the project in development mode:
   ```bash
   flutter run
   ```

### Troubleshooting
* **Riverpod/Code Generation Issues:** If generated files are missing or out-of-date, clean the build runner cache and rebuild:
  ```bash
  flutter pub run build_runner clean
  flutter pub run build_runner build --delete-conflicting-outputs
  ```
* **Database Upgrades & Schema Version Mismatches:** If you receive DB constraint or schema errors when updating models, increment the `version` variable in `_initDatabase()` inside [db_helper.dart](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/lib/data/database/db_helper.dart) and define the migration logic under `_onUpgrade`.

---

## 10. Verification & Testing

Verify that your environment is working correctly by running the suite of tests:
* **Unit & Widget Tests:** Enforce business constraints (e.g., making sure vouchers balance and Contra transactions only refer to cash/bank).
  ```bash
  flutter test
  ```
* **Performance Testing:** Ensures the database Daybook loads 10k+ vouchers in under 2 seconds.

---

This README is designed to serve as the definitive entry point for developers and accountants contributing to Naya Vyapaar Sync. For structural rules and implementation details, refer to the [TallyDroid Master Spec](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/TallyDroid_Master_Spec_v1.md) and [GEMINI Instructions](file:///Users/karthikganji/Downloads/analyze-devops-2/untitled%20folder/nayavyapaarsync/GEMINI.md).
