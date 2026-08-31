import 'package:flutter/material.dart';

class RoleBadge {
  final String id;
  final String name;
  final String badge;
  final Color color;
  final int priority;

  RoleBadge({required this.id, required this.name, required this.badge, required this.color, required this.priority});
}

final List<RoleBadge> allDefinedRoles = [
  RoleBadge(id: "guru", name: "Guru Informatika", badge: "📌", color: const Color(0xFFD35400), priority: 99),
  RoleBadge(id: "teladan", name: "Siswa Teladan", badge: "⭐", color: const Color(0xFFB7950B), priority: 12),
  RoleBadge(id: "koding", name: "Master Koding", badge: "💻", color: const Color(0xFF7B1FA2), priority: 11),
  RoleBadge(id: "ketua", name: "Ketua Kelas / Moderator", badge: "👑", color: const Color(0xFF2563EB), priority: 10),
  RoleBadge(id: "mentor", name: "Siswa Mentor / Helper", badge: "🛡️", color: const Color(0xFF059669), priority: 9),
  RoleBadge(id: "designer", name: "UI/UX Designer", badge: "🎨", color: const Color(0xFFDB2777), priority: 8),
  RoleBadge(id: "bughunter", name: "Bug Hunter", badge: "🐛", color: const Color(0xFFDC2626), priority: 7),
  RoleBadge(id: "fastlearner", name: "Fast Learner", badge: "🚀", color: const Color(0xFF0284C7), priority: 6),
  RoleBadge(id: "presenter", name: "Top Presenter", badge: "📢", color: const Color(0xFFD97706), priority: 5),
  RoleBadge(id: "aktivis_jumat", name: "Aktivis Jumat (Misterius)", badge: "🌙", color: const Color(0xFF8E44AD), priority: 4),
  RoleBadge(id: "legend_chat", name: "Legenda Obrolan", badge: "👑", color: const Color(0xFF7C3AED), priority: 3),
  RoleBadge(id: "pro_chat", name: "Siswa Paling Aktif", badge: "🔥", color: const Color(0xFFEA580C), priority: 2),
  RoleBadge(id: "active_chat", name: "Siswa Aktif", badge: "💬", color: const Color(0xFF0D9488), priority: 1),
  RoleBadge(id: "default", name: "Siswa", badge: "🎓", color: const Color(0xFF1E293B), priority: 0),
];
