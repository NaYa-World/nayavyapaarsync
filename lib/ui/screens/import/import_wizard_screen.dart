import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../../../data/database/db_helper.dart';
import '../../../data/models/party.dart';
import '../../../data/models/item.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/item_provider.dart';

enum ImportType { parties, items }

class ImportWizardScreen extends ConsumerStatefulWidget {
  const ImportWizardScreen({super.key});

  @override
  ConsumerState<ImportWizardScreen> createState() => _ImportWizardScreenState();
}

class _ImportWizardScreenState extends ConsumerState<ImportWizardScreen> {
  int _currentStep = 0;
  ImportType _importType = ImportType.parties;
  File? _selectedFile;
  String? _fileName;
  int? _fileSize;

  List<String> _headers = [];
  List<List<String>> _allDataRows = []; // contains parsed rows as string values
  
  // Mapping of DB Field -> Excel/CSV Header Index
  final Map<String, int?> _fieldMappings = {};
  
  // Sets of lowercase existing names in DB to prevent duplicates
  Set<String> _existingNamesInDb = {};

  bool _isProcessing = false;
  String? _errorMessage;

  // DB Fields configuration
  List<String> get _targetFields {
    if (_importType == ImportType.parties) {
      return ['Name', 'Type (CUSTOMER/SUPPLIER)', 'Phone', 'Address', 'GSTIN', 'Opening Balance', 'Balance Type (DR/CR)'];
    } else {
      return ['Name', 'Category (SEED/FERTILISER)', 'HSN Code', 'GST Rate', 'Primary Unit (BAG/BOX)', 'Box Weight', 'Bag Weight', 'Stock Group'];
    }
  }

  List<String> get _requiredFields {
    if (_importType == ImportType.parties) {
      return ['Name', 'Type (CUSTOMER/SUPPLIER)', 'Phone'];
    } else {
      return ['Name', 'Category (SEED/FERTILISER)', 'HSN Code', 'GST Rate', 'Primary Unit (BAG/BOX)'];
    }
  }

  @override
  void initState() {
    super.initState();
    _resetWizard();
  }

