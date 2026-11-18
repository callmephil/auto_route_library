import 'package:test/test.dart';

import 'support/generate.dart';

String _page(String name, {required String import, String fields = ''}) =>
    '''
import 'package:auto_route/auto_route.dart';
import '$import';

@RoutePage()
class $name extends StatelessWidget {
  const $name({super.key, required this.onDone, this.child$fields});

  final VoidCallback onDone;
  final Widget? child;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''';

void main() {
  // #2345: Flutter 3.50.0 deprecates the material and cupertino libraries of
  // package:flutter in favor of the material_ui and cupertino_ui packages.
  // Steps: a page that imports Flutter's material library takes a Key, a
  // VoidCallback and a Widget, and the router is built. The router imported
  // the material library for those types, and an app analyzing it got
  // deprecated_member_use, which the router's `type=lint` ignore does not
  // silence. The router must name each type through a library that is not
  // deprecated whenever one exports it, and through the app's own material_ui
  // when the page uses it.
  group('deprecated Flutter libraries in the generated router (#2345)', () {
    test('a page on package:flutter/material.dart gets widgets.dart', () async {
      final result = await generateRouter({
        'lib/home_page.dart': _page(
          'HomePage',
          import: 'package:flutter/material.dart',
        ),
      });
      expect(result.errors, isEmpty);
      expect(result.compileErrors, isEmpty);
      expect(result.source, isNot(contains('package:flutter/material.dart')));
      expect(
        result.source,
        contains("import 'package:flutter/widgets.dart' as _i3;"),
      );
      expect(result.source, contains('required _i3.VoidCallback onDone'));
      expect(result.source, contains('_i3.Widget? child'));
    });

    test(
      'a page on package:flutter/cupertino.dart gets widgets.dart',
      () async {
        final result = await generateRouter({
          'lib/home_page.dart': _page(
            'HomePage',
            import: 'package:flutter/cupertino.dart',
          ),
        });
        expect(result.errors, isEmpty);
        expect(result.compileErrors, isEmpty);
        expect(
          result.source,
          isNot(contains('package:flutter/cupertino.dart')),
        );
        expect(
          result.source,
          contains("import 'package:flutter/widgets.dart' as _i3;"),
        );
      },
    );

    test('a page on material_ui keeps the package it imports', () async {
      final result = await generateRouter({
        'lib/home_page.dart': _page(
          'HomePage',
          import: 'package:material_ui/material_ui.dart',
        ),
      });
      expect(result.errors, isEmpty);
      expect(result.compileErrors, isEmpty);
      expect(result.source, isNot(contains('package:flutter/material.dart')));
      expect(
        result.source,
        contains("import 'package:material_ui/material_ui.dart' as _i3;"),
      );
    });

    test(
      'a type only a deprecated library exports still comes from it',
      () async {
        // ThemeData of Flutter's built-in Material is public only through
        // package:flutter/material.dart. The file under package:flutter/src/
        // that declares it may move in any Flutter release, so the router
        // keeps the deprecated library here.
        final result = await generateRouter({
          'lib/home_page.dart':
              _page(
                'HomePage',
                import: 'package:flutter/material.dart',
                fields: ', required this.theme',
              ).replaceFirst(
                'final Widget? child;',
                'final Widget? child;\n  final ThemeData theme;',
              ),
        });
        expect(result.errors, isEmpty);
        expect(result.compileErrors, isEmpty);
        expect(result.source, contains('package:flutter/material.dart'));
        expect(result.source, isNot(contains('package:flutter/src/')));
      },
    );
  });
}
