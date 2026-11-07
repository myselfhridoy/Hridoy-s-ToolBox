import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Ksoup-এর মতো CSS selector API — Dart-এর `html` প্যাকেজের ওপর হেল্পার।
///
/// সব return type `dom.` prefix দিয়ে namespaced, যাতে Flutter-এর
/// `Text`/`Element` widget-এর সাথে নাম সংঘর্ষ না হয়।
class HtmlUtils {
  HtmlUtils._();

  /// HTML স্ট্রিং পার্স করে Document রিটার্ন করে।
  static dom.Document parse(String html) => html_parser.parse(html);

  /// CSS selector দিয়ে সব element।
  static List<dom.Element> selectAll(dom.Document doc, String selector) =>
      doc.querySelectorAll(selector);

  /// CSS selector দিয়ে প্রথম element (থাকলে)।
  static dom.Element? select(dom.Document doc, String selector) =>
      doc.querySelector(selector);

  /// selector-এর সব element-এর text (trimmed)।
  static List<String> texts(dom.Document doc, String selector) =>
      doc.querySelectorAll(selector).map((e) => e.text.trim()).toList();

  /// selector-এর সব element-এর নির্দিষ্ট attribute।
  static List<String?> attrs(
    dom.Document doc,
    String selector,
    String attr,
  ) =>
      doc.querySelectorAll(selector).map((e) => e.attributes[attr]).toList();

  /// HTML থেকে শুধু প্লেইন টেক্সট (tags বাদ)।
  static String stripTags(String html) =>
      html_parser.parseFragment(html).text?.trim() ?? '';
}
