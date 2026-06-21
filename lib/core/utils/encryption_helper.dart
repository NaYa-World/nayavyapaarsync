import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionHelper {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyPrefix = 'backup_encryption_key';

  /// Retrieves or derives the 256-bit encryption key.
  /// Falls back to using Google email + default PIN '0000' if no active key exists.
  static Future<String> _getOrDeriveKey() async {
    String? key = await _secureStorage.read(key: _keyPrefix);
    if (key == null || key.isEmpty) {
      final email = await _secureStorage.read(key: 'google_user_email') ?? 'default@vyapaarsync.com';
      final pin = '0000';
      key = sha256.convert(utf8.encode('$pin:$email')).toString();
      await _secureStorage.write(key: _keyPrefix, value: key);
    }
    return key;
  }

  /// Sets the active encryption key derived from user PIN.
  static Future<void> saveEncryptionKeyForPin(String pin, String email) async {
    final key = sha256.convert(utf8.encode('$pin:$email')).toString();
    await _secureStorage.write(key: _keyPrefix, value: key);
  }

  /// Encrypts a source file to a destination file using AES-256-CBC.
  /// Prepends a random 16-byte IV to the encrypted payload.
  static Future<void> encryptFile(File source, File destination) async {
    final bytes = await source.readAsBytes();
    final encryptionKey = await _getOrDeriveKey();
    
    final keyBytes = sha256.convert(utf8.encode(encryptionKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromSecureRandom(16);
    
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);
    
    final outBytes = Uint8List(16 + encrypted.bytes.length);
    outBytes.setRange(0, 16, iv.bytes);
    outBytes.setRange(16, outBytes.length, encrypted.bytes);
    
    await destination.writeAsBytes(outBytes);
  }

  /// Decrypts a source file (with 16-byte prepended IV) to a destination file.
  static Future<void> decryptFile(File source, File destination) async {
    final bytes = await source.readAsBytes();
    if (bytes.length < 16) {
      throw Exception('Encrypted file too small');
    }
    
    final ivBytes = bytes.sublist(0, 16);
    final encryptedBytes = bytes.sublist(16);
    
    final encryptionKey = await _getOrDeriveKey();
    final keyBytes = sha256.convert(utf8.encode(encryptionKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List.fromList(ivBytes));
    
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final decryptedBytes = encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);
    
    await destination.writeAsBytes(decryptedBytes);
  }
}
