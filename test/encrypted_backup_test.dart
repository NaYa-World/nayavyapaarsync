import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:godown_management/core/utils/encryption_helper.dart';

void main() {
  final Map<String, String> mockSecureStorage = {};

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const MethodChannel channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'write') {
          final key = methodCall.arguments['key'] as String;
          final value = methodCall.arguments['value'] as String;
          mockSecureStorage[key] = value;
          return null;
        }
        if (methodCall.method == 'read') {
          final key = methodCall.arguments['key'] as String;
          return mockSecureStorage[key];
        }
        if (methodCall.method == 'delete') {
          final key = methodCall.arguments['key'] as String;
          mockSecureStorage.remove(key);
          return null;
        }
        return null;
      },
    );
  });

  group('Encrypted Backup Utility Tests', () {
    late Directory tempDir;
    late File sourceFile;
    late File encryptedFile;
    late File decryptedFile;
    const testContent = 'VyapaarSync Secure Transaction Database File Content Mock 12345';

    setUp(() async {
      mockSecureStorage.clear();
      tempDir = await Directory.systemTemp.createTemp('backup_test');
      sourceFile = File('${tempDir.path}/source.db');
      encryptedFile = File('${tempDir.path}/encrypted.db');
      decryptedFile = File('${tempDir.path}/decrypted.db');
      
      await sourceFile.writeAsString(testContent);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Encryption and Decryption matches original content', () async {
      const email = 'karthik@nayavyapaar.com';
      const pin = '4321';
      
      await EncryptionHelper.saveEncryptionKeyForPin(pin, email);

      // Perform encryption
      await EncryptionHelper.encryptFile(sourceFile, encryptedFile);
      expect(await encryptedFile.exists(), true);
      
      // The encrypted file should not match original string
      final encryptedContent = await encryptedFile.readAsString(encoding: latin1);
      expect(encryptedContent, isNot(equals(testContent)));

      // Perform decryption
      await EncryptionHelper.decryptFile(encryptedFile, decryptedFile);
      expect(await decryptedFile.exists(), true);
      
      // The decrypted file should match original content
      final decryptedContent = await decryptedFile.readAsString();
      expect(decryptedContent, equals(testContent));
    });

    test('Decryption fails with invalid key or corrupted data', () async {
      const email = 'karthik@nayavyapaar.com';
      const pin = '4321';
      await EncryptionHelper.saveEncryptionKeyForPin(pin, email);

      // Perform encryption
      await EncryptionHelper.encryptFile(sourceFile, encryptedFile);

      // Save a different key to mock key change / invalid PIN access
      await EncryptionHelper.saveEncryptionKeyForPin('0000', email);

      // Attempt decryption - should throw an error due to invalid key / padding error
      expect(
        () => EncryptionHelper.decryptFile(encryptedFile, decryptedFile),
        throwsA(anything),
      );
    });
  });
}
