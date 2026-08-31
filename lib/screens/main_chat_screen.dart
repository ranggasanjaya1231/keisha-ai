import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_database/firebase_database.dart';

// Import file modular (Menggunakan '../' karena file ini berada di dalam folder lib/screens/)
import '../models/role_badge.dart';
import '../services/ai_service.dart';
import '../services/database_helper.dart';

// ==========================================
// LAYAR MAIN CHAT & DISKUSI KELAS
// ==========================================
class MainChatScreen extends StatefulWidget {
  final String? initialUser;
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;

  const MainChatScreen({
    super.key, 
    this.initialUser, 
    required this.isDarkMode, 
    required this.onToggleDarkMode,
  });

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _classChatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _classChatScrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _taskDescController = TextEditingController();
  final TextEditingController _taskKeysController = TextEditingController();
  final TextEditingController _taskCountController = TextEditingController(text: "15");
  
  String _taskSelectedTargetClass = "Semua Kelas";
  String _taskSelectedType = "Pilihan Ganda"; 

  final List<Map<String, dynamic>> _messages = [];
  List<Map<String, String>> _archives = [];

  String username = "Mas Kahfi";
  String displayName = "Mas Kahfi";
  String? studentClass; 
  String? profileImageBase64;
  bool isTeacher = false;
  bool isFemale = false;
  bool isLoading = false;
  bool _isGreetingLoading = false;
  bool isTypingStreaming = false;
  
  String? _currentSessionId;
  Timer? _typewriterTimer;
  String? _currentFullStreamText;
  int _currentStreamIndex = 0;
  String statusText = "Online";

  String activeClassChatTab = "Kelas 10";
  bool isGroupMuted = false;
  
  StreamSubscription<DatabaseEvent>? _classChatSubscription;
  StreamSubscription<DatabaseEvent>? _pinnedMessageSubscription;
  
  List<Map<String, dynamic>> _currentClassMessages = [];
  Map<String, dynamic>? _replyingToMessage;
  String? _pinnedMessage;

  Map<String, dynamic> _cachedUsersMap = {};
  DateTime? _lastUserFetchTime;

  final String _firebaseUrl = "https://keisha-informatics-app-default-rtdb.asia-southeast1.firebasedatabase.app";

  final List<Map<String, String>> educationalStickers = [
    {"name": "Izin Tanya", "url": "https://img.icons8.com/color/96/000000/ask-question.png"},
    {"name": "Paham!", "url": "https://img.icons8.com/color/96/000000/idea.png"},
    {"name": "Sudah Dicek", "url": "https://img.icons8.com/color/96/000000/checked-checkbox.png"},
    {"name": "Mantap", "url": "https://img.icons8.com/color/96/000000/ok.png"},
    {"name": "Bintang Kelas", "url": "https://img.icons8.com/color/96/000000/star.png"},
    {"name": "Sedang Koding", "url": "https://img.icons8.com/color/96/000000/code.png"},
  ];

  String get systemInstruction {
    if (isTeacher) {
      return """
Kamu adalah Keisha, AI Senior Software Engineer, Master Game Developer, & Asisten AI Pribadi dari Kepala Sekolah / Guru Informatika Mas Kahfi.

ATURAN KHUSUS UNTUK GURU (MAS KAHFI):
1. Pengguna saat ini adalah GURU KAMU. Berikan jawaban langsung pada inti perintah dengan bahasa yang sopan, menghormati, manis, dan berwibawa.
2. DILARANG MENGGUNAKAN TABEL MARKDOWN / SIMBOL GARIS (|) ATAU DASH (---). Format daftar soal secara polos menggunakan penomoran standar ke bawah (1, 2, 3...).
3. PEMBUATAN SOAL PILIHAN GANDA (PG):
   - Buat soal beserta opsi pilihan A, B, C, D secara mendatar atau berurutan rapi.
   - Wajib sertakan KUNCI JAWABAN di baris paling akhir pesan dengan format ringkas yang mudah dibaca sistem (Contoh: KUNCI JAWABAN: 1.A, 2.B, 3.C, 4.D).
   - Berhenti menulis setelah jumlah soal yang diminta terpenuhi.
4. JIKA GURU MEMINTA KODE PROGRAM (HTML/JS/Dart): Berikan kode utuh yang siap dipakai tanpa terpotong. Gunakan markdown code blocks (```) untuk kode.
""";
    } else {
      return """
Kamu adalah Keisha, AI Senior Software Engineer, Master Game Developer, & Asisten AI Pribadi dari Kepala Sekolah / Guru Informatika Mas Kahfi.

ATURAN KETAT UNTUK SISWA:
1. Jawab langsung pada inti pertanyaan dengan gaya bahasa edukatif, ramah, dan membimbing.
2. DILARANG MENGGUNAKAN SIMBOL TABEL MARKDOWN (|).
3. KELOMPOK RAHASIA & KEAMANAN SOAL:
   - DILARANG KERAS membocorkan kunci jawaban (A, B, C, D) langsung atau memberikan jawaban instan dari soal/tugas sekolah.
   - Jika siswa bertanya jawaban dari suatu soal, jangan beri tahu pilihan mana yang benar. Berikan penjelasan konsep dasar, rumus, atau petunjuk langkah-langkah berpikir agar siswa menemukan jawabannya sendiri.
4. Gunakan markdown code blocks (```) jika memberikan contoh kode program.
""";
    }
  }