  void _resetWizard() {
    setState(() {
      _selectedFile = null;
      _fileName = null;
      _fileSize = null;
      _headers = [];
      _allDataRows = [];
      _fieldMappings.clear();
      _errorMessage = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final name = result.files.single.name;
      final size = result.files.single.size;

      setState(() {
        _selectedFile = file;
        _fileName = name;
        _fileSize = size;
        _errorMessage = null;
      });

      _parseFileHeaders();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select file: $e';
      });
    }
  }

  Future<void> _parseFileHeaders() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final path = _selectedFile!.path.toLowerCase();
      if (path.endsWith('.csv')) {
        await _parseCsv();
      } else {
        await _parseExcel();
      }

      // Pre-populate mappings based on exact/partial name matches
      _autoMapFields();
      
      setState(() {
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to parse file structure: $e';
        _selectedFile = null;
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _parseCsv() async {
    final bytes = await _selectedFile!.readAsBytes();
    String csvString;
    try {
      csvString = utf8.decode(bytes);
    } catch (_) {
      csvString = utf8.decode(bytes, allowMalformed: true);
    }

    final List<List<dynamic>> rows = const CsvToListConverter().convert(csvString);
    if (rows.isEmpty) {
      throw Exception('CSV file is empty');
    }

    final headers = rows.first.map((cell) => cell?.toString().trim() ?? '').toList();
    
    // Parse all other rows as string data
    final List<List<String>> dataRows = [];
    for (int i = 1; i < rows.length; i++) {
      final dataRow = rows[i].map((cell) => cell?.toString().trim() ?? '').toList();
      // Only add non-empty rows
      if (dataRow.any((val) => val.isNotEmpty)) {
        dataRows.add(dataRow);
      }
    }

    setState(() {
      _headers = headers;
      _allDataRows = dataRows;
    });
  }

  Future<void> _parseExcel() async {
    final bytes = await _selectedFile!.readAsBytes();
    final excel = excel_pkg.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('Excel sheet is empty');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    if (sheet.rows.isEmpty) {
      throw Exception('Excel sheet has no rows');
    }

    final headers = sheet.rows.first.map((cell) => cell?.value?.toString().trim() ?? '').toList();
    
    final List<List<String>> dataRows = [];
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final dataRow = row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
      // Align row size with headers length
      while (dataRow.length < headers.length) {
        dataRow.add('');
      }
      if (dataRow.any((val) => val.isNotEmpty)) {
        dataRows.add(dataRow);
      }
    }

    setState(() {
      _headers = headers;
      _allDataRows = dataRows;
    });
  }

  void _autoMapFields() {
    _fieldMappings.clear();
    for (final field in _targetFields) {
      final normalizedField = field.toLowerCase();
      int? matchedIndex;

      for (int i = 0; i < _headers.length; i++) {
        final header = _headers[i].toLowerCase();
        if (header == normalizedField || 
            normalizedField.contains(header) || 
            header.contains(normalizedField.split(' ').first)) {
          matchedIndex = i;
          break;
        }
      }

      _fieldMappings[field] = matchedIndex;
    }
  }

  Future<void> _fetchExistingDbNames() async {
    setState(() {
      _isProcessing = true;
    });
    try {
      final db = await DbHelper().database;
      if (_importType == ImportType.parties) {
        final List<Map<String, dynamic>> res = await db.query('parties', columns: ['name']);
        _existingNamesInDb = res.map((r) => (r['name'] as String).toLowerCase()).toSet();
      } else {
        final List<Map<String, dynamic>> res = await db.query('items', columns: ['name']);
        _existingNamesInDb = res.map((r) => (r['name'] as String).toLowerCase()).toSet();
      }
    } catch (e) {
      debugPrint('Error loading existing names: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Cell Validation: returns null if valid, or String error message
  String? _validateCell(String fieldName, String value) {
    final cleanValue = value.trim();

    if (_requiredFields.contains(fieldName) && cleanValue.isEmpty) {
      return 'Required field cannot be empty';
    }

    if (cleanValue.isEmpty) return null; // Optional cell empty is valid

    if (fieldName == 'Name') {
      if (_existingNamesInDb.contains(cleanValue.toLowerCase())) {
        return 'Name already exists in database';
      }
      return null;
    }

    if (fieldName == 'Type (CUSTOMER/SUPPLIER)') {
      final upper = cleanValue.toUpperCase();
      if (upper != 'CUSTOMER' && upper != 'SUPPLIER') {
        return 'Must be CUSTOMER or SUPPLIER';
      }
      return null;
    }

    if (fieldName == 'Phone') {
      final phoneDigits = cleanValue.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.length != 10) {
        return 'Must be a 10-digit number';
      }
      return null;
    }

    if (fieldName == 'GSTIN') {
      final gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$', caseSensitive: false);
      if (!gstRegex.hasMatch(cleanValue)) {
        return 'Invalid 15-character GSTIN format';
      }
      return null;
    }

    if (fieldName == 'Opening Balance') {
      final num = double.tryParse(cleanValue);
      if (num == null || num < 0) {
        return 'Must be a non-negative number';
      }
      return null;
    }

    if (fieldName == 'Balance Type (DR/CR)') {
      final upper = cleanValue.toUpperCase();
      if (upper != 'DR' && upper != 'CR') {
        return 'Must be DR or CR';
      }
      return null;
    }

    if (fieldName == 'Category (SEED/FERTILISER)') {
      final upper = cleanValue.toUpperCase();
      if (upper != 'SEED' && upper != 'FERTILISER') {
        return 'Must be SEED or FERTILISER';
      }
      return null;
    }

    if (fieldName == 'HSN Code') {
      final hsnRegex = RegExp(r'^\d{4,8}$');
      if (!hsnRegex.hasMatch(cleanValue)) {
        return 'Must be 4 to 8 digits';
      }
      return null;
    }

    if (fieldName == 'GST Rate') {
      final num = double.tryParse(cleanValue);
      if (num == null || num < 0) {
        return 'Must be a positive percentage';
      }
      return null;
    }

    if (fieldName == 'Primary Unit (BAG/BOX)') {
      final upper = cleanValue.toUpperCase();
      if (upper != 'BAG' && upper != 'BOX') {
        return 'Must be BAG or BOX';
      }
      return null;
    }

    if (fieldName == 'Box Weight' || fieldName == 'Bag Weight') {
      final num = double.tryParse(cleanValue);
      if (num == null || num <= 0) {
        return 'Must be a positive number';
      }
      return null;
    }

    return null;
  }

  // Check if mapping is complete (all required fields are mapped)
  bool _isMappingValid() {
    for (final req in _requiredFields) {
      if (_fieldMappings[req] == null) return false;
    }
    return true;
  }

  String _getCellValue(List<String> row, String fieldName) {
    final idx = _fieldMappings[fieldName];
    if (idx == null || idx >= row.length) return '';
    return row[idx];
  }

  // Perform full parsing and validation check
  bool _hasSheetErrors() {
    for (final row in _allDataRows) {
      for (final field in _targetFields) {
        final val = _getCellValue(row, field);
        if (_validateCell(field, val) != null) {
          return true;
        }
      }
    }
    return false;
  }

  int _countSheetErrors() {
    int count = 0;
    for (final row in _allDataRows) {
      for (final field in _targetFields) {
        final val = _getCellValue(row, field);
        if (_validateCell(field, val) != null) {
          count++;
        }
      }
    }
    return count;
  }

  Future<void> _processImport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final db = await DbHelper().database;
      final deviceId = ref.read(authProvider).deviceId;
      final uuid = const Uuid();
      final nowStr = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        if (_importType == ImportType.parties) {
          for (final row in _allDataRows) {
            final name = _getCellValue(row, 'Name').trim();
            final type = _getCellValue(row, 'Type (CUSTOMER/SUPPLIER)').trim().toUpperCase();
            final phone = _getCellValue(row, 'Phone').trim();
            final address = _getCellValue(row, 'Address').trim();
            final gstin = _getCellValue(row, 'GSTIN').trim();
            final opBalStr = _getCellValue(row, 'Opening Balance').trim();
            final opBal = double.tryParse(opBalStr) ?? 0.0;
            final balType = _getCellValue(row, 'Balance Type (DR/CR)').trim().toUpperCase();

            final partyId = uuid.v4();
            final party = Party(
              id: partyId,
              name: name,
              type: type,
              phone: phone,
              address: address.isNotEmpty ? address : 'Imported Address',
              gstin: gstin.isNotEmpty ? gstin : null,
              openingBalance: opBal,
              balanceType: balType.isNotEmpty ? balType : 'CR',
              createdAt: DateTime.now(),
            );

            final partyMap = party.toMap();

            // 1. Insert Party
            await txn.insert('parties', partyMap);

            // 2. Insert corresponding Ledger (required for Double-Entry Compatibility)
            await txn.insert('ledgers', {
              'id': 'led_$partyId',
              'name': name,
              'group_id': type == 'CUSTOMER' ? 'grp_debtors' : 'grp_creditors',
              'opening_balance': opBal,
              'balance_type': balType.isNotEmpty ? balType : (type == 'CUSTOMER' ? 'DR' : 'CR'),
              'company_id': 'company_default',
              'is_active': 1,
              'created_at': nowStr,
            });

            // 3. Audit Log entry
            await txn.insert('audit_logs', {
              'id': uuid.v4(),
              'table_name': 'parties',
              'record_id': partyId,
              'action': 'CREATE',
              'old_values': null,
              'new_values': jsonEncode(partyMap),
              'timestamp': nowStr,
              'device_id': deviceId,
            });

            // 4. Sync Queue entry
            await txn.insert('sync_queue', {
              'id': uuid.v4(),
              'operation': 'CREATE',
              'table_name': 'parties',
              'record_id': partyId,
              'payload': jsonEncode(partyMap),
              'created_at': nowStr,
              'status': 'PENDING',
            });
          }
        } else {
          // Items import
          for (final row in _allDataRows) {
            final name = _getCellValue(row, 'Name').trim();
            final category = _getCellValue(row, 'Category (SEED/FERTILISER)').trim().toUpperCase();
            final hsn = _getCellValue(row, 'HSN Code').trim();
            final rateStr = _getCellValue(row, 'GST Rate').trim();
            final rate = double.tryParse(rateStr) ?? 5.0;
            final primaryUnit = _getCellValue(row, 'Primary Unit (BAG/BOX)').trim().toUpperCase();
            final boxWeightStr = _getCellValue(row, 'Box Weight').trim();
            final boxWeight = double.tryParse(boxWeightStr);
            final bagWeightStr = _getCellValue(row, 'Bag Weight').trim();
            final bagWeight = double.tryParse(bagWeightStr);
            final stockGrp = _getCellValue(row, 'Stock Group').trim();

            final itemId = uuid.v4();
            final item = Item(
              id: itemId,
              name: name,
              category: category,
              hsnCode: hsn,
              gstRate: rate,
              primaryUnit: primaryUnit,
              boxWeightKg: boxWeight,
              bagWeightKg: bagWeight,
              createdAt: DateTime.now(),
              stockGroup: stockGrp.isNotEmpty ? stockGrp : 'General',
            );

            final itemMap = item.toMap();

            // 1. Insert Item
            await txn.insert('items', itemMap);

            // 2. Audit Log entry
            await txn.insert('audit_logs', {
              'id': uuid.v4(),
              'table_name': 'items',
              'record_id': itemId,
              'action': 'CREATE',
              'old_values': null,
              'new_values': jsonEncode(itemMap),
              'timestamp': nowStr,
              'device_id': deviceId,
            });

            // 3. Sync Queue entry
            await txn.insert('sync_queue', {
              'id': uuid.v4(),
              'operation': 'CREATE',
              'table_name': 'items',
              'record_id': itemId,
              'payload': jsonEncode(itemMap),
              'created_at': nowStr,
              'status': 'PENDING',
            });
          }
        }
      });

      // Reload providers
      await ref.read(partyProvider.notifier).loadParties();
      await ref.read(itemProvider.notifier).loadItems();

      // Show success screen
      setState(() {
        _currentStep = 4;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Transaction failed: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel / CSV Import Wizard'),
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing... Please wait.'),
                ],
              ),
            )
          : Column(
              children: [
                _buildProgressHeader(theme),
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildStepContent(theme, width),
                  ),
                ),
                _buildStepNavigation(theme),
              ],
            ),
    );
  }

  Widget _buildProgressHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (index) {
          final isCompleted = _currentStep > index;
          final isActive = _currentStep == index;
          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isCompleted
                      ? Colors.green
                      : isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive || isCompleted ? Colors.white : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                if (index < 4)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isCompleted ? Colors.green : theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme, double width) {
    switch (_currentStep) {
      case 0:
        return _buildStep1(theme);
      case 1:
        return _buildStep2(theme);
      case 2:
        return _buildStep3(theme);
      case 3:
        return _buildStep4(theme);
      case 4:
        return _buildStep5(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 1: Choose Import Type',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the type of master records you want to bulk import into the application.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: _importType == ImportType.parties ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _importType == ImportType.parties ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() => _importType = ImportType.parties),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.people_alt_rounded, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        const Text('Parties', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Customers & Suppliers', textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                elevation: _importType == ImportType.items ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _importType == ImportType.items ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() => _importType = ImportType.items),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        const Text('Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Seeds & Fertilizers', textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expected Columns Guide:', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ..._requiredFields.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text(f, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text(' (Required)', style: TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    )),
                ..._targetFields.where((f) => !_requiredFields.contains(f)).map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 16),
                          const SizedBox(width: 8),
                          Text(f),
                          const Text(' (Optional)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 2: Upload CSV or Excel file',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Upload your sheet containing the master records. Supported files: .csv, .xlsx, .xls',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _selectedFile != null ? Colors.green : theme.colorScheme.primary.withValues(alpha: 0.4),
                style: BorderStyle.solid,
                width: 2,
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _selectedFile != null ? Icons.task_rounded : Icons.cloud_upload_rounded,
                      size: 54,
                      color: _selectedFile != null ? Colors.green : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile != null ? 'File Attached Successfully!' : 'Tap to Browse File',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (_fileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _fileName!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Size: ${(_fileSize! / 1024).toStringAsFixed(2)} KB',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 3: Map Spreadsheet Columns',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Map standard database fields to columns detected in your sheet.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        ..._targetFields.map((field) {
          final isRequired = _requiredFields.contains(field);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(field, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (isRequired) const Text(' *', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isRequired ? 'Required database field' : 'Optional database field',
                          style: TextStyle(color: isRequired ? Colors.red.shade700 : Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<int>(
                      value: _fieldMappings[field],
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select Column'),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('Unmapped / None', style: TextStyle(color: Colors.grey)),
                        ),
                        ...List.generate(_headers.length, (index) {
                          return DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              '${_headers[index]} (Col ${index + 1})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _fieldMappings[field] = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep4(ThemeData theme) {
    final previewRowsCount = _allDataRows.length > 5 ? 5 : _allDataRows.length;
    final totalErrors = _countSheetErrors();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 4: Verification & Preview',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Verify validation constraints before importing. Invalid cells are highlighted in red.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: totalErrors > 0 ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: totalErrors > 0 ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                totalErrors > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                color: totalErrors > 0 ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  totalErrors > 0
                      ? 'Detected $totalErrors formatting errors in the spreadsheet. Please correct your file before proceeding.'
                      : 'Validation Passed! All ${_allDataRows.length} rows are formatted correctly.',
                  style: TextStyle(
                    color: totalErrors > 0 ? Colors.red.shade900 : Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Data Preview (First $previewRowsCount Rows):',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_allDataRows.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No data rows found in spreadsheet.')))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              border: TableBorder.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              columns: _targetFields.map((f) => DataColumn(label: Text(f, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              rows: List.generate(previewRowsCount, (rowIndex) {
                final row = _allDataRows[rowIndex];
                return DataRow(
                  cells: _targetFields.map((field) {
                    final val = _getCellValue(row, field);
                    final error = _validateCell(field, val);
                    return DataCell(
                      Tooltip(
                        message: error ?? 'Valid cell',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: error != null ? Colors.red.withValues(alpha: 0.15) : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (error != null) ...[
                                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 14),
                                const SizedBox(width: 4),
                              ],
                              Text(val.isEmpty ? '-' : val, style: TextStyle(color: error != null ? Colors.red.shade800 : null)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildStep5(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        const CircleAvatar(
          radius: 48,
          backgroundColor: Colors.green,
          child: Icon(Icons.done_all_rounded, size: 54, color: Colors.white),
        ),
        const SizedBox(height: 24),
        Text(
          'Batch Import Complete!',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade800),
        ),
        const SizedBox(height: 12),
        Text(
          'Successfully imported ${_allDataRows.length} ${_importType == ImportType.parties ? "Parties" : "Products"} into the SQLite local database.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        const Text(
          'Double-entry ledgers have been created dynamically, and changes are queued to sync with Google Drive.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
          child: const Text('Go to Dashboard'),
        ),
      ],
    );
  }

  Widget _buildStepNavigation(ThemeData theme) {
    if (_currentStep == 4) return const SizedBox.shrink(); // No nav buttons on success page

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _currentStep--;
                  _errorMessage = null;
                });
              },
              child: const Text('Back'),
            )
          else
            const SizedBox.shrink(),

          // Forward/Action button
          ElevatedButton(
            onPressed: _canProceed() ? _onProceedPressed : null,
            child: Text(_getProceedButtonText()),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (_currentStep == 1 && _selectedFile == null) return false;
    if (_currentStep == 2 && !_isMappingValid()) return false;
    if (_currentStep == 3 && _hasSheetErrors()) return false;
    return true;
  }

  String _getProceedButtonText() {
    switch (_currentStep) {
      case 0:
        return 'Next: Select File';
      case 1:
        return 'Next: Map Columns';
      case 2:
        return 'Next: Verify & Preview';
      case 3:
        return 'Start Batch Import';
      default:
        return 'Next';
    }
  }

  void _onProceedPressed() async {
    if (_currentStep == 0) {
      setState(() {
        _currentStep = 1;
      });
    } else if (_currentStep == 1) {
      setState(() {
        _currentStep = 2;
      });
    } else if (_currentStep == 2) {
      await _fetchExistingDbNames();
      setState(() {
        _currentStep = 3;
      });
    } else if (_currentStep == 3) {
      await _processImport();
    }
  }
}
