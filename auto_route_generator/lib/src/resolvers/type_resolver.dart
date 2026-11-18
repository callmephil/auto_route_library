import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart'
    show DartType, FunctionType, ParameterizedType, RecordType;
import 'package:auto_route_generator/dart_type_x.dart';
import 'package:auto_route_generator/src/models/resolved_type.dart';

const _kUnPreferredImports = {'dart:ui'};

/// A Helper class that resolves types
class TypeResolver {
  /// Default constructor
  const new(this._libs);

  /// The list of resolved libraries in `BuildStep`
  final List<LibraryElement> _libs;

  /// Resolved the import path of the given [element]
  String? resolveImport(Element? element) {
    // return early if source is null or element is a core type
    if (_libs.isEmpty ||
        element?.library?.uri == null ||
        _isCoreDartType(element!)) {
      return null;
    }

    // A type of the Dart SDK is imported from the library that declares it.
    // Another SDK library may export it too, as dart:html does `Point`, which
    // dart:math declares, and the first library found must not win.
    final declaring = element.library!.uri;
    if (declaring.scheme == 'dart' &&
        !declaring.path.startsWith('_') &&
        !_kUnPreferredImports.contains(declaring.toString())) {
      return declaring.toString();
    }

    // A library the app may not reach the type by is used only when no other
    // library exports it. A deprecated one, such as
    // package:flutter/material.dart on Flutter 3.50.0, makes the analyzer
    // report deprecated_member_use in the generated router, which `type=lint`
    // does not silence (#2345), and an implementation library under `src/`
    // may change in any release of its package, so it comes last.
    final fallBackImports = <String>[];
    final implementationImports = <String>[];
    for (final lib in _libs) {
      if (!_isCoreDartType(lib) &&
          lib.exportNamespace.definedNames2.values.contains(element)) {
        final uri = lib.uri;
        final import = uri.scheme == 'asset'
            ? _assetToPackage(uri)
            : uri.toString();
        if (_kUnPreferredImports.contains(import) ||
            lib.metadata.hasDeprecated) {
          fallBackImports.add(import);
        } else if (_isImplementationLibrary(uri)) {
          implementationImports.add(import);
        } else {
          return import;
        }
      }
    }
    return fallBackImports.firstOrNull ?? implementationImports.firstOrNull;
  }

  /// Whether [uri] is a library under a package's `lib/src/`.
  bool _isImplementationLibrary(Uri uri) =>
      uri.scheme == 'package' && uri.pathSegments.elementAtOrNull(1) == 'src';

  String _assetToPackage(Uri uri) {
    if (uri.scheme == 'asset') {
      final segments = uri.pathSegments;
      final libIndex = segments.indexOf('lib');
      if (libIndex > 0 && libIndex + 1 < segments.length) {
        final validSegments = [
          ...segments.sublist(libIndex - 1, libIndex),
          ...segments.sublist(libIndex + 1),
        ];
        return 'package:${validSegments.join('/')}';
      }
    }
    return uri.toString();
  }

  bool _isCoreDartType(Element element) {
    return element.library?.uri.toString() == 'dart:core';
  }

  List<ResolvedType> _resolveTypeArguments(DartType typeToCheck) {
    final types = <ResolvedType>[];
    if (typeToCheck is RecordType) {
      for (final recordField in typeToCheck.positionalFields) {
        types.add(_resolveNestedType(recordField.type));
      }
      for (final recordField in typeToCheck.namedFields) {
        types.add(
          _resolveNestedType(recordField.type, nameInRecord: recordField.name),
        );
      }
    } else if (typeToCheck is ParameterizedType) {
      for (final type in typeToCheck.typeArguments) {
        types.add(_resolveNestedType(type));
      }
    }
    return types;
  }

  /// Resolves a type argument or a record field, which may be a record or a
  /// function type itself.
  ResolvedType _resolveNestedType(DartType type, {String? nameInRecord}) {
    if (type is FunctionType && type.alias == null) {
      return ResolvedType.function(
        parts: FunctionTypeParts(
          returnType: _resolveNestedType(type.returnType),
          requiredParameters: [
            for (final p in type.formalParameters.where(
              (parameter) => parameter.isRequiredPositional,
            ))
              _resolveNestedType(p.type),
          ],
          optionalParameters: [
            for (final p in type.formalParameters.where(
              (parameter) => parameter.isOptionalPositional,
            ))
              _resolveNestedType(p.type),
          ],
          namedParameters: {
            for (final p in type.formalParameters.where(
              (parameter) => parameter.isOptionalNamed,
            ))
              p.name!: _resolveNestedType(p.type),
          },
          namedRequiredParameters: {
            for (final p in type.formalParameters.where(
              (parameter) => parameter.isRequiredNamed,
            ))
              p.name!: _resolveNestedType(p.type),
          },
        ),
        isNullable: type.nullabilitySuffix == .question,
        nameInRecord: nameInRecord,
      );
    } else if (type is FunctionType) {
      final alias = type.alias!;
      return ResolvedType(
        name: alias.element.displayName,
        import: resolveImport(alias.element),
        isNullable: type.nullabilitySuffix == .question,
        typeArguments: alias.typeArguments.map(resolveType).toList(),
        nameInRecord: nameInRecord,
      );
    } else if (type is RecordType) {
      return ResolvedType.record(
        name: type.nameWithoutSuffix,
        import: resolveImport(type.element),
        isNullable: type.nullabilitySuffix == .question,
        typeArguments: _resolveTypeArguments(type),
        nameInRecord: nameInRecord,
      );
    } else if (type.element case final TypeParameterElement element) {
      // A type parameter of the page class is one the route declares too.
      // Any other, such as a generic function's, has no name there.
      if (element.enclosingElement is! InterfaceElement) {
        return ResolvedType(name: 'dynamic', nameInRecord: nameInRecord);
      }
      return ResolvedType(
        name: element.displayName,
        isNullable: type.nullabilitySuffix == .question,
        nameInRecord: nameInRecord,
      );
    }
    return ResolvedType(
      name: type.element?.displayName ?? 'void',
      import: resolveImport(type.element),
      isNullable: type.nullabilitySuffix == .question,
      typeArguments: _resolveTypeArguments(type),
      nameInRecord: nameInRecord,
      isEnum: type.element is EnumElement,
    );
  }

  /// Resolves the given [type] to a [ResolvedType]
  ///
  /// A type named by a typedef resolves to the typedef, unless
  /// [shouldSkipAlias] is true: then it resolves to the type the typedef
  /// stands for.
  ResolvedType resolveType(DartType type, {bool shouldSkipAlias = false}) {
    final alias = shouldSkipAlias ? null : type.alias;
    final effectiveElement = alias?.element ?? type.element;
    final import = resolveImport(effectiveElement);
    final typeArgs = <ResolvedType>[];
    if (alias != null) {
      typeArgs.addAll(alias.typeArguments.map(resolveType));
    } else {
      typeArgs.addAll(_resolveTypeArguments(type));
    }
    if (type is RecordType && alias == null) {
      return ResolvedType.record(
        name: effectiveElement?.displayName ?? 'void',
        import: import,
        isNullable: type.nullabilitySuffix == .question,
        typeArguments: typeArgs,
      );
    }

    return ResolvedType(
      name: effectiveElement?.displayName ?? type.nameWithoutSuffix,
      isNullable: type.nullabilitySuffix == .question,
      import: import,
      typeArguments: typeArgs,
      isEnum: effectiveElement is EnumElement,
    );
  }
}
