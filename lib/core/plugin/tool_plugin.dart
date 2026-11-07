import 'package:flutter/material.dart';

abstract class ToolPlugin {
  String get id;
  String get name;
  IconData get icon;
  List<String> get categories;
  List<String> get tags;

  Widget buildPage(BuildContext context);
}
