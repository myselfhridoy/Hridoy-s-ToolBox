import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Ksoup-এর মতো CSS selector API — Dart-এর `html` প্যাকেজের ওপর হেল্পার।
class HtmlUtils {
  HtmlUtils._();

  /// HTML স্ট্রিং পার্স করে Document রিটার্ন করে।
  static Document parse(String html) => html_parser.parse(html);

  /// CSS selector দিয়ে সব element।
  static List<Element> selectAll(Document doc, String selector) =>
      doc.querySelectorAll(selector);

  /// CSS selector দিয়ে প্রথম element (থাকলে)।
  static Element? select(Document doc, String selector) =>
      doc.querySelector(selector);

  /// selector-এর সব element-এর text (trimmed)।
  static List<String> texts(Document doc, String selector) =>
      doc.querySelectorAll(selector).map((e) => e.text.trim()).toList();

  /// selector-এর সব element-এর নির্দিষ্ট attribute।
  static List<String?> attrs(Document doc, String selector, String attr) =>
      doc.querySelectorAll(selector).map((e) => e.attributes[attr]).toList();

  /// HTML থেকে শুধু প্লেইন টেক্সট (tags বাদ)।
  static String stripTags(String html) =>
      html_parser.parseFragment(html).text.trim();
}
