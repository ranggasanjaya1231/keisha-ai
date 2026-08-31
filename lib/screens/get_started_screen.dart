import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFFEFF3FA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  const CircleAvatar(radius: 18, backgroundColor: Color(0xFF616BF2), child: Icon(Icons.smart_toy, color: Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Keisha AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                      Text('Informatics Assistant', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              children: [
                const Text('KEISHA AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                const Text('Your Personal AI Senior Engineer,\nMaster Game Developer & Informatics Partner', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4)),
                const SizedBox(height: 25),
                Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF616BF2).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: const Icon(Icons.smart_toy_rounded, size: 85, color: Color(0xFF616BF2)),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              decoration: const BoxDecoration(color: Color(0xFF616BF2), borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                      onPressed: () => Navigator.pushNamed(context, '/auth'),
                      child: const Text('GET STARTED', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF616BF2))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(onTap: () => Navigator.pushNamed(context, '/auth', arguments: false), child: const Text('Login', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                      GestureDetector(onTap: () => Navigator.pushNamed(context, '/auth', arguments: true), child: const Text('Sign up', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
