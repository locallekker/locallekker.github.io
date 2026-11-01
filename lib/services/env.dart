import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> loadEnv() async {
  await dotenv.load(fileName: '${Directory.current.path}/.env');
}
