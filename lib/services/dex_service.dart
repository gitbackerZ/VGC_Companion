import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

class DexService {
  static final DexService _instance = DexService._internal();
  factory DexService() => _instance;
  DexService._internal();

  JavascriptRuntime? _jsRuntime;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _jsRuntime = getJavascriptRuntime();
    final engineCode = await rootBundle.loadString('assets/engine.js');
    _jsRuntime!.evaluate(engineCode);
    _isInitialized = true;
  }

  List<dynamic> getSpeciesList() {
    if (_jsRuntime == null) return [];
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getSpeciesList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (e) {
      return [];
    }
  }

  List<dynamic> getMoveList() {
    if (_jsRuntime == null) return [];
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getMoveList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (e) {
      return [];
    }
  }

  List<dynamic> getItemList() {
    if (_jsRuntime == null) return [];
    try {
      final jsonStr = _jsRuntime!.evaluate("globalThis.getItemList();").stringResult;
      return jsonDecode(jsonStr);
    } catch (e) {
      return [];
    }
  }
}
