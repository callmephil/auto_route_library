import 'dart:convert';

/// A utility to re-case a string to kabab-case
///
/// A name with capitals in a row keeps some of them: 'TVRoute' gives
/// 't-vRoute' and 'HTTPRoute' gives 'h-tt-pRoute'. The default paths of
/// routes come from this, so it stays as it is: changing it would change
/// their urls.
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
/// [Uri.queryParametersAll] gives them, except that an empty value is left
/// out, and a key left with none with it, and that bytes that aren't valid
/// UTF-8 become U+FFFD instead of throwing, as the URL standard reads them.
///
/// `?b=`, a bare `?c` and the second `tag` of `?tag=a&tag=` read as absent,
/// as [withoutEmptyQueryValues] reads them in a route pushed in code: the url
/// the router writes leaves them out, so a page reads the same before and
/// after a reload.
Map<String, List<String>> queryParametersAllOf(Uri uri) => {
  for (final MapEntry(:key, :value) in _queryParametersAll(uri).entries)
    if (value.any((each) => each.isNotEmpty))
      key: [
        for (final each in value)
          if (each.isNotEmpty) each,
      ],
};

Map<String, List<String>> _queryParametersAll(Uri uri) {
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

/// [params] without its empty query values: a value that is `null` or an
/// empty text, and such an entry in a list of values. A key left with no
/// value is left out, and a list keeps its own type when nothing is taken
/// out of it.
///
/// The router writes no such value into a url, and reads none from one
/// ([queryParametersAllOf]), so a route pushed in code reads what a reload
/// of its url reads.
Map<String, Object?> withoutEmptyQueryValues(Map<String, Object?> params) {
  bool isEmpty(Object? value) => value == null || value == '';
  final kept = <String, Object?>{};
  for (final MapEntry(:key, :value) in params.entries) {
    if (value is Iterable<Object?> && value.any(isEmpty)) {
      final values = [
        for (final each in value)
          if (!isEmpty(each)) each,
      ];
      if (values.isNotEmpty) kept[key] = values;
    } else if (!isEmpty(value)) {
      kept[key] = value;
    }
  }
  return kept;
}