  @override
  void initState() {
    super.initState();
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _loadUserSession();
    
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
      }
    });
  }
  
  void _listenToClassChat() async {
    String classKey = activeClassChatTab.replaceAll(' ', '_').toLowerCase();
    await _fetchUsersMapSmartCache();

    _pinnedMessageSubscription?.cancel();
    _pinnedMessageSubscription = FirebaseDatabase.instance
        .ref("class_chats/${classKey}_pinned")
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        Map<dynamic, dynamic> pinData = event.snapshot.value as Map<dynamic, dynamic>;
        if (mounted) setState(() => _pinnedMessage = pinData['message']);
      } else {
        if (mounted) setState(() => _pinnedMessage = null);
      }
    });

    _classChatSubscription?.cancel();
    _classChatSubscription = FirebaseDatabase.instance
        .ref("class_chats/$classKey")
        .orderByKey()
        .limitToLast(50)
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        Map<dynamic, dynamic> raw = event.snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> newMsgs = [];
        
        raw.forEach((key, val) {
          String sender = val["sender"] ?? "Siswa";
          Color computedColor = const Color(0xFF1E293B);
          String computedBadge = "";
          String roleName = val["role"] ?? "siswa";
          
          if (_cachedUsersMap.containsKey(sender)) {
             var uData = _cachedUsersMap[sender];
             List<String> assigned = [];
             if (uData["roles"] != null) {
                 if (uData["roles"] is List) assigned = List<String>.from(uData["roles"]);
                 else if (uData["roles"] is Map) assigned = (uData["roles"] as Map).values.map((e)=>e.toString()).toList();
             }
             int uXp = (uData["xp"] is int) ? uData["xp"] : (int.tryParse(uData["xp"]?.toString() ?? "0") ?? 0);
             bool isUserGuru = (uData["is_teacher"] == true);
             
             List<RoleBadge> badges = [];
             if (isUserGuru) {
                 badges.add(allDefinedRoles.firstWhere((r) => r.id == "guru"));
             } else {
                 for (var rId in assigned) {
                     var matched = allDefinedRoles.where((r) => r.id == rId);
                     if (matched.isNotEmpty) badges.add(matched.first);
                 }
                 if (uXp >= 2500) badges.add(allDefinedRoles.firstWhere((r) => r.id == "legend_chat"));
                 else if (uXp >= 1000) badges.add(allDefinedRoles.firstWhere((r) => r.id == "pro_chat"));
                 else if (uXp >= 250) badges.add(allDefinedRoles.firstWhere((r) => r.id == "active_chat"));
                 
                 if (badges.isEmpty) badges.add(allDefinedRoles.firstWhere((r) => r.id == "default"));
             }
             badges.sort((a, b) => b.priority.compareTo(a.priority));
             
             computedColor = badges.first.color;
             computedBadge = badges.first.badge;
             roleName = badges.first.name;
          } else if (val["role"] == "guru" || val["role"] == "Guru Informatika") {
             computedColor = const Color(0xFFD35400);
             computedBadge = "📌";
             roleName = "Guru Informatika";
          }

          newMsgs.add({
            "id": key.toString(),
            "sender": sender,
            "display_name": val["display_name"] ?? sender,
            "message": val["message"] ?? "",
            "role": roleName, 
            "timestamp": val["timestamp"] ?? "",
            "reactions": val["reactions"] ?? {},
            "reply_to": val["reply_to"], 
            "computed_color": computedColor,
            "computed_badge": computedBadge,
          });
        });
        
        if (newMsgs.isNotEmpty) {
          newMsgs.sort((a, b) => a["timestamp"].compareTo(b["timestamp"]));
          if (mounted) {
            setState(() {
              _currentClassMessages = newMsgs;
            });
            _scrollToBottomClassChat(force: true);
          }
        }
      } else {
        if (mounted) setState(() => _currentClassMessages = []);
      }
    });
  }

  Future<void> _fetchUsersMapSmartCache() async {
    if (_lastUserFetchTime != null && DateTime.now().difference(_lastUserFetchTime!).inMinutes < 5 && _cachedUsersMap.isNotEmpty) {
      return; 
    }
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users.json"));
      if (res.statusCode == 200 && res.body != "null") {
        _cachedUsersMap = jsonDecode(res.body);
        _lastUserFetchTime = DateTime.now();
      }
    } catch (_) {}
  }

  Future<void> _loadUserSession() async {
    if (widget.initialUser != null) {
      username = widget.initialUser!;
    }
    
    Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();
    if (db.containsKey(username)) {
      final userData = db[username];
      if (mounted) {
        setState(() {
          displayName = userData["display_name"] ?? username;
          studentClass = userData["class"] ?? "Kelas 10";
          isFemale = userData["is_female"] ?? false;
          isTeacher = userData["is_teacher"] ?? false;
          profileImageBase64 = userData["profile_pic_b64"];
          if (!isTeacher && studentClass != null) {
            activeClassChatTab = studentClass!;
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          displayName = username;
          studentClass = "Kelas 10";
          isTeacher = false;
          if (!isTeacher) activeClassChatTab = studentClass!;
        });
      }
    }

    _fetchUserProfileFromCloud();
    _loadArchives();
    if (_messages.isEmpty && !_isGreetingLoading) {
      _fetchDynamicGreeting();
    }
    _listenToClassChat();
  }

  Future<void> _fetchUserProfileFromCloud() async {
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users/$username.json"));
      if (res.statusCode == 200 && res.body != "null") {
        Map<String, dynamic> data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            if (data["profile_pic_b64"] != null) profileImageBase64 = data["profile_pic_b64"];
            if (data["display_name"] != null) displayName = data["display_name"];
          });
        }
      }
    } catch (_) {}
  }

  void _triggerAutoSave() async {
    if (_messages.length > 1 && _currentSessionId != null) {
      String firstMsg = (_messages.firstWhere((m) => m['sender'] == 'user', orElse: () => {'text': 'Obrolan'})['text'] as String);
      await DatabaseHelper.saveArchive(_currentSessionId!, firstMsg, _messages);
      await _loadArchives();
    }
  }

  Future<void> _checkAktivisJumatBadge() async {
    if (isTeacher) return;
    DateTime now = DateTime.now();
    if (now.weekday == 5) {
      try {
        final res = await http.get(Uri.parse("$_firebaseUrl/users/$username/roles.json"));
        List<String> currentRoles = [];
        if (res.statusCode == 200 && res.body != "null") {
          dynamic raw = jsonDecode(res.body);
          if (raw is List) currentRoles = List<String>.from(raw);
          else if (raw is Map) currentRoles = raw.values.map((e) => e.toString()).toList();
        }
        if (!currentRoles.contains("aktivis_jumat")) {
          currentRoles.add("aktivis_jumat");
          await http.put(
            Uri.parse("$_firebaseUrl/users/$username/roles.json"),
            body: jsonEncode(currentRoles),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _incrementXP(int amount, {String? targetUsername}) async {
    String target = targetUsername ?? username;
    if (isTeacher && target == username) return;
    
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users/$target.json"));
      if (res.statusCode == 200 && res.body != "null") {
        Map<String, dynamic> uData = jsonDecode(res.body);
        if (uData["is_teacher"] == true) return;

        int oldXp = (uData["xp"] is int) ? uData["xp"] : (int.tryParse(uData["xp"]?.toString() ?? "0") ?? 0);
        int newXp = oldXp + amount;
        String targetDispName = uData["display_name"] ?? target;
        
        await http.patch(
          Uri.parse("$_firebaseUrl/users/$target.json"),
          body: jsonEncode({"xp": newXp}),
        );

        int oldLevel = (oldXp / 100).floor() + 1;
        int newLevel = (newXp / 100).floor() + 1;
        
        String roleUnlockMsg = "";
        if (oldXp < 250 && newXp >= 250) roleUnlockMsg = " dan berhasil membuka Lencana 💬 **Siswa Aktif**";
        else if (oldXp < 1000 && newXp >= 1000) roleUnlockMsg = " dan berhasil membuka Lencana Prestisius 🔥 **Siswa Paling Aktif**";
        else if (oldXp < 2500 && newXp >= 2500) roleUnlockMsg = " dan berhasil mencapai Tahta Tertinggi 👑 **Legenda Obrolan**";
        
        if (newLevel > oldLevel || roleUnlockMsg.isNotEmpty) {
          if (target == username) {
            if (mounted) {
              setState(() {
                _messages.add({
                  'sender': 'ai',
                  'text': '🎉 Selamat @$displayName! Kamu resmi naik ke **Level $newLevel**$roleUnlockMsg berkat pencapaian XP-mu. Teruslah aktif belajar!'
                });
              });
              _scrollToBottom();
              _triggerAutoSave();
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("🎉 @$targetDispName telah resmi naik ke Level $newLevel$roleUnlockMsg!"),
                  backgroundColor: const Color(0xFF616BF2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    _classChatSubscription?.cancel();
    _pinnedMessageSubscription?.cancel();
    _typewriterTimer?.cancel();
    _classChatInputController.dispose();
    _inputController.dispose();
    _taskTitleController.dispose();
    _taskDescController.dispose();
    _taskKeysController.dispose();
    _taskCountController.dispose();
    _scrollController.dispose();
    _classChatScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      setState(() {
        username = args["username"] ?? username;
        displayName = args["display_name"] ?? displayName;
        isFemale = args["is_female"] ?? false;
        studentClass = args["class"] ?? studentClass;
        isTeacher = args["is_teacher"] ?? false;
        if (!isTeacher && studentClass != null) activeClassChatTab = studentClass!;
      });
    }
  }

  Future<void> _loadArchives() async {
    List<Map<String, String>> list = await DatabaseHelper.getArchiveList();
    if (mounted) setState(() => _archives = list);
  }

  String _cleanUtf8Text(String text) {
    return text
        .replaceAll('**', '')
        .replaceAll('###', '')
        .replaceAll('##', '')
        .replaceAll(RegExp(r'â[\x80-\xFF]*'), '')
        .replaceAll('â¯+â¯', '+')
        .replaceAll('â¯-â¯', '-')
        .replaceAll('â¯=â¯', '=')
        .replaceAll('â¯', '')
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✅ $label berhasil disalin!"),
        backgroundColor: const Color(0xFF616BF2),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _downloadImageToGallery(String url) async {
    try {
      await Gal.putImage(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Gambar berhasil disimpan ke Galeri HP!"), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal menyimpan gambar: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showImageFullscreen(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.black54,
                  child: const Text("Gagal memuat gambar", style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _downloadImageToGallery(url);
              },
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text("Simpan ke Galeri HP", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF616BF2),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
    if (image != null) {
      List<int> bytes = await image.readAsBytes();
      String base64Img = base64Encode(bytes);

      Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();
      if (db.containsKey(username)) {
        db[username]["profile_pic_b64"] = base64Img;
        await DatabaseHelper.saveLocalDb(db);
      }

      try {
        await http.patch(
          Uri.parse("$_firebaseUrl/users/$username.json"),
          body: jsonEncode({"profile_pic_b64": base64Img}),
        );
      } catch (_) {}

      if (mounted) {
        setState(() => profileImageBase64 = base64Img);
        _lastUserFetchTime = null; 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto profil publik berhasil diperbarui!"), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showUserProfileShowcase(String userKey, String dispName, String userRole) async {
    String? fetchedPicBase64;
    List<String> assignedRoles = [];
    int currentXp = 0;
    
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users/$userKey.json"));
      if (res.statusCode == 200 && res.body != "null") {
        Map<String, dynamic> uData = jsonDecode(res.body);
        
        if (uData["roles"] != null) {
          if (uData["roles"] is List) {
            assignedRoles = List<String>.from(uData["roles"]);
          } else if (uData["roles"] is Map) {
            assignedRoles = (uData["roles"] as Map).values.map((e) => e.toString()).toList();
          }
        }
        if (uData["profile_pic_b64"] != null) {
          fetchedPicBase64 = uData["profile_pic_b64"];
        }
        if (uData["xp"] != null) {
          currentXp = (uData["xp"] is int) ? uData["xp"] : (int.tryParse(uData["xp"].toString()) ?? 0);
        }
      }
    } catch (_) {}

    int level = (currentXp / 100).floor() + 1;

    List<RoleBadge> badges = [];
    if (userRole == "guru") {
      badges.add(allDefinedRoles.firstWhere((r) => r.id == "guru"));
    } else {
      for (var rId in assignedRoles) {
        var matched = allDefinedRoles.where((r) => r.id == rId);
        if (matched.isNotEmpty) badges.add(matched.first);
      }
      
      if (currentXp >= 2500) badges.add(allDefinedRoles.firstWhere((r) => r.id == "legend_chat"));
      else if (currentXp >= 1000) badges.add(allDefinedRoles.firstWhere((r) => r.id == "pro_chat"));
      else if (currentXp >= 250) badges.add(allDefinedRoles.firstWhere((r) => r.id == "active_chat"));
      
      if (badges.isEmpty) badges.add(allDefinedRoles.firstWhere((r) => r.id == "default"));
    }

    badges.sort((a, b) => b.priority.compareTo(a.priority));

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF616BF2),
              backgroundImage: fetchedPicBase64 != null ? MemoryImage(base64Decode(fetchedPicBase64)) : null,
              child: fetchedPicBase64 == null 
                  ? Text(dispName.isNotEmpty ? dispName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(height: 12),
            Text(dispName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text("@$userKey", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Lencana & Pencapaian:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: badges.map((b) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: b.color.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: b.color, width: 1)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(b.badge, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(b.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: b.color)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text("$currentXp", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF616BF2))),
                      const Text("Total XP", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  Column(
                    children: [
                      Text("Lvl $level", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00D2FF))),
                      const Text("Level", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            if (userKey == username) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF616BF2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showEditProfileModal();
                },
                icon: const Icon(Icons.edit, color: Colors.white, size: 16),
                label: const Text("Edit Nama & Foto", style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _showEditProfileModal() {
    final nameCtrl = TextEditingController(text: displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Profil Saya"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nama Tampilan (Display Name)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await _changeProfilePicture();
                if (mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.photo_camera),
              label: const Text("Ganti Foto Profil (Publik)"),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();
                if (db.containsKey(username)) {
                  db[username]["display_name"] = nameCtrl.text.trim();
                  await DatabaseHelper.saveLocalDb(db);
                }
                try {
                  await http.patch(
                    Uri.parse("$_firebaseUrl/users/$username.json"),
                    body: jsonEncode({"display_name": nameCtrl.text.trim()}),
                  );
                } catch (_) {}
                if (mounted) {
                  setState(() => displayName = nameCtrl.text.trim());
                  _lastUserFetchTime = null; 
                  Navigator.pop(ctx);
                }
              }
            },
            child: const Text("Simpan"),
          )
        ],
      ),
    );
  }

  void _showRankGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.military_tech, color: Color(0xFF616BF2)),
            SizedBox(width: 8),
            Text("Panduan Rank & Role Kelas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Sistem Apresiasi & Gamifikasi Keisha AI:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                _buildRankGuideItem("⭐ Siswa Teladan", "Role Spesial Guru - Siswa paling tertib & sopan.", const Color(0xFFB7950B)),
                _buildRankGuideItem("💻 Master Koding", "Role Spesial Guru - Logika pemrograman terbaik.", const Color(0xFF7B1FA2)),
                _buildRankGuideItem("👑 Ketua Kelas / Moderator", "Role Spesial Guru - Pemimpin & pengatur kelas.", const Color(0xFF2563EB)),
                _buildRankGuideItem("🛡️ Siswa Mentor", "Role Spesial Guru - Rajin membantu teman belajar.", const Color(0xFF059669)),
                _buildRankGuideItem("🎨 UI/UX Designer", "Role Spesial Guru - Ahli estetika & desain visual.", const Color(0xFFDB2777)),
                _buildRankGuideItem("🐛 Bug Hunter", "Role Spesial Guru - Teliti menemukan kesalahan koding.", const Color(0xFFDC2626)),
                _buildRankGuideItem("🚀 Fast Learner", "Role Spesial Guru - Paling cepat paham materi baru.", const Color(0xFF0284C7)),
                _buildRankGuideItem("📢 Top Presenter", "Role Spesial Guru - Komunikatif saat presentasi.", const Color(0xFFD97706)),
                _buildRankGuideItem("🌙 Lencana Misterius (???)", "Syarat: ??? (Temukan cara rahasianya sendiri!)", const Color(0xFF8E44AD)),
                _buildRankGuideItem("👑 Legenda Obrolan", "Auto-Role Aktivitas - Tercapai setelah 2.500 XP.", const Color(0xFF7C3AED)),
                _buildRankGuideItem("🔥 Siswa Paling Aktif", "Auto-Role Aktivitas - Tercapai setelah 1.000 XP.", const Color(0xFFEA580C)),
                _buildRankGuideItem("💬 Siswa Aktif", "Auto-Role Aktivitas - Tercapai setelah 250 XP.", const Color(0xFF0D9488)),
                const Divider(),
                const Text("💡 Info Push Rank (XP):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                const Text("• Ngobrol / Bertanya: +5 XP\n• Jawaban Membantu Teman (Bonus Guru): +25 XP\n• Tiap 100 XP = Naik 1 Level!", style: TextStyle(fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Paham!")),
        ],
      ),
    );
  }

  Widget _buildRankGuideItem(String title, String desc, Color col) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: col, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: col, fontSize: 13)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _showTopGlobalLeaderboard() async {
    Map<String, dynamic> freshUsersMap = {};
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users.json"));
      if (res.statusCode == 200 && res.body != "null") {
        freshUsersMap = jsonDecode(res.body);
        _cachedUsersMap = freshUsersMap; 
        _lastUserFetchTime = DateTime.now();
      }
    } catch (e) {
      debugPrint("Error Top Global Fetch: $e");
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Color(0xFFB7950B)),
            SizedBox(width: 8),
            Text("🏆 Top Global Kelas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: Builder(
            builder: (context) {
              if (freshUsersMap.isEmpty) {
                return const Center(child: Text("Belum ada data siswa terdaftar."));
              }
              
              List<Map<String, dynamic>> userList = [];
              freshUsersMap.forEach((k, v) {
                if (v is Map) {
                  String actualUsername = v["username"] ?? k;
                  bool isTeacherAccount = (v["is_teacher"] == true);
                  
                  if (!isTeacherAccount) {
                    List<String> assigned = [];
                    if (v["roles"] != null) {
                      if (v["roles"] is List) assigned = List<String>.from(v["roles"]);
                      else if (v["roles"] is Map) assigned = (v["roles"] as Map).values.map((e)=>e.toString()).toList();
                    }
                    
                    int uXp = 0;
                    if (v["xp"] != null) {
                      if (v["xp"] is int) uXp = v["xp"];
                      else if (v["xp"] is String) uXp = int.tryParse(v["xp"].toString()) ?? 0;
                      else if (v["xp"] is double) uXp = (v["xp"] as double).toInt();
                    }
                    
                    List<RoleBadge> badges = [];
                    for (var rId in assigned) {
                      var matched = allDefinedRoles.where((r) => r.id == rId);
                      if (matched.isNotEmpty) badges.add(matched.first);
                    }
                    if (uXp >= 2500) badges.add(allDefinedRoles.firstWhere((r) => r.id == "legend_chat"));
                    else if (uXp >= 1000) badges.add(allDefinedRoles.firstWhere((r) => r.id == "pro_chat"));
                    else if (uXp >= 250) badges.add(allDefinedRoles.firstWhere((r) => r.id == "active_chat"));
                    
                    if (badges.isEmpty) badges.add(allDefinedRoles.firstWhere((r) => r.id == "default"));
                    badges.sort((a, b) => b.priority.compareTo(a.priority));

                    userList.add({
                      "username": actualUsername,
                      "display_name": v["display_name"] ?? actualUsername,
                      "class": v["class"] ?? "Kelas 10",
                      "xp": uXp,
                      "level": (uXp / 100).floor() + 1,
                      "top_badge": badges.first.badge,
                      "top_role_name": badges.first.name,
                      "badge_color": badges.first.color,
                      "profile_pic_b64": v["profile_pic_b64"],
                    });
                  }
                }
              });

              userList.sort((a, b) => (b["xp"] as int).compareTo(a["xp"] as int));

              if (userList.isEmpty) {
                return const Center(child: Text("Belum ada data siswa terdaftar."));
              }

              return ListView.builder(
                itemCount: userList.length,
                itemBuilder: (context, idx) {
                  var user = userList[idx];
                  int rank = idx + 1;
                  Color rankColor = rank == 1 ? const Color(0xFFB7950B) : (rank == 2 ? const Color(0xFF7F8C8D) : (rank == 3 ? const Color(0xFFD35400) : Colors.grey));
                  
                  String? picB64 = user["profile_pic_b64"];
                  String dName = user["display_name"];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () {
                        _showUserProfileShowcase(user["username"], dName, "siswa");
                      },
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            alignment: Alignment.center,
                            child: Text("#$rank", style: TextStyle(fontWeight: FontWeight.bold, color: rankColor, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF616BF2),
                            backgroundImage: picB64 != null ? MemoryImage(base64Decode(picB64)) : null,
                            child: picB64 == null ? Text(dName.isNotEmpty ? dName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 12)) : null,
                          ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(dName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          Text("${user['top_badge']} ${user['top_role_name']}", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: user['badge_color'])),
                        ],
                      ),
                      subtitle: Text("${user['class']} • Lvl ${user['level']}", style: const TextStyle(fontSize: 11)),
                      trailing: Text("${user['xp']} XP", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF616BF2), fontSize: 12)),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup"))],
      ),
    );
  }

  void _showStickerPicker({bool isClassForum = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Stiker Edukatif Resmi Sekolah", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text("Kirim apresiasi atau reaksi sopan ke dalam obrolan", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: educationalStickers.length,
                itemBuilder: (context, idx) {
                  final st = educationalStickers[idx];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      String stickerUrl = st["url"]!;
                      if (isClassForum) {
                        _sendClassMessagePayload("[STIKER] $stickerUrl", activeClassChatTab);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.network(
                            st["url"]!,
                            height: 48,
                            width: 48,
                            errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions, color: Colors.white, size: 40),
                          ),
                          const SizedBox(height: 4),
                          Text(st["name"]!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendClassImageFromGallery() async {
    String currentTabLocked = activeClassChatTab;
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mengunggah & mengoptimasi gambar...")));
      
      try {
        String? imageUrl;
        String? imgbbKey = dotenv.env['IMGBB_API_KEY'];
        
        if (imgbbKey != null && imgbbKey.isNotEmpty) {
          var request = http.MultipartRequest('POST', Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbKey'));
          request.files.add(await http.MultipartFile.fromPath('image', image.path));
          var res = await request.send();
          if (res.statusCode == 200) {
             var resData = await res.stream.bytesToString();
             imageUrl = jsonDecode(resData)['data']['url'];
          }
        }
        
        if (imageUrl != null) {
          _sendClassMessagePayload("[IMAGE_URL] $imageUrl", currentTabLocked);
        } else {
          Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
            image.path,
            minWidth: 400,
            minHeight: 400,
            quality: 45,
          );
          
          if (compressedBytes != null) {
            String b64 = base64Encode(compressedBytes);
            _sendClassMessagePayload("[IMAGE_B64] $b64", currentTabLocked);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal mengirim gambar.")));
        }
      }
    }
  }

  Future<void> _sendClassMessagePayload(String payloadContent, String targetClassTab) async {
    String classKey = targetClassTab.replaceAll(' ', '_').toLowerCase();
    try {
      Map<String, dynamic> payload = {
        "sender": username,
        "display_name": displayName,
        "message": payloadContent,
        "role": isTeacher ? "guru" : (isFemale ? "siswi" : "siswa"),
        "timestamp": DateTime.now().toString()
      };

      if (_replyingToMessage != null) {
        payload["reply_to"] = {
          "id": _replyingToMessage!["id"],
          "sender_name": _replyingToMessage!["display_name"],
          "message": _replyingToMessage!["message"],
        };
      }

      await FirebaseDatabase.instance.ref("class_chats/$classKey").push().set(payload);

      if (mounted) setState(() => _replyingToMessage = null);

      _incrementXP(5);
      await _checkAktivisJumatBadge();
    } catch (_) {}
  }

  Future<void> _sendClassChatMessage() async {
    String text = _classChatInputController.text.trim();
    if (text.isEmpty) return;

    String currentTabLocked = activeClassChatTab;
    _classChatInputController.clear();
    _sendClassMessagePayload(text, currentTabLocked);
  }

  // ==========================================
  // SCROLL PINTAR & STANDAR
  // ==========================================
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  void _scrollToBottomClassChat({bool force = false}) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_classChatScrollController.hasClients) {
        double maxScroll = _classChatScrollController.position.maxScrollExtent;
        double currentScroll = _classChatScrollController.position.pixels;

        if (force || (maxScroll - currentScroll) < 150) {
          _classChatScrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _fetchDynamicGreeting() async {
    if (_isGreetingLoading) return;
    _isGreetingLoading = true;

    String studentTitle = isFemale ? "Siswi" : "Siswa";
    String currentClassStr = studentClass ?? "Kelas 10";
    String greetingPrompt = isTeacher
        ? "Buatlah satu kalimat sanjungan puitis manis dan berwibawa untuk Kepala Sekolah sekaligus Guru Informatika tercinta. JAWAB LANGSUNG TANPA BASA-BASI EXTRA."
        : "Buatlah kalimat perkenalan dan sambutan ramah edukatif untuk $studentTitle $currentClassStr bernama '$displayName'. Perkenalkan dirimu sebagai Keisha, asisten AI pribadi dari Guru Informatika kita. JAWAB LANGSUNG TANPA BASA-BASI EXTRA.";

    try {
      List<Map<String, String>> initialMsg = [
        {"role": "system", "content": systemInstruction},
        {"role": "user", "content": greetingPrompt}
      ];

      final aiReplyRaw = await AIService.callMercuryApi(initialMsg);
      if (aiReplyRaw.isNotEmpty) {
          String reply = _cleanUtf8Text(aiReplyRaw.trim());
          if (mounted) setState(() => _messages.add({'sender': 'ai', 'text': reply}));
      } else {
         _fallbackGreeting();
      }
    } catch (_) {
      _fallbackGreeting();
    } finally {
      _isGreetingLoading = false;
      _triggerAutoSave();
    }
  }

  void _fallbackGreeting() {
    String studentTitle = isFemale ? "Siswi" : "Siswa";
    String currentClassStr = studentClass ?? "Kelas 10";
    String greeting = isTeacher
        ? "Selamat datang kembali Guru Informatika yang tampan dan berwibawa! Keisha AI siap mendampingi pembelajaran hari ini."
        : "Halo $displayName ($studentTitle $currentClassStr)! Selamat datang di Keisha AI, asisten pribadi dari Guru Informatika kita yang hebat.";
    if (mounted) setState(() => _messages.add({'sender': 'ai', 'text': greeting}));
  }

  Future<void> _sendMessage([String? customText]) async {
    final text = customText ?? _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    
    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      isLoading = true;
      statusText = "Keisha sedang berpikir...";
    });

    _scrollToBottom();
    _triggerAutoSave();
    _incrementXP(5);
    await _checkAktivisJumatBadge();

    if (text.toLowerCase().contains("buatkan gambar") ||
        text.toLowerCase().contains("gambar foto") ||
        text.toLowerCase().contains("lukiskan")) {
      String cleanPrompt = text.replaceAll(RegExp(r'buatkan gambar|gambar foto|lukiskan', caseSensitive: false), '').trim();
      String imageUrl = "https://image.pollinations.ai/prompt/${Uri.encodeComponent(cleanPrompt)}?width=800&height=600&nologo=true";

      setState(() {
        _messages.add({
          'sender': 'ai',
          'text': 'Berikut adalah gambar visual untuk "$cleanPrompt":',
          'generated_image': imageUrl
        });
        isLoading = false;
        statusText = "Online";
      });
      _scrollToBottom();
      _triggerAutoSave();
      return;
    }

    try {
      List<Map<String, String>> apiMessages = [
        {"role": "system", "content": systemInstruction}
      ];

      for (var msg in _messages) {
        if (msg['sender'] == 'user' && msg['text'] != null && msg['text'].toString().isNotEmpty) {
          apiMessages.add({"role": "user", "content": msg['text']});
        } else if (msg['sender'] == 'ai' && msg['text'] != null && msg['text'].toString().isNotEmpty) {
          apiMessages.add({"role": "assistant", "content": msg['text']});
        }
      }

      String aiReplyRaw = await AIService.callMercuryApi(apiMessages);
      String aiReply = _cleanUtf8Text(aiReplyRaw.trim());

      String? docType;
      bool isCreate = text.toLowerCase().contains("buatkan") ||
          text.toLowerCase().contains("word") ||
          text.toLowerCase().contains("excel") ||
          text.toLowerCase().contains("game") ||
          text.toLowerCase().contains("kalkulator") ||
          text.toLowerCase().contains("html");

      if (isCreate) {
        if (text.toLowerCase().contains("word") || text.toLowerCase().contains("surat")) {
          docType = "Dokumen Word";
        } else if (text.toLowerCase().contains("excel") || text.toLowerCase().contains("tabel")) {
          docType = "Tabel Excel";
        } else {
          docType = "Kode HTML/Game";
        }
      }

      _streamTypewriterEffect(aiReply, docType: docType);

    } catch (e) {
      if(mounted) {
        setState(() => _messages.add({'sender': 'ai', 'text': '⚠️ Gagal terhubung ke Mercury 2 API. Periksa kembali koneksi atau API Key Anda.'}));
      }
    } finally {
      if(mounted) {
        setState(() {
          isLoading = false;
          statusText = "Online";
        });
      }
      _scrollToBottom();
      _triggerAutoSave();
    }
  }

  void _streamTypewriterEffect(String fullText, {String? docType}) {
    _typewriterTimer?.cancel(); 

    _currentFullStreamText = fullText;
    _currentStreamIndex = 0;
    String currentText = "";

    _messages.add({
      'sender': 'ai',
      'text': '',
      'doc_type': docType,
    });
    int lastMsgIndex = _messages.length - 1;

    setState(() => isTypingStreaming = true);

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_currentStreamIndex < fullText.length) {
        int chunkSize = 2; 
        if (_currentStreamIndex + chunkSize > fullText.length) {
          chunkSize = fullText.length - _currentStreamIndex;
        }
        currentText += fullText.substring(_currentStreamIndex, _currentStreamIndex + chunkSize);
        _currentStreamIndex += chunkSize;

        setState(() => _messages[lastMsgIndex]['text'] = currentText);
        _scrollToBottom();
      } else {
        timer.cancel();
        setState(() => isTypingStreaming = false);
        _triggerAutoSave();
      }
    });
  }

  void _skipTypewriterEffect() {
    _typewriterTimer?.cancel();
    if (_currentFullStreamText != null && _messages.isNotEmpty) {
      setState(() {
        _messages.last['text'] = _currentFullStreamText;
        isTypingStreaming = false;
      });
      _scrollToBottom();
      _triggerAutoSave();
    }
  }

  void _openTaskDialogWithPreffiledData(String aiResponseText) {
    setState(() {
      _taskTitleController.text = "Tugas Baru dari Keisha";
      _taskDescController.text = aiResponseText;
      _taskKeysController.text = ""; 
      _taskSelectedType = "Pilihan Ganda";
    });
    _showTaskDialog();
  }

  void _showTaskDialog() {
    bool isSubmitting = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(isTeacher ? "Kelola & Kirim Tugas Guru" : "Bank Tugas Aktif"),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTeacher) ...[
                    Row(
                      children: [
                        const Text("Tipe Tugas: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _taskSelectedType,
                            isExpanded: true,
                            items: ["Pilihan Ganda", "Essay"].map((String val) {
                              return DropdownMenuItem<String>(value: val, child: Text(val));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => _taskSelectedType = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _taskTitleController,
                      decoration: const InputDecoration(hintText: "Judul Tugas...", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _taskDescController,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: "Isi Soal Tugas...", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _taskCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: "Jumlah Soal (misal: 15)", border: OutlineInputBorder()),
                    ),
                    
                    if (_taskSelectedType == "Pilihan Ganda") ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _taskKeysController,
                        decoration: const InputDecoration(hintText: "Kunci Jawaban PG (contoh: A,B,C...)", border: OutlineInputBorder()),
                      ),
                    ],

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text("Target Kelas: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _taskSelectedTargetClass,
                            isExpanded: true,
                            items: ["Semua Kelas", "Kelas 10", "Kelas 11", "Kelas 12"].map((String val) {
                              return DropdownMenuItem<String>(value: val, child: Text(val));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => _taskSelectedTargetClass = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF616BF2)),
                        onPressed: isSubmitting ? null : () async {
                          if (_taskTitleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Judul tugas wajib diisi!", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
                            return;
                          }

                          int qCount = int.tryParse(_taskCountController.text) ?? 15;
                          List<String> keys = [];

                          if (_taskSelectedType == "Pilihan Ganda") {
                              if (_taskKeysController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Kunci Jawaban PG wajib diisi!", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
                                  return;
                              }
                              String rawKeys = _taskKeysController.text.toUpperCase().replaceAll(RegExp(r'[^A-Z,]'), '');
                              keys = rawKeys.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                              
                              if (keys.length != qCount) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Peringatan: Jumlah Kunci Jawaban (${keys.length}) tidak sama dengan Jumlah Soal ($qCount)!", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
                                  return;
                              }
                          }
                          
                          setModalState(() => isSubmitting = true);
                          
                          try {
                            await http.post(
                              Uri.parse("$_firebaseUrl/tasks.json"),
                              body: jsonEncode({
                                "title": _taskTitleController.text,
                                "description": _taskDescController.text,
                                "targetClass": _taskSelectedTargetClass,
                                "type": _taskSelectedType, 
                                "question_count": qCount,
                                "answer_keys": keys,
                                "created_at": DateTime.now().toString()
                              }),
                            );
                            
                            _taskTitleController.clear();
                            _taskDescController.clear();
                            _taskKeysController.clear();
                            
                            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Tugas Berhasil Dikirim ke Kelas!")));
                          } catch (e) {
                             if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal mengirim tugas. Cek koneksi internet."), backgroundColor: Colors.redAccent));
                          } finally {
                            setModalState(() => isSubmitting = false);
                          }
                        },
                        child: isSubmitting 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Text("Kirim Tugas ke Target Kelas", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const Divider(),
                  ],
                  const Text("Daftar Tugas Aktif:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FutureBuilder(
                    future: http.get(Uri.parse("$_firebaseUrl/tasks.json")),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();
                      if (snapshot.hasData && snapshot.data?.statusCode == 200) {
                        final rawBody = snapshot.data?.body;
                        if (rawBody != null && rawBody != "null") {
                          Map<String, dynamic> tasks = jsonDecode(rawBody);
                          
                          var filteredTasks = tasks.entries.where((e) {
                            if (isTeacher) return true;
                            var t = e.value;
                            String target = t['targetClass'] ?? "Semua Kelas";
                            return target == "Semua Kelas" || target == studentClass;
                          }).toList();

                          if (filteredTasks.isEmpty) {
                            return const Text("Belum ada tugas untuk kelas Anda.");
                          }

                          return Column(
                            children: filteredTasks.map((e) {
                              var t = e.value;
                              String taskId = e.key;
                              String targetInfo = t['targetClass'] ?? "Semua Kelas";
                              String taskType = t['type'] ?? "Pilihan Ganda";
                              int qCount = t['question_count'] ?? 10;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  title: Text("${t['title']} [$targetInfo]", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  subtitle: Text("$taskType • $qCount Soal\n${t['description'] ?? ''}", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                                  trailing: isTeacher
                                      ? IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                                          onPressed: () async {
                                            await http.delete(Uri.parse("$_firebaseUrl/tasks/$taskId.json"));
                                            setModalState((){}); 
                                          },
                                        )
                                      : const Icon(Icons.chevron_right, color: Color(0xFF616BF2)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showInteractiveQuizSheet(taskId, t['title'] ?? 'Tugas', t['description'] ?? '', t['answer_keys'] ?? [], taskType, qCount);
                                  },
                                ),
                              );
                            }).toList(),
                          );
                        }
                      }
                      return const Text("Belum ada tugas aktif.");
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
        ),
      ),
    );
  }

  void _showInteractiveQuizSheet(String taskId, String title, String rawContent, List<dynamic> answerKeys, String taskType, int totalQuestions) async {
    bool alreadySubmitted = false;
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/submissions.json"));
      if (res.statusCode == 200 && res.body != "null") {
        Map<String, dynamic> subs = jsonDecode(res.body);
        alreadySubmitted = subs.values.any((s) => s['task_id'] == taskId && s['username'] == username);
      }
    } catch (_) {}

    if (alreadySubmitted && !isTeacher) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Kamu sudah mengerjakan tugas ini! Setiap tugas hanya bisa dikerjakan 1x."), backgroundColor: Colors.orangeAccent),
        );
      }
      return;
    }

    Map<int, String> userAnswers = {};
    Map<int, TextEditingController> essayControllers = {};
    List<int> shuffledIndices = List.generate(totalQuestions, (index) => index);
    
    // TIMER LOGIC (15 Menit)
    int remainingSeconds = 15 * 60;
    Timer? examTimer;

    if (taskType == "Essay") {
        for(int i = 1; i <= totalQuestions; i++) {
           essayControllers[i] = TextEditingController();
        }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: isTeacher, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          
          if (examTimer == null && !isTeacher) {
            examTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (remainingSeconds > 0) {
                setModalState(() => remainingSeconds--);
              } else {
                timer.cancel();
                Navigator.pop(context); // Auto close
              }
            });
          }

          int answeredCount = taskType == "Pilihan Ganda" 
              ? userAnswers.length 
              : essayControllers.values.where((c) => c.text.trim().isNotEmpty).length;
          
          double progress = totalQuestions > 0 ? answeredCount / totalQuestions : 0.0;
          String timeFormatted = '${(remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';

          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    if (isTeacher)
                      IconButton(icon: const Icon(Icons.close), onPressed: () {
                        examTimer?.cancel();
                        Navigator.pop(context);
                      }),
                  ],
                ),
                if (!isTeacher) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: remainingSeconds < 120 ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("⏱️ Sisa Waktu:", style: TextStyle(fontWeight: FontWeight.bold, color: remainingSeconds < 120 ? Colors.red : const Color(0xFF616BF2))),
                        Text(timeFormatted, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: remainingSeconds < 120 ? Colors.red : const Color(0xFF616BF2))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade300,
                      color: const Color(0xFF616BF2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text("Progres: $answeredCount dari $totalQuestions Terjawab", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rawContent, style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 20),
                        const Text("Lembar Jawaban Siswa:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: totalQuestions,
                          itemBuilder: (context, idx) {
                            int actualQuestionIndex = shuffledIndices[idx]; 
                            int displayNum = idx + 1; 

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade700), borderRadius: BorderRadius.circular(12)),
                              child: taskType == "Pilihan Ganda"
                                  ? Row(
                                      children: [
                                        SizedBox(
                                          width: 75,
                                          child: Text("Soal $displayNum:", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: ["A", "B", "C", "D"].map((opt) {
                                              bool isSelected = userAnswers[actualQuestionIndex] == opt;
                                              return InkWell(
                                                onTap: () => setModalState(() => userAnswers[actualQuestionIndex] = opt),
                                                child: CircleAvatar(
                                                  radius: 18,
                                                  backgroundColor: isSelected ? const Color(0xFF616BF2) : Colors.grey.shade800,
                                                  child: Text(opt, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        )
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Jawaban Essay Soal $displayNum:", style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        TextField(
                                          controller: essayControllers[displayNum],
                                          maxLines: 3,
                                          onChanged: (val) => setModalState((){}),
                                          decoration: const InputDecoration(
                                            hintText: "Ketik jawabanmu di sini...",
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.all(8)
                                          ),
                                        )
                                      ],
                                  ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF616BF2)),
                    onPressed: () async {
                      if (answeredCount < totalQuestions && remainingSeconds > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Lengkapi dulu jawaban! Masih ada ${totalQuestions - answeredCount} soal belum diisi.")),
                        );
                        return;
                      }

                      examTimer?.cancel();
                      Navigator.pop(context);
                      
                      String ansSummary = "";
                      int? finalScore;
                      int correctCount = 0;

                      if (taskType == "Pilihan Ganda") {
                          List<int> wrongNumbers = [];
                          for (int i = 0; i < totalQuestions; i++) {
                            int actualIndex = shuffledIndices[i];
                            String studentAns = userAnswers[actualIndex] ?? "";
                            String correctAns = actualIndex < answerKeys.length ? answerKeys[actualIndex].toString() : "";
                            
                            if (studentAns == correctAns) {
                              correctCount++;
                            } else {
                              wrongNumbers.add(i + 1);
                            }
                          }
                          finalScore = ((correctCount / totalQuestions) * 100).round();
                          ansSummary = userAnswers.entries.map((e) => "Soal Asli No ${e.key + 1}: ${e.value}").join(", ");
                          
                          setState(() {
                            _messages.add({
                              'sender': 'ai',
                              'text': 'Tugas "$title" telah berhasil diserahkan!\nNilai Kamu: $finalScore/100 (Benar $correctCount dari $totalQuestions soal).\n${wrongNumbers.isNotEmpty ? "Nomor urut di layar yang perlu diperbaiki: " + wrongNumbers.join(", ") : "Sempurna! Semua benar 100."}'
                            });
                          });
                      } else {
                          List<String> essayAnswers = [];
                          essayControllers.forEach((key, ctrl) {
                              essayAnswers.add("Soal $key: ${ctrl.text}");
                          });
                          ansSummary = essayAnswers.join("\n\n");
                          
                          setState(() {
                            _messages.add({
                              'sender': 'ai',
                              'text': 'Tugas Essay "$title" telah berhasil diserahkan ke Guru Informatika! (Saran AI: Menunggu validasi manual dari Mas Kahfi).'
                            });
                          });
                      }

                      String currentClassStr = studentClass ?? "Kelas 10";
                      
                      await http.post(
                        Uri.parse("$_firebaseUrl/submissions.json"),
                        body: jsonEncode({
                          "task_id": taskId,
                          "username": username,
                          "student": "$displayName ($username - $currentClassStr)",
                          "type": taskType,
                          "answers": ansSummary,
                          "score": finalScore,
                          "correct": correctCount,
                          "total": totalQuestions,
                          "submitted_at": DateTime.now().toString()
                        }),
                      );
                      _scrollToBottom();
                    },
                    child: const Text("KIRIM JAWABAN SAYA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    ).then((_) {
       examTimer?.cancel();
    });
  }

  void _showSubmissionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📥 Hasil Pengumpulan Tugas Siswa"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder(
            future: http.get(Uri.parse("$_firebaseUrl/submissions.json")),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasData && snapshot.data?.statusCode == 200) {
                final raw = snapshot.data?.body;
                if (raw != null && raw != "null") {
                  Map<String, dynamic> subs = jsonDecode(raw);
                  List<MapEntry<String, dynamic>> subList = subs.entries.toList();

                  return Column(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), minimumSize: const Size(double.infinity, 40)),
                        icon: const Icon(Icons.table_chart, color: Colors.white),
                        label: const Text("📊 Export Semua ke CSV (Salin)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () {
                           String csv = "Nama Siswa,Tugas,Tipe,Skor,Benar,Total,Waktu Kumpul\n";
                           for(var e in subList) {
                              var s = e.value;
                              csv += "${s['student'] ?? 'Siswa'},Task_ID_${s['task_id']},${s['type']},${s['score'] ?? 'Perlu Nilai'},${s['correct'] ?? 0},${s['total'] ?? 0},${s['submitted_at']}\n";
                           }
                           _copyToClipboard(csv, "Rekap Nilai CSV");
                           Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          children: subList.map((e) {
                            String subId = e.key;
                            var s = e.value;
                            String taskType = s['type'] ?? "Pilihan Ganda";
                            int? score = s['score'];
                            Color scoreColor = score == null ? Colors.blue : (score >= 75 ? Colors.green : Colors.orange);
                            String scoreText = score == null ? "?" : "$score";

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: scoreColor.withOpacity(0.2),
                                  child: Text(scoreText, style: TextStyle(fontWeight: FontWeight.bold, color: scoreColor, fontSize: 12)),
                                ),
                                title: Text("${s['student'] ?? 'Siswa'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text("$taskType • ${s['submitted_at'] ?? '-'}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF616BF2)),
                                onTap: () {
                                  _showSubmissionDetailPopUp(subId, s);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                }
              }
              return const Center(child: Text("Belum ada siswa yang mengumpulkan tugas."));
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  void _showSubmissionDetailPopUp(String subId, Map<String, dynamic> subData) {
    bool isEssay = (subData['type'] == "Essay" || subData['score'] == null);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Detail Jawaban: ${subData['student']}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isEssay ? "Status: Perlu Dinilai Manual" : "Skor: ${subData['score']}/100", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF616BF2))),
                if (!isEssay) Text("Benar: ${subData['correct']}/${subData['total']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const Divider(),
            const Text("Rincian Lembar Jawaban:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(10),
              width: double.maxFinite,
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: Text(subData['answers'] ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Color(0xFF616BF2)),
            tooltip: "Salin Rekapan Jawaban",
            onPressed: () => _copyToClipboard("Siswa: ${subData['student']}\nSkor: ${subData['score'] ?? 'Perlu Dinilai'}\nJawaban:\n${subData['answers']}", "Rekapan Jawaban"),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: "Hapus Hasil Ini",
            onPressed: () async {
              await http.delete(Uri.parse("$_firebaseUrl/submissions/$subId.json"));
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                _showSubmissionsDialog();
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup")),
        ],
      ),
    );
  }

  void _showRoleManagerModal(String targetUsername, String targetDisplayName) async {
    List<String> currentRoles = [];
    try {
      final res = await http.get(Uri.parse("$_firebaseUrl/users/$targetUsername/roles.json"));
      if (res.statusCode == 200 && res.body != "null") {
        dynamic raw = jsonDecode(res.body);
        if (raw is List) {
          currentRoles = List<String>.from(raw);
        } else if (raw is Map) {
          currentRoles = raw.values.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}

    List<String> initialRoles = List.from(currentRoles);
    final assignableRoles = allDefinedRoles.where((r) => r.id != "guru" && r.id != "default" && !r.id.contains("_chat")).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            title: Text("Atur Role: $targetDisplayName", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: assignableRoles.map((r) {
                  bool isSelected = currentRoles.contains(r.id);
                  return CheckboxListTile(
                    activeColor: const Color(0xFF616BF2),
                    title: Row(
                      children: [
                        Text(r.badge, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(r.name, style: TextStyle(fontWeight: FontWeight.bold, color: r.color, fontSize: 13)),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (val) {
                      setModalState(() {
                        if (val == true) {
                          if (!currentRoles.contains(r.id)) currentRoles.add(r.id);
                        } else {
                          currentRoles.remove(r.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF616BF2)),
                onPressed: () async {
                  try {
                    await http.put(
                      Uri.parse("$_firebaseUrl/users/$targetUsername/roles.json"),
                      body: jsonEncode(currentRoles),
                    );

                    List<String> newlyAddedRoles = currentRoles.where((r) => !initialRoles.contains(r)).toList();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("✅ Role untuk $targetDisplayName berhasil diperbarui!"))
                      );
                      Navigator.pop(ctx);
                      
                      if (newlyAddedRoles.isNotEmpty) {
                        List<String> roleNames = newlyAddedRoles.map((rId) => allDefinedRoles.firstWhere((r) => r.id == rId).name).toList();
                        String roleString = roleNames.join(" & ");
                        String pengumuman = "🌟 *PENGUMUMAN SPESIAL:* @$targetDisplayName baru saja dianugerahi Role Kehormatan **$roleString** oleh Guru Informatika! Beri tepuk tangan! 🎉";
                        
                        _sendClassMessagePayload(pengumuman, activeClassChatTab);
                      }
                    }
                  } catch (_) {}
                },
                child: const Text("Simpan Role", style: TextStyle(color: Colors.white)),
              )
            ],
          );
        },
      ),
    );
  }

  void _showUserStatistics() async {
    if (_cachedUsersMap.isEmpty) {
      await _fetchUsersMapSmartCache();
    }
    
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📊 Statistik Pengguna Unik"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Builder(
            builder: (context) {
              if (_cachedUsersMap.isEmpty) return const Center(child: Text("Belum ada data pendaftar."));
              
              List<String> userList = _cachedUsersMap.keys.toList();
              return ListView(
                children: userList.map((uKey) {
                  var uData = _cachedUsersMap[uKey];
                  String dName = uData["display_name"] ?? uKey;
                  bool isUserTeacher = uData["is_teacher"] ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      onTap: () => _showUserProfileShowcase(uKey, dName, isUserTeacher ? "guru" : "siswa"),
                      dense: true,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: const Color(0xFF616BF2),
                        child: Text(dName.isNotEmpty ? dName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      title: Text("$dName (@$uKey)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(uData["class"] ?? "Kelas 10", style: const TextStyle(fontSize: 10)),
                      trailing: (isTeacher && !isUserTeacher)
                          ? ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF616BF2),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.star, color: Colors.white, size: 12),
                              label: const Text("Atur Role", style: TextStyle(color: Colors.white, fontSize: 10)),
                              onPressed: () => _showRoleManagerModal(uKey, dName),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  Widget _buildClassChatEndDrawer() {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF616BF2),
                child: Row(
                  children: [
                    const Icon(Icons.forum, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(child: Text("💬 Ruang Diskusi Kelas", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions, color: Colors.white),
                      onPressed: () => _showStickerPicker(isClassForum: true),
                    ),
                    if (isTeacher)
                      IconButton(
                        icon: Icon(isGroupMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                        onPressed: () => setState(() => isGroupMuted = !isGroupMuted),
                      )
                  ],
                ),
              ),
              if (isTeacher)
                Container(
                  color: Theme.of(context).cardColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ["Kelas 10", "Kelas 11", "Kelas 12"].map((cName) {
                      bool isActive = activeClassChatTab == cName;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            activeClassChatTab = cName;
                            _currentClassMessages.clear();
                          });
                          _listenToClassChat();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? const Color(0xFF616BF2) : Colors.transparent, width: 3))),
                          child: Text(cName, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? const Color(0xFF616BF2) : Colors.grey)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
              if (_pinnedMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    border: const Border(bottom: BorderSide(color: Colors.amber, width: 2))
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin, size: 16, color: Color(0xFFD35400)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_pinnedMessage!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD35400)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (isTeacher)
                        InkWell(
                          onTap: () async {
                            await FirebaseDatabase.instance.ref("class_chats/${activeClassChatTab.replaceAll(' ', '_').toLowerCase()}_pinned").remove();
                            setState(() => _pinnedMessage = null);
                          },
                          child: const Icon(Icons.close, size: 16, color: Colors.grey),
                        )
                    ],
                  ),
                ),

              Expanded(
                child: _currentClassMessages.isEmpty
                    ? const Center(child: Text("Belum ada obrolan di kelas ini.", style: TextStyle(color: Colors.grey, fontSize: 12)))
                    : ListView.builder(
                        controller: _classChatScrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _currentClassMessages.length,
                        itemBuilder: (context, idx) {
                          var msg = _currentClassMessages[idx];
                          bool isMe = msg["sender"] == username;
                          bool isGuruMsg = msg["role"] == "Guru Informatika" || msg["role"] == "guru";
                          String msgContent = msg['message'] ?? '';
                          String msgDispName = msg['display_name'] ?? msg['sender'] ?? 'Siswa';
                          Map<String, dynamic> reactions = msg['reactions'] is Map ? Map<String, dynamic>.from(msg['reactions']) : {};
                          var replyData = msg['reply_to']; 

                          bool isStickerMsg = msgContent.startsWith("[STIKER]");
                          bool isImageB64Msg = msgContent.startsWith("[IMAGE_B64]");
                          bool isImageUrlMsg = msgContent.startsWith("[IMAGE_URL]");

                          Color bubbleColor = msg["computed_color"] ?? (isGuruMsg ? const Color(0xFFD35400) : const Color(0xFF1E293B));
                          String badge = msg["computed_badge"] ?? "";

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe) ...[
                                  GestureDetector(
                                    onTap: () => _showUserProfileShowcase(msg['sender'], msgDispName, msg['role']),
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: bubbleColor.withOpacity(0.8),
                                      child: Text(msgDispName.isNotEmpty ? msgDispName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                
                                GestureDetector(
                                  onLongPress: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (ctx) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.reply, color: Color(0xFF616BF2)),
                                              title: const Text("Balas Pesan Ini"),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                setState(() => _replyingToMessage = msg);
                                              },
                                            ),
                                            if (isTeacher) ...[
                                              ListTile(
                                                leading: const Icon(Icons.push_pin, color: Colors.amber),
                                                title: const Text("Pin Pengumuman Kelas"),
                                                onTap: () async {
                                                  Navigator.pop(ctx);
                                                  await FirebaseDatabase.instance.ref("class_chats/${activeClassChatTab.replaceAll(' ', '_').toLowerCase()}_pinned").set({"message": msgContent});
                                                },
                                              ),
                                              if (!isMe)
                                                ListTile(
                                                  leading: const Icon(Icons.star, color: Colors.amber),
                                                  title: const Text("Berikan +25 XP Apresiasi"),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _incrementXP(25, targetUsername: msg['sender']);
                                                    String pengumuman = "🌟 *APRESIASI GURU:* @$msgDispName mendapatkan bonus +25 XP atas partisipasinya yang luar biasa!";
                                                    _sendClassMessagePayload(pengumuman, activeClassChatTab);
                                                  },
                                                ),
                                            ]
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                                    decoration: BoxDecoration(
                                      color: bubbleColor, 
                                      borderRadius: BorderRadius.circular(14),
                                      border: isGuruMsg ? Border.all(color: Colors.amber.withOpacity(0.5), width: 1.5) : null
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("$msgDispName ${badge.isNotEmpty ? badge : ''}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isGuruMsg ? Colors.amber : Colors.white70)),
                                        
                                        if (replyData != null) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(8),
                                              border: const Border(left: BorderSide(color: Color(0xFF00F2FE), width: 3)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  replyData['sender_name'] ?? 'Pesan',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF00F2FE)),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  replyData['message'].toString().startsWith('[STIKER]')
                                                      ? '🎨 Stiker'
                                                      : replyData['message'].toString().startsWith('[IMAGE_')
                                                          ? '📷 Foto'
                                                          : replyData['message'] ?? '',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 10, color: Colors.white70, fontStyle: FontStyle.italic),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 4),
                                        if (isStickerMsg)
                                          Image.network(
                                            msgContent.replaceAll("[STIKER] ", ""),
                                            height: 65,
                                            width: 65,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions, color: Colors.white, size: 40),
                                          )
                                        else if (isImageUrlMsg)
                                          GestureDetector(
                                            onTap: () => _showImageFullscreen(msgContent.replaceAll("[IMAGE_URL] ", "")),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                msgContent.replaceAll("[IMAGE_URL] ", ""),
                                                height: 140,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  padding: const EdgeInsets.all(10),
                                                  color: Colors.black26,
                                                  child: const Text("Gambar rusak", style: TextStyle(color: Colors.white, fontSize: 11)),
                                                ),
                                              ),
                                            ),
                                          )
                                        else if (isImageB64Msg)
                                          GestureDetector(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => Dialog(
                                                  backgroundColor: Colors.transparent,
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(16),
                                                    child: Image.memory(base64Decode(msgContent.replaceAll("[IMAGE_B64] ", "")), fit: BoxFit.contain),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                base64Decode(msgContent.replaceAll("[IMAGE_B64] ", "")),
                                                height: 140,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  padding: const EdgeInsets.all(10),
                                                  color: Colors.black26,
                                                  child: const Text("Gambar rusak", style: TextStyle(color: Colors.white, fontSize: 11)),
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Text(msgContent, style: const TextStyle(color: Colors.white, fontSize: 13)),
  
                                        if (reactions.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 4,
                                            children: reactions.values.toSet().map((emoji) {
                                              int count = reactions.values.where((e) => e == emoji).length;
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                                                child: Text("$emoji $count", style: const TextStyle(fontSize: 10, color: Colors.white)),
                                              );
                                            }).toList(),
                                          )
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _showUserProfileShowcase(username, displayName, isTeacher ? "guru" : "siswa"),
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: bubbleColor.withOpacity(0.8),
                                      child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              
              AnimatedBuilder(
                animation: _classChatScrollController,
                builder: (context, child) {
                  bool showFab = false;
                  if (_classChatScrollController.hasClients) {
                    double maxScroll = _classChatScrollController.position.maxScrollExtent;
                    double currentScroll = _classChatScrollController.position.pixels;
                    showFab = (maxScroll - currentScroll) > 200;
                  }
                  if (!showFab) return const SizedBox.shrink();
                  
                  return Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16, bottom: 8),
                    child: FloatingActionButton.small(
                      backgroundColor: const Color(0xFF616BF2),
                      onPressed: () => _scrollToBottomClassChat(force: true),
                      child: const Icon(Icons.arrow_downward, color: Colors.white),
                    ),
                  );
                },
              ),

              if (_replyingToMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    children: [
                      Container(width: 3, height: 35, color: const Color(0xFF616BF2)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Membalas ${_replyingToMessage!['display_name']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF616BF2)),
                            ),
                            Text(
                              _replyingToMessage!['message'].toString().startsWith('[STIKER]')
                                  ? '🎨 Stiker'
                                  : _replyingToMessage!['message'].toString().startsWith('[IMAGE_')
                                      ? '📷 Foto'
                                      : _replyingToMessage!['message'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                        onPressed: () => setState(() => _replyingToMessage = null),
                      ),
                    ],
                  ),
                ),

              if (!isGroupMuted || isTeacher)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.image, color: Color(0xFF616BF2)), onPressed: _sendClassImageFromGallery),
                      Expanded(
                        child: TextField(
                          controller: _classChatInputController,
                          decoration: const InputDecoration(hintText: "Ketik pesan kelas...", border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.send, color: Color(0xFF616BF2)), onPressed: _sendClassChatMessage)
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeminiDrawer() {
    String currentClassStr = studentClass ?? "Kelas 10";
    String roleText = isTeacher ? "Guru Informatika" : (isFemale ? "Siswi $currentClassStr" : "Siswa $currentClassStr");
    
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _showUserProfileShowcase(username, displayName, isTeacher ? "guru" : "siswa"),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF616BF2),
                      backgroundImage: profileImageBase64 != null ? MemoryImage(base64Decode(profileImageBase64!)) : null,
                      child: profileImageBase64 == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text("@$username • $roleText", style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: _showEditProfileModal,
                    tooltip: "Edit Profil",
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: Color(0xFF616BF2)),
              title: const Text("Mode Gelap (Cyber Dark)"),
              value: widget.isDarkMode,
              onChanged: (val) => widget.onToggleDarkMode(val),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.emoji_events, color: Color(0xFFB7950B)),
              title: const Text("🏆 Top Global Kelas", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _showTopGlobalLeaderboard();
              },
            ),
            ListTile(
              leading: const Icon(Icons.military_tech, color: Color(0xFF616BF2)),
              title: const Text("Panduan Rank & Role Kelas"),
              onTap: () {
                Navigator.pop(context);
                _showRankGuideDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Color(0xFF616BF2)),
              title: const Text("Sesi Baru", style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(context);
                setState(() {
                  _messages.clear();
                  _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
                  _fetchDynamicGreeting();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_outlined, color: Color(0xFF616BF2)),
              title: const Text("Kelola Tugas"),
              onTap: () {
                Navigator.pop(context);
                _showTaskDialog();
              },
            ),
            if (isTeacher) ...[
              ListTile(
                leading: const Icon(Icons.task_alt, color: Color(0xFF616BF2)),
                title: const Text("Hasil Tugas Siswa (Guru)"),
                onTap: () {
                  Navigator.pop(context);
                  _showSubmissionsDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.analytics, color: Color(0xFF616BF2)),
                title: const Text("Statistik & Kelola Role Siswa"),
                onTap: () {
                  Navigator.pop(context);
                  _showUserStatistics();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text("Hapus Obrolan Layar"),
              onTap: () {
                Navigator.pop(context);
                setState(() => _messages.clear());
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text("Riwayat Chat (Auto-Save)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
            ),
            Expanded(
              child: _archives.isEmpty
                  ? const Center(child: Text("Belum ada riwayat.", style: TextStyle(color: Colors.grey, fontSize: 12)))
                  : ListView.builder(
                      itemCount: _archives.length,
                      itemBuilder: (context, index) {
                        var item = _archives[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF616BF2)),
                          title: Text(item['title'] ?? 'Riwayat', maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () async {
                            Navigator.pop(context);
                            List<Map<String, dynamic>> loaded = await DatabaseHelper.loadArchiveByFileId(item['file_id']!);
                            if (loaded.isNotEmpty) {
                              setState(() {
                                _messages.clear();
                                _messages.addAll(loaded);
                                _currentSessionId = item['file_id']!.replaceAll('archive_', '').split('_')[0];
                              });
                            }
                          },
                        );
                      },
                    ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text("Keluar (Logout)", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(context);
                Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();
                db.remove("last_active_user");
                await DatabaseHelper.saveLocalDb(db);
                if(mounted) Navigator.pushReplacementNamed(context, '/get_started');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF616BF2))),
            SizedBox(width: 10),
            Text("Keisha sedang berpikir...", style: TextStyle(fontSize: 13, color: Color(0xFF00F2FE), fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  List<Widget> _parseMessageWithCodeBlocks(String text) {
    if (!text.contains("```")) {
      return [SelectableText(text, style: TextStyle(fontSize: 15, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF262E3D)))];
    }

    List<Widget> widgets = [];
    List<String> parts = text.split("```");
    
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        if (parts[i].trim().isNotEmpty) {
           widgets.add(SelectableText(parts[i].trim(), style: TextStyle(fontSize: 15, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF262E3D))));
        }
      } else {
        String codeContent = parts[i];
        String lang = "";
        int firstNewline = codeContent.indexOf('\n');
        if (firstNewline != -1) {
          lang = codeContent.substring(0, firstNewline).trim();
          codeContent = codeContent.substring(firstNewline + 1);
        }

        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117), 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: const BoxDecoration(color: Color(0xFF161B22), borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(lang.isEmpty ? "Code" : lang.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      InkWell(
                        onTap: () => _copyToClipboard(codeContent, "Kode $lang"),
                        child: Row(
                          children: const [
                            Icon(Icons.copy, size: 12, color: Colors.grey),
                            SizedBox(width: 4),
                            Text("Copy Code", style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(codeContent, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF00F2FE))),
                  ),
                ),
              ],
            ),
          )
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawer: _buildGeminiDrawer(),
      endDrawer: _buildClassChatEndDrawer(),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                    border: isDark ? Border.all(color: const Color(0xFF30363D)) : Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.menu, size: 28), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                      const SizedBox(width: 4),
                      const CircleAvatar(radius: 18, backgroundColor: Color(0xFF616BF2), child: Icon(Icons.smart_toy, color: Colors.white, size: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Keisha AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: statusText == "Online" ? Colors.green : Colors.orange, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text(statusText == "Online" ? "Active | Mercury 2 Engine" : statusText, style: TextStyle(fontSize: 11, color: statusText == "Online" ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                              ],
                            )
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.forum_outlined, color: Color(0xFF616BF2), size: 26),
                        onPressed: () {
                          _scaffoldKey.currentState?.openEndDrawer();
                        },
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _messages.length + (isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (isLoading && index == _messages.length) return _buildThinkingBubble();

                      final msg = _messages[index];
                      final isUser = msg['sender'] == 'user';
                      String msgText = (msg['text'] as String?) ?? '';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF616BF2) : (isDark ? const Color(0xFF161B22) : Colors.white),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isUser ? 20 : 2),
                              bottomRight: Radius.circular(isUser ? 2 : 20),
                            ),
                            border: (!isUser && isDark) ? Border.all(color: const Color(0xFF30363D), width: 1) : (!isUser ? Border.all(color: Colors.grey.shade200) : null),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.smart_toy, size: 16, color: Color(0xFF00F2FE)),
                                        SizedBox(width: 6),
                                        Text("Keisha AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF00F2FE))),
                                      ],
                                    ),
                                    InkWell(
                                      onTap: () => _copyToClipboard(msgText, "Teks Obrolan"),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFF616BF2).withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                        child: Row(children: const [Icon(Icons.copy, size: 14, color: Color(0xFF616BF2)), SizedBox(width: 4), Text("Salin", style: TextStyle(fontSize: 11, color: Color(0xFF616BF2), fontWeight: FontWeight.bold))]),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                              ],

                              if (msg['generated_image'] != null) ...[
                                GestureDetector(
                                  onTap: () => _showImageFullscreen(msg['generated_image']),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(msg['generated_image'], height: 200, width: double.infinity, fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _showImageFullscreen(msg['generated_image']),
                                  icon: const Icon(Icons.download, size: 14, color: Colors.white),
                                  label: const Text("Simpan ke Galeri", style: TextStyle(fontSize: 11, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF616BF2),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              if (msgText.isNotEmpty) ...[
                                if (isUser)
                                  SelectableText(msgText, style: const TextStyle(color: Colors.white, fontSize: 15))
                                else
                                  ..._parseMessageWithCodeBlocks(msgText),
                              ],

                              if (!isUser && isTeacher && (msgText.contains("1.") || msgText.contains("A.")) && msgText.length > 50) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD35400),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                    ),
                                    icon: const Icon(Icons.assignment_turned_in, color: Colors.white, size: 18),
                                    label: const Text(
                                      "📝 Jadikan Tugas Otomatis",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    onPressed: () => _openTaskDialogWithPreffiledData(msgText),
                                  ),
                                )
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.sports_esports, size: 16, color: Color(0xFF616BF2)),
                        label: const Text("🎮 Buat Game HTML Instant", style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          _inputController.text = "Buatkan kode HTML lengkap (termasuk CSS dan JavaScript di dalamnya) untuk game [Nama Game]. Buat dalam satu file utuh yang langsung bisa dijalankan di browser.";
                        },
                      ),
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, 
                    borderRadius: BorderRadius.circular(35),
                    border: isDark ? Border.all(color: const Color(0xFF30363D)) : Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          onTap: _scrollToBottom,
                          decoration: const InputDecoration(
                            hintText: 'Ketik pesan ke Keisha (Mercury 2)...', 
                            border: InputBorder.none, 
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            hintStyle: TextStyle(color: Color(0xFF98A2B3))
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(color: Color(0xFF616BF2), shape: BoxShape.circle),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: () => _sendMessage(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (isTypingStreaming)
              Positioned(
                bottom: 80,
                right: 20,
                child: FloatingActionButton.extended(
                  elevation: 4,
                  backgroundColor: const Color(0xFF00F2FE),
                  icon: const Icon(Icons.flash_on, color: Colors.black, size: 18),
                  label: const Text("⚡ Tampilkan Semua", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _skipTypewriterEffect,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
