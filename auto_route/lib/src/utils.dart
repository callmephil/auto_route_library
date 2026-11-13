import 'dart:convert';

/// A utility to re-case a string to kabab-case
String toKebabCase(String s) {
  // Both groups of the pattern take part in every match, so neither is null.
  return s.replaceAllMapped(
    RegExp('(.+?)([A-Z])'),
    (match) => '${match.group(1)!}-${match.group(2)!}'.toLowerCase(),
  );
}

const _lossyUtf8 = Utf8Codec(allowMalformed: true);

/// Decodes the percent-escapes of [encoded], one component of a url's path,
/// as [Uri.decodeComponent] does, except that bytes that aren't valid UTF-8
/// become U+FFFD instead of throwing, as the URL standard reads them.
///
/// A '+' stays a '+'. Text without a '%' is returned as it is, since it has
/// nothing to decode; the matcher calls this on every segment it compares.
String decodeUrlComponent(String encoded) {
  if (!encoded.contains('%')) return encoded;
  return Uri.decodeQueryComponent(
    encoded.replaceAll('+', '%2B'),
    encoding: _lossyUtf8,
  );
}

/// The query params of [uri], every value of each key, as
/// [Uri.queryParametersAll] gives them, except that bytes that aren't valid
/// UTF-8 become U+FFFD instead of throwing, as the URL standard reads them.
Map<String, List<String>> queryParametersAllOf(Uri uri) {
  try {
    return uri.queryParametersAll;
  } on FormatException {
    final params = <String, List<String>>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final [key, ...value] = pair.split('=');
      (params[Uri.decodeQueryComponent(key, encoding: _lossyUtf8)] ??= []).add(
        Uri.decodeQueryComponent(value.join('='), encoding: _lossyUtf8),
      );
    }
    return params;
  }
}
