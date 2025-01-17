import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:html/parser.dart';
import 'package:html/dom.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:http/http.dart' as http;

// computed style is a stack, each time we encounter an element like <p>... we push its style onto the stack, then pop it off at </p>
// the top of the stack merges all of the styles of the parents.
class ComputedStyle {
  List<Style> stack = [Style()];
  push(Style s, e) {
    var base = stack.last;
    s = s;
    s.e = e;
    stack.add(s.merge(base));
  }

  pop() {
    stack.removeLast();
  }

  pw.TextStyle style() {
    return stack.last.style();
  }

  Style parent() {
    return stack[stack.length - 1];
  }

  // Style parent2() {
  //   return stack[stack.length - 2];
  // }
}

Future<Uint8List> getImage(imageUrl) async {
  final formatUrl = Uri.parse(imageUrl);
  var url = Uri.https(formatUrl.host, formatUrl.path);
  var response = await http.get(url);
  final bytes = response.bodyBytes;
  return bytes;
}

class _UrlText extends pw.StatelessWidget {
  _UrlText(this.text, this.url);

  final String text;
  final String url;

  @override
  pw.Widget build(pw.Context context) {
    return pw.UrlLink(
      destination: url,
      child: pw.Text(text,
          style: const pw.TextStyle(
            decoration: pw.TextDecoration.underline,
            decorationColor: PdfColors.blue,
            color: PdfColors.blue,
          )),
    );
  }
}

// you will need to add more attributes here, just follow the pattern.
class Style {
  pw.Font? font;
  pw.FontWeight? weight;
  double? height;
  pw.FontStyle? fontStyle;
  pw.UrlLink? urlLink;
  p.PdfColor? color;
  int listNumber = 0;
  pw.Container? container;
  int? listIndent;
  pw.Widget? bullet;
  pw.TextDecoration? textDecoration;
  pw.BoxDecoration? boxDecoration;
  Node? e;
  Style(
      {this.font,
      this.weight,
      this.height,
      this.fontStyle,
      this.color,
      this.bullet,
      this.container,
      this.listIndent = 0,
      this.listNumber = 0,
      this.e,
      this.textDecoration,
      this.boxDecoration});

  Style merge(Style s) {
    font ??= s.font;
    weight ??= s.weight;
    height ??= s.height;
    fontStyle ??= s.fontStyle;
    color ??= s.color;
    container ??= s.container;
    bullet ??= s.bullet;
    textDecoration ??= s.textDecoration;
    boxDecoration ??= s.boxDecoration;
    return this;
  }

  pw.TextStyle style() {
    return pw.TextStyle(
        font: font,
        fontWeight: weight,
        fontSize: height,
        color: color,
        fontStyle: fontStyle,
        decoration: textDecoration,
        background: boxDecoration);
  }
}

class BorderStyle {
  const BorderStyle({
    this.paint = true,
    this.pattern,
    this.phase = 0,
  });

  static const none = BorderStyle(paint: false);
  static const solid = BorderStyle();
  static const dashed = BorderStyle(pattern: <int>[3, 3]);
  static const dotted = BorderStyle(pattern: <int>[1, 1]);

  /// Paint this line
  final bool paint;

  /// Lengths of alternating dashes and gaps. The numbers shall be nonnegative
  /// and not all zero.
  final List<num>? pattern;

  /// Specify the distance into the dash pattern at which to start the dash.
  final int phase;
}

// each node is formatted as a chunk. A chunk can be a list of widgets ready to format, or a series of text spans that will be incorporated into a parent widget.
class Chunk {
  List<pw.Widget>? widget;
  pw.TextSpan? text;
  Chunk({this.widget, this.text});
}

// post order traversal of the html tree, recursively format each node.
class Styler {
  var style = ComputedStyle();

  get text => null;

  Chunk formatStyle(Node e, Style s) {
    style.push(s, e);
    var o = format(e);
    style.pop();
    return o;
  }

