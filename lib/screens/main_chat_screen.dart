import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_database/firebase_database.dart';

// Import file modular yang baru dibuat
import '../models/role_badge.dart';
import '../services/ai_service.dart';
import '../services/database_helper.dart';

// === TEMPEL CLASS MainChatScreen DAN _MainChatScreenState DI SINI ===
