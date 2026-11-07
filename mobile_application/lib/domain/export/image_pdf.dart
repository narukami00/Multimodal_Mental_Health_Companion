import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A one-page PDF that is a picture of the page, written by hand so no package is needed.
///
/// [rgb] is 8-bit RGB, three bytes per pixel, row by row from the top. The picture fills an A4 page. The text on it is
/// part of the picture rather than selectable, which is what lets any language print correctly.
Uint8List imagePdf({
  required Uint8List rgb,
  required int width,
  required int height,
  double pageWidth = 595.28,
  double pageHeight = 841.89,
}) {
  assert(rgb.length == width * height * 3, 'rgb must be width x height x 3 bytes');
  final pixels = Uint8List.fromList(ZLibEncoder().convert(rgb));
  final out = BytesBuilder();
  final offsets = <int>[];

  void write(String s) => out.add(latin1.encode(s));
  void object(int number, String head, {Uint8List? stream}) {
    offsets.add(out.length);
    write('$number 0 obj\n$head');
    if (stream != null) {
      write('\nstream\n');
      out.add(stream);
      write('\nendstream');
    }
    write('\nendobj\n');
  }

  write('%PDF-1.4\n');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  object(
    3,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $pageHeight] '
    '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>',
  );
  final draw = latin1.encode('q $pageWidth 0 0 $pageHeight 0 0 cm /Im0 Do Q');
  object(4, '<< /Length ${draw.length} >>', stream: Uint8List.fromList(draw));
  object(
    5,
    '<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB '
    '/BitsPerComponent 8 /Filter /FlateDecode /Length ${pixels.length} >>',
    stream: pixels,
  );

  final xref = out.length;
  write('xref\n0 6\n0000000000 65535 f \n');
  for (final o in offsets) {
    write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toBytes();
}
