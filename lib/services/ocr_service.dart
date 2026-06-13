import 'dart:convert';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

class OcrLineItem {
  final String name;
  final String nameConfidence;
  final double qty;
  final String qtyConfidence;
  final String unit; // 'BAG' or 'BOX'
  final String unitConfidence;
  final double rate;
  final String rateConfidence;
  final double gstRate;
  final String gstRateConfidence;

  OcrLineItem({
    required this.name,
    required this.nameConfidence,
    required this.qty,
    required this.qtyConfidence,
    required this.unit,
    required this.unitConfidence,
    required this.rate,
    required this.rateConfidence,
    required this.gstRate,
    required this.gstRateConfidence,
  });
}

class OcrResult {
  final String? partyName;
  final String partyNameConfidence;
  final String? date;
  final String dateConfidence;
  final String? invoiceNo;
  final String invoiceNoConfidence;
  final List<OcrLineItem> lineItems;
  final double? subtotal;
  final String subtotalConfidence;
  final double? gstTotal;
  final String gstTotalConfidence;
  final double? grandTotal;
  final String grandTotalConfidence;
  final String rawResponse;

  OcrResult({
    this.partyName,
    required this.partyNameConfidence,
    this.date,
    required this.dateConfidence,
    this.invoiceNo,
    required this.invoiceNoConfidence,
    required this.lineItems,
    this.subtotal,
    required this.subtotalConfidence,
    this.gstTotal,
    required this.gstTotalConfidence,
    this.grandTotal,
    required this.grandTotalConfidence,
    required this.rawResponse,
  });
}

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  Future<OcrResult> scanInvoice(
    File imageFile, {
    List<String> knownParties = const [],
    List<String> knownItems = const [],
  }) async {
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final TextRecognizer textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    final String fullText = recognizedText.text;

    // Collect all lines
    final List<TextLine> allLines = [];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    // Sort by top coordinate
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Group into rows if they are vertically aligned (e.g. within 15 pixels)
    const double alignmentThreshold = 15.0;
    final List<List<TextLine>> groupedRows = [];
    for (final line in allLines) {
      bool placed = false;
      for (final row in groupedRows) {
        final double rowAverageTop = row.map((l) => l.boundingBox.top).reduce((a, b) => a + b) / row.length;
        if ((line.boundingBox.top - rowAverageTop).abs() < alignmentThreshold) {
          row.add(line);
          placed = true;
          break;
        }
      }
      if (!placed) {
        groupedRows.add([line]);
      }
    }

    // Sort each row horizontally (left to right)
    for (final row in groupedRows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }

    // Sort the rows vertically
    groupedRows.sort((a, b) {
      final double topA = a.map((l) => l.boundingBox.top).reduce((x, y) => x + y) / a.length;
      final double topB = b.map((l) => l.boundingBox.top).reduce((x, y) => x + y) / b.length;
      return topA.compareTo(topB);
    });

    // Extract Party Name
    String? partyName;
    String partyNameConfidence = 'low';
    for (final party in knownParties) {
      if (fullText.toLowerCase().contains(party.toLowerCase())) {
        partyName = party;
        partyNameConfidence = 'high';
        break;
      }
    }

    // Extract Date
    String? dateStr;
    String dateConfidence = 'low';
    final dateRegex = RegExp(r'\b(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})\b|\b(\d{4})[-./](\d{1,2})[-./](\d{1,2})\b');
    final dateMatch = dateRegex.firstMatch(fullText);
    if (dateMatch != null) {
      final matchedStr = dateMatch.group(0)!;
      try {
        DateTime? parsed;
        final formats = [
          'dd-MM-yyyy', 'd-M-yyyy', 'dd/MM/yyyy', 'd/M/yyyy', 'dd.MM.yyyy', 'd.M.yyyy',
          'yyyy-MM-dd', 'yyyy/MM/dd', 'dd-MMM-yyyy', 'd-MMM-yyyy'
        ];
        for (final fmt in formats) {
          try {
            parsed = DateFormat(fmt).parse(matchedStr);
            break;
          } catch (_) {}
        }
        if (parsed != null) {
          dateStr = DateFormat('yyyy-MM-dd').format(parsed);
          dateConfidence = 'high';
        }
      } catch (_) {
        dateStr = matchedStr;
      }
    }

    // Extract Invoice Number
    String? invoiceNo;
    String invoiceNoConfidence = 'low';
    final invRegex = RegExp(r'(?:inv(?:oice)?|bill|challan)\s*(?:no\.?|number)?\s*[:\-\s]\s*([A-Za-z0-9\-\/]+)', caseSensitive: false);
    final invMatch = invRegex.firstMatch(fullText);
    if (invMatch != null) {
      invoiceNo = invMatch.group(1);
      invoiceNoConfidence = 'high';
    } else {
      final fallbackRegex = RegExp(r'\b(?:inv|bill|invoice)\b.*\b([A-Za-z0-9\-\/]{3,})\b', caseSensitive: false);
      final fallbackMatch = fallbackRegex.firstMatch(fullText);
      if (fallbackMatch != null) {
        invoiceNo = fallbackMatch.group(1);
        invoiceNoConfidence = 'high';
      }
    }

    // Extract Line Items
    final List<OcrLineItem> lineItems = [];
    for (final row in groupedRows) {
      final String rowText = row.map((l) => l.text).join(' ');
      
      String? matchedItemName;
      for (final item in knownItems) {
        if (rowText.toLowerCase().contains(item.toLowerCase())) {
          matchedItemName = item;
          break;
        }
      }

      String itemName = '';
      String nameConfidence = 'low';

      if (matchedItemName != null) {
        itemName = matchedItemName;
        nameConfidence = 'high';
      } else {
        // Run blacklist check to skip header, footer, metadata, or tax total lines
        final lowercaseRow = rowText.toLowerCase();
        final blacklist = [
          'total', 'subtotal', 'cgst', 'sgst', 'igst', 'taxable', 'invoice', 
          'challan', 'bill', 'date', 'rupees', 'signature', 'receiver', 'driver', 
          'freight', 'charges', 'discount', 'round', 'balance', 'terms', 
          'conditions', 'bank', 'account', 'gstin', 'state', 'phone', 'mobile', 
          'address', 'email', 'website', 'gross', 'net', 'declaration', 
          'e. & o.e.', 'subject to', 'authorized', 'prepared', 'checked', 
          'payment', 'sl.no', 's.no', 'sr.no', 'particulars', 'description'
        ];
        
        bool isBlacklisted = false;
        for (final keyword in blacklist) {
          if (lowercaseRow.contains(keyword)) {
            isBlacklisted = true;
            break;
          }
        }
        
        if (isBlacklisted) continue;
        
        // Extract a candidate name from the text by removing numbers and common symbols/units
        String cleanName = rowText;
        cleanName = cleanName.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '');
        cleanName = cleanName.replaceAll(RegExp(r'[%\-:\+,\/\*]'), '');
        cleanName = cleanName.replaceAll(RegExp(r'\b(?:bags?|pkts?|pcs|boxes?|cases?|kg|liters?|ltrs?|gm|ml)\b', caseSensitive: false), '');
        cleanName = cleanName.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        if (cleanName.length < 3) continue;
        
        itemName = cleanName;
        nameConfidence = 'low';
      }

      final numbers = _parseNumbersFromRow(rowText);
      if (numbers.isEmpty) continue;

      double qty = 1.0;
      double rate = 0.0;
      double total = 0.0;
      double gstRate = 5.0; // default standard

      if (numbers.length >= 3) {
        double bestQty = 1.0;
        double bestRate = 0.0;
        double bestTotal = 0.0;
        double bestError = double.infinity;

        for (int i = 0; i < numbers.length; i++) {
          for (int j = 0; j < numbers.length; j++) {
            if (i == j) continue;
            for (int k = 0; k < numbers.length; k++) {
              if (k == i || k == j) continue;
              final q = numbers[i];
              final r = numbers[j];
              final t = numbers[k];

              if (q <= 0 || r <= 0 || t <= 0) continue;
              if (q == 2024 || q == 2025 || q == 2026 || r == 2024 || r == 2025 || r == 2026) continue;

              final error = (q * r - t).abs();
              if (error < bestError) {
                bestError = error;
                bestQty = q;
                bestRate = r;
                bestTotal = t;
              }
            }
          }
        }

        if (bestError < 0.2 * bestTotal) {
          qty = bestQty;
          rate = bestRate;
          total = bestTotal;
        } else {
          final sorted = List<double>.from(numbers)..sort();
          total = sorted.last;
          qty = sorted.first;
          rate = sorted[sorted.length - 2];
        }
      } else if (numbers.length == 2) {
        final sorted = List<double>.from(numbers)..sort();
        qty = sorted.first;
        rate = sorted.last;
        total = qty * rate;
      } else if (numbers.length == 1) {
        rate = numbers.first;
        qty = 1.0;
        total = rate;
      }

      final gstRegex = RegExp(r'\b(5|12|18|28)\s*%', caseSensitive: false);
      final gstMatch = gstRegex.firstMatch(rowText);
      if (gstMatch != null) {
        gstRate = double.tryParse(gstMatch.group(1) ?? '5.0') ?? 5.0;
      } else {
        for (final n in numbers) {
          if (n == 5.0 || n == 12.0 || n == 18.0 || n == 28.0) {
            gstRate = n;
            break;
          }
        }
      }

      String unit = 'BAG';
      if (rowText.toLowerCase().contains('box') || rowText.toLowerCase().contains('case') || rowText.toLowerCase().contains('pcs')) {
        unit = 'BOX';
      }

      lineItems.add(OcrLineItem(
        name: itemName,
        nameConfidence: nameConfidence,
        qty: qty,
        qtyConfidence: nameConfidence == 'high' ? 'high' : 'low',
        unit: unit,
        unitConfidence: nameConfidence == 'high' ? 'high' : 'low',
        rate: rate,
        rateConfidence: nameConfidence == 'high' ? 'high' : 'low',
        gstRate: gstRate,
        gstRateConfidence: nameConfidence == 'high' ? 'high' : 'low',
      ));
    }

    // Extract Totals
    double? grandTotal;
    final numbers = _parseNumbersFromRow(fullText);
    if (numbers.isNotEmpty) {
      final sortedNumbers = List<double>.from(numbers)..sort();
      final potentialTotals = sortedNumbers.where((n) => n != 2024 && n != 2025 && n != 2026 && n > 100).toList();
      if (potentialTotals.isNotEmpty) {
        grandTotal = potentialTotals.last;
      }
    }

    await textRecognizer.close();

    return OcrResult(
      partyName: partyName,
      partyNameConfidence: partyNameConfidence,
      date: dateStr,
      dateConfidence: dateConfidence,
      invoiceNo: invoiceNo,
      invoiceNoConfidence: invoiceNoConfidence,
      lineItems: lineItems,
      subtotal: null,
      subtotalConfidence: 'low',
      gstTotal: null,
      gstTotalConfidence: 'low',
      grandTotal: grandTotal,
      grandTotalConfidence: grandTotal != null ? 'high' : 'low',
      rawResponse: fullText,
    );
  }

  List<double> _parseNumbersFromRow(String rowText) {
    final cleanedText = rowText.replaceAll(RegExp(r'(?<=\d),(?=\d)'), '');
    final matches = RegExp(r'\b\d+(?:\.\d+)?\b').allMatches(cleanedText);
    final List<double> list = [];
    for (final m in matches) {
      final val = double.tryParse(m.group(0) ?? '');
      if (val != null) {
        list.add(val);
      }
    }
    return list;
  }

  // Deprecated key methods
  Future<void> saveApiKey(String apiKey) async {}
  Future<String?> getApiKey() async => null;
  Future<void> deleteApiKey() async {}
}
