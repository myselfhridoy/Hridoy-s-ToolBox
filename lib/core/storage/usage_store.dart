import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favorites আর Recent টুল ট্র্যাক করে, SharedPreferences-এ persist করে।
class UsageStore extends ChangeNotifier {
  UsageStore._();
  static final UsageStore instance = UsageStore._();

  static const _kFavorites = 'favorites';
  static const _kRecents = 'recents';
  static const _maxRecents = 8;

  SharedPreferences? _prefs;
  List<String> _favorites = [];
  List<String> _recents = [];

  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recents => List.unmodifiable(_recents);

  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _favorites = _prefs?.getStringList(_kFavorites) ?? [];
    _recents = _prefs?.getStringList(_kRecents) ?? [];
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    if (_favorites.contains(id)) {
      _favorites.remove(id);
    } else {
      _favorites.add(id);
    }
    await _prefs?.setStringList(_kFavorites, _favorites);
    notifyListeners();
  }

  Future<void> recordUsage(String id) async {
    _recents.remove(id);
    _recents.insert(0, id);
    if (_recents.length > _maxRecents) {
      _recents = _recents.sublist(0, _maxRecents);
    }
    await _prefs?.setStringList(_kRecents, _recents);
    notifyListeners();
  }

  Future<void> clearRecents() async {
    _recents.clear();
    await _prefs?.setStringList(_kRecents, _recents);
    notifyListeners();
  }
}
