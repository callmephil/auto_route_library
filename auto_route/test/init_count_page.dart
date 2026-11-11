import 'package:material_ui/material_ui.dart';

/// A page that shows [label] and calls [onInit] from its initState, so a test
/// counts how often the page is built anew.
class InitCountPage extends StatefulWidget {
  /// Calls [onInit] once per state.
  const new(this.onInit, {this.label = 'Home', super.key});

  /// Called from initState.
  final VoidCallback onInit;

  /// The text the page shows.
  final String label;

  @override
  State<InitCountPage> createState() => _InitCountPageState();
}

class _InitCountPageState extends State<InitCountPage> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(widget.label));
}
