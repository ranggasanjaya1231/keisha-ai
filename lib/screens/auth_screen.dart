import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/database_helper.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isRegister = true;
  bool rememberMe = true;
  bool isFemale = false;
  
  String selectedClass = "Kelas 10";
  final List<String> classOptions = ["Kelas 10", "Kelas 11", "Kelas 12"];
  
  final _userController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _tokenController = TextEditingController();
  final _teacherTokenController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmPassController = TextEditingController();
  String statusMsg = "";

  final String _firebaseUrl = "https://keisha-informatics-app-default-rtdb.asia-southeast1.firebasedatabase.app";
  final Map<String, String> validClassTokens = {"Kelas 10": "INF10", "Kelas 11": "INF11", "Kelas 12": "INF12"};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is bool) isRegister = args;
  }

  Future<void> _processAuth() async {
    String username = _userController.text.trim().toLowerCase();
    String displayName = _displayNameController.text.trim();
    String password = _passController.text.trim();
    String token = _tokenController.text.trim().toUpperCase();
    String teacherToken = _teacherTokenController.text.trim().toUpperCase();

    if (username.isEmpty || password.isEmpty) {
      setState(() => statusMsg = "Username dan Sandi wajib diisi!");
      return;
    }
    if (displayName.isEmpty) displayName = username;

    bool isTeacherAccount = (teacherToken == "INFGURU") || username.contains("kahfi") || username.contains("muzaini");
    Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();

    if (isRegister) {
      if (db.containsKey(username) && username != "last_active_user") {
        setState(() => statusMsg = "Username sudah terdaftar! Silakan Login.");
        return;
      }
      if (password != _confirmPassController.text.trim()) {
        setState(() => statusMsg = "Konfirmasi kata sandi tidak cocok!");
        return;
      }
      if (!isTeacherAccount) {
        String expectedToken = validClassTokens[selectedClass] ?? "INF10";
        if (token != expectedToken) {
          setState(() => statusMsg = "Kode Akses $selectedClass Salah!");
          return;
        }
      }

      db[username] = {
        "password": password, "display_name": displayName, "class": isTeacherAccount ? "Guru Informatika" : selectedClass,
        "is_female": isFemale, "is_teacher": isTeacherAccount, "remember_me": rememberMe, "created_at": DateTime.now().toString()
      };
      
      if (rememberMe) db["last_active_user"] = username;
      await DatabaseHelper.saveLocalDb(db);

      try {
        await http.put(
          Uri.parse("$_firebaseUrl/users/$username.json"),
          body: jsonEncode({
            "username": username, "display_name": displayName, "class": isTeacherAccount ? "Guru Informatika" : selectedClass,
            "is_teacher": isTeacherAccount, "is_female": isFemale, "roles": isTeacherAccount ? ["guru"] : ["default"], "xp": 0
          }),
        );
      } catch (_) {}
    } else {
      if (db.containsKey(username)) {
        String savedPass = db[username]["password"] ?? "";
        if (savedPass.isNotEmpty && savedPass != password) {
          setState(() => statusMsg = "Kata sandi salah! Akses ditolak.");
          return;
        }
        if (db[username]["display_name"] != null) displayName = db[username]["display_name"];
        if (db[username]["is_female"] != null) isFemale = db[username]["is_female"];
        if (db[username]["class"] != null) selectedClass = db[username]["class"];
        isTeacherAccount = db[username]["is_teacher"] ?? isTeacherAccount;
      } else {
        db[username] = {
          "password": password, "display_name": displayName, "class": isTeacherAccount ? "Guru Informatika" : selectedClass,
          "is_female": isFemale, "is_teacher": isTeacherAccount, "remember_me": rememberMe, "created_at": DateTime.now().toString()
        };
      }
      db["last_active_user"] = username;
      await DatabaseHelper.saveLocalDb(db);
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context, '/chat', 
      arguments: {"username": username, "display_name": displayName, "is_female": isFemale, "class": isTeacherAccount ? "Guru Informatika" : selectedClass, "is_teacher": isTeacherAccount}
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: Text(isRegister ? 'Buat Akun Baru' : 'Masuk Keisha AI', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF0F172A))), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          children: [
            const CircleAvatar(radius: 36, backgroundColor: Color(0xFF616BF2), child: Icon(Icons.person_add, size: 36, color: Colors.white)),
            const SizedBox(height: 20),
            _buildInputField(_userController, "Username Unik (ID Login)"),
            const SizedBox(height: 12),
            _buildInputField(_displayNameController, "Nama Tampilan / Nama Panggilan"),
            if (isRegister) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.school, color: Color(0xFF616BF2), size: 20), const SizedBox(width: 12),
                    const Text("Pilih Kelas:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))), const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedClass, isExpanded: true,
                          items: classOptions.map((String val) { return DropdownMenuItem<String>(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))); }).toList(),
                          onChanged: (val) { if (val != null) setState(() => selectedClass = val); },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildInputField(_tokenController, "Kode Akses Kelas Siswa (Token INF)"),
              const SizedBox(height: 12),
              _buildInputField(_teacherTokenController, "Kode Akses Khusus Guru (Opsional)"),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Text("Panggilan:", style: TextStyle(color: Color(0xFF334155))), const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Radio<bool>(value: false, groupValue: isFemale, activeColor: const Color(0xFF616BF2), onChanged: (val) => setState(() => isFemale = val ?? false)), const Text("Siswa"),
                          Radio<bool>(value: true, groupValue: isFemale, activeColor: const Color(0xFF616BF2), onChanged: (val) => setState(() => isFemale = val ?? true)), const Text("Siswi"),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildInputField(_passController, "Sandi", isPassword: true),
            if (isRegister) ...[
              const SizedBox(height: 12),
              _buildInputField(_confirmPassController, "Konfirmasi Sandi", isPassword: true),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(value: rememberMe, activeColor: const Color(0xFF616BF2), onChanged: (val) => setState(() => rememberMe = val ?? true)),
                const Text('Ingat Saya (Remember Me)', style: TextStyle(fontSize: 14, color: Color(0xFF334155))),
              ],
            ),
            if (statusMsg.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(statusMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF616BF2), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                onPressed: _processAuth,
                child: Text(isRegister ? 'DAFTAR & MASUK' : 'MASUK SEKARANG', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            TextButton(
              onPressed: () => setState(() { isRegister = !isRegister; statusMsg = ""; }),
              child: Text(isRegister ? 'Sudah punya akun? Masuk di sini' : 'Belum punya akun? Daftar baru', style: const TextStyle(color: Color(0xFF4752D9), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String hint, {bool isPassword = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: const TextStyle(color: Color(0xFF0F172A)),
        decoration: InputDecoration(hintText: hint, border: InputBorder.none, hintStyle: const TextStyle(color: Color(0xFF94A3B8))),
      ),
    );
  }
}