  List<pw.Widget> widgetChildren(Node e, Style s) {
    style.push(s, e);
    List<pw.Widget> r = [];
    List<pw.TextSpan> spans = [];
    clear() {
      if (spans.isNotEmpty) {
        // turn text into widget
        r.add(pw.RichText(text: pw.TextSpan(children: spans)));
        spans = [];
      }
    }

    for (var o in e.nodes) {
      var ch = format(o);
      if (ch.widget != null) {
        clear();
        r = [...r, ...ch.widget!];
      } else if (ch.text != null) {
        spans.add(ch.text!);
      }
    }
    clear();
    style.pop();
    return r;
  }

  pw.TextSpan inlineChildren(Node e, Style s) {
    style.push(s, e);
    List<pw.InlineSpan> r = [];
    for (var o in e.nodes) {
      var ch = format(o);
      if (ch.text != null) {
        r.add(ch.text!);
      }
    }
    style.pop();
    return pw.TextSpan(children: r);
  }

  pw.TextStyle? s = null;
  pw.Divider? f = null;

  // I only implmenented necessary ones, but follow the pattern

  int i = 0;

  Chunk format(Node e) {
    switch (e.nodeType) {
      case Node.TEXT_NODE:
        return Chunk(
            text:
                pw.TextSpan(baseline: 0, style: style.style(), text: (e.text)));
      case Node.ELEMENT_NODE:
        e as Element;
        // for (var o in e.attributes.entries) { o.key; o.value;}
        switch (e.localName) {
          // SPANS
          // spans can contain text or other spans
          case "span":
          // case "code":
          //   return Chunk(text: inlineChildren(e, Style()));
          case "code":
            return Chunk(
                text: inlineChildren(
                    e,
                    Style(
                        boxDecoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius:
                              pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        font: pw.Font.courier())));
          case "strong":
            return Chunk(
                text: inlineChildren(e, Style(weight: pw.FontWeight.bold)));
          case "em":
            return Chunk(
                text: inlineChildren(e, Style(fontStyle: pw.FontStyle.italic)));
          case "a":
            return Chunk(
                widget: [_UrlText((e.innerHtml), (e.attributes["href"]!))]);
          case "del":
            return Chunk(
                text: inlineChildren(
                    e,
                    Style(
                        color: PdfColors.black,
                        textDecoration: pw.TextDecoration.lineThrough)));

          // blocks can contain blocks or spans
          case "ul":
          case "ol":
            var ln;
            final cl = e.attributes["start"];
            if (cl != null) {
              ln = int.parse(cl) - 1;
            } else {
              ln = 0;
            }
            return Chunk(
                widget: widgetChildren(
                    e,
                    Style(
                      bullet: e.localName == "ul" ? pw.Bullet() : null,
                      listIndent: style.stack.last.listIndent ?? -4 + 4,
                      listNumber: ln,
                    )));
          // listNumber: e.attributes["start"] == null
          //     ? 0
          //     : int.parse(e.attributes["start"]!))));
          case "hr":
            return Chunk(widget: [pw.Divider()]);
          case "li":
            // we don't need to given an indent because we'll indent the child tree
            final st = style.stack.last;
            final bullet =
                st.bullet ?? pw.Text("${++style.parent().listNumber}");
            final wl = widgetChildren(e, Style());
            final w = pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.SizedBox(width: 20, height: 20, child: bullet),
                  pw.Expanded(
                      child: pw.Padding(
                          padding: pw.EdgeInsets.only(left: 5),
                          child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: wl)))
                ]);
            return Chunk(widget: [w]);
          case "blockquote":
            return Chunk(widget: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              left: pw.BorderSide(
                                  color: p.PdfColors.grey400, width: 2)),
                          color: p.PdfColors.grey200),
                      padding:
                          const pw.EdgeInsets.only(left: 10, top: 5, bottom: 5),
                      margin: const pw.EdgeInsets.only(left: 5),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: widgetChildren(e, Style()),
                      ),
                    ),
                  ])
            ]);
          case "h1":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 24)));
          case "h2":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 22)));
          case "h3":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 20)));
          case "h4":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 18)));
          case "h5":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 16)));
          case "h6":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 14)));
          case "pre":
            return Chunk(widget: [
              pw.Container(
                  child: pw.Row(
                      children:
                          widgetChildren(e, Style(font: pw.Font.courier()))),
                  padding: pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                      color: PdfColors.grey200))
            ]);
          case "body":
            return Chunk(widget: widgetChildren(e, Style()));
          //Create a table with the rows stored in rowChildren
          case "table":
            var ch = <pw.TableRow>[];
            var cellfill = PdfColors.white;
            var border = pw.Border.all(width: 1, color: PdfColors.white);
            addRows(Node e, Style s) {
              for (var r in e.nodes) {
                var cl = <pw.Widget>[];
                for (var c in r.nodes) {
                  var ws = widgetChildren(c, Style());
                  var align = pw.CrossAxisAlignment.start;
                  if (c.attributes["style"] != null) {
                    if (c.attributes["style"] == "text-align: right;") {
                      align = pw.CrossAxisAlignment.end;
                    } else if (c.attributes["style"] == "text-align: center;") {
                      align = pw.CrossAxisAlignment.center;
                    } else if (c.attributes["style"] == "text-align: left;") {
                      align = pw.CrossAxisAlignment.start;
                    }
                  }
                  c as Element;
                  if (c.localName == "th") {
                    cellfill = PdfColors.grey300;
                    border = pw.Border(
                        bottom: pw.BorderSide(width: 2),
                        top: pw.BorderSide(color: PdfColors.white));
                    ws = widgetChildren(
                        c,
                        Style(
                          weight: pw.FontWeight.bold,
                        ));
                  } else {
                    cellfill = PdfColors.white;
                    border = pw.Border.all(width: 0, color: PdfColors.white);
                  }
                  cl.add(pw.Column(children: ws, crossAxisAlignment: align));
                }
                ch.add(pw.TableRow(
                    children: cl,
                    decoration:
                        pw.BoxDecoration(color: cellfill, border: border)));
              }
            }
            addRows(e.nodes[0], Style(weight: pw.FontWeight.bold));
            addRows(e.nodes[1], Style());
            return Chunk(widget: [pw.Table(children: ch)]);
          // case "img":
          //   var imageBody = getImage(e.attributes["src"]);
          //   var imageRender = pw.MemoryImage(imageBody);
          //   return Chunk(widget: [pw.Image(imageRender)]);
          case "p":
            return Chunk(widget: widgetChildren(e, Style()));
          default:
            print("${e.localName} is unknown");
            return Chunk(widget: widgetChildren(e, Style()));
        }
      case Node.ENTITY_NODE:
      case Node.ENTITY_REFERENCE_NODE:
      case Node.NOTATION_NODE:
      case Node.PROCESSING_INSTRUCTION_NODE:
      case Node.ATTRIBUTE_NODE:
      case Node.CDATA_SECTION_NODE:
      case Node.COMMENT_NODE:
      case Node.DOCUMENT_FRAGMENT_NODE:
      case Node.DOCUMENT_NODE:
      case Node.DOCUMENT_TYPE_NODE:
        print("${e.nodeType} is unknown node type");
    }
    return Chunk();
  }
}

mdtopdf(String path, String out) async {
  print(Directory.current);
  final md2 = await File(path).readAsString();
  var htmlx = md.markdownToHtml(md2,
      inlineSyntaxes: [md.InlineHtmlSyntax()],
      blockSyntaxes: [
        const md.TableSyntax(),
        md.FencedCodeBlockSyntax(),
        md.HeaderWithIdSyntax(),
        md.SetextHeaderWithIdSyntax(),
      ],
      extensionSet: md.ExtensionSet.gitHubWeb);
  File("$out.html").writeAsString(htmlx);
  var document = parse(htmlx);
  if (document.body == null) {
    return;
  }
  Chunk ch = Styler().format(document.body!);
  var doc = pw.Document();
  doc.addPage(pw.MultiPage(build: (context) => ch.widget ?? []));
  File(out).writeAsBytes(await doc.save());
}
