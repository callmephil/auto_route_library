import 'package:material_ui/material_ui.dart';

/// A page that counts its taps and shows its name and the count, such as
/// 'Form 2', so a test tells whether the page kept its State.
class TapCountPage extends StatefulWidget {
  /// Shows [name] with the count of taps, 0 at first.
  const new(this.name, {super.key});

  /// The text the page shows before its count.
  final String name;

  @override
  State<TapCountPage> createState() => _TapCountPageState();
}

class _TapCountPageState extends State<TapCountPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('${widget.name} $_count'),
      ),
    ),
  );
}
