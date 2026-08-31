import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static Uint8List applyXor(List<int> bytes) {
    Uint8List result = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i] ^ ((i % 7) + 13);
    }
    return result;
  }

  static Future<void> saveLocalDb(Map<String, dynamic> db) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.users_db.bin');
      String rawJson = jsonEncode(db);
      List<int> utf8Bytes = utf8.encode(rawJson);
      String base64Str = base64Encode(utf8Bytes);
      List<int> base64Bytes = utf8.encode(base64Str);
      Uint8List ciphered = applyXor(base64Bytes);
      await file.writeAsBytes(ciphered);
    } catch (e) {
      debugPrint("DB Save Error: $e");
    }
  }

  static Future<Map<String, dynamic>> loadLocalDb() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.users_db.bin');
      if (!await file.exists()) return {};
      Uint8List ciphered = await file.readAsBytes();
      Uint8List unciphered = applyXor(ciphered);
      String base64Str = utf8.decode(unciphered);
      List<int> utf8Bytes = base64Decode(base64Str);
      String rawJson = utf8.decode(utf8Bytes);
      return jsonDecode(rawJson);
    } catch (e) {
      debugPrint("DB Load Error: $e");
      return {};
    }
  }

  static Future<void> saveArchive(String sessionId, String title, List<Map<String, dynamic>> messages) async {
    try {
      if (messages.isEmpty) return;
      final dir = await getApplicationDocumentsDirectory();
      String cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      if (cleanTitle.length > 25) cleanTitle = cleanTitle.substring(0, 25);
      if (cleanTitle.isEmpty) cleanTitle = "Sesi_Chat";
      
      List<Map<String, dynamic>> savableMessages = messages.map((m) {
        var copy = Map<String, dynamic>.from(m);
        copy.remove('attached_image_bytes');
        return copy;
      }).toList();

      final file = File('${dir.path}/archive_${sessionId}_$cleanTitle.json');
      await file.writeAsString(jsonEncode(savableMessages));

      List<FileSystemEntity> files = dir.listSync();
      List<File> archives = files.where((f) => f.path.contains('archive_')).map((f) => File(f.path)).toList();
      if (archives.length >= 250) {
        archives.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        int deleteCount = archives.length - 240; 
        for (int i = 0; i < deleteCount; i++) {
          if (await archives[i].exists()) {
            await archives[i].delete();
          }
        }
      }
    } catch (e) {
      debugPrint("Archive Save Error: $e");
    }
  }

  static Future<List<Map<String, String>>> getArchiveList() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      List<FileSystemEntity> files = dir.listSync();
      List<Map<String, String>> archives = [];
      for (var f in files) {
        if (f.path.contains('archive_')) {
          String filename = f.path.split(Platform.pathSeparator).last;
          String rawName = filename.replaceAll('archive_', '').replaceAll('.json', '');
          List<String> parts = rawName.split('_');
          String title = parts.length > 2 ? parts.sublist(2).join(' ') : (parts.length > 1 ? parts[1] : rawName);
          archives.add({
            'file_id': filename.replaceAll('.json', ''),
            'title': title,
            'path': f.path
          });
        }
      }
      return archives;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> loadArchiveByFileId(String fileId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileId.json');
      if (await file.exists()) {
        String content = await file.readAsString();
        List<dynamic> raw = jsonDecode(content);
        return List<Map<String, dynamic>>.from(raw);
      }
    } catch (_) {}
    return [];
  }
}
