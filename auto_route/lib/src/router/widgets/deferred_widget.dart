import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

part 'deferred_loading_placeholder.dart';

/// Signature for a function that returns a void future
/// Used in [DeferredWidget] to load deferred libraries
typedef LibraryLoader = Future<void> Function();

/// Signature for a function that returns a widget
/// Used in [DeferredWidget] to build the lazy-loaded library
typedef DeferredWidgetBuilder = Widget Function();

/// Wraps the child inside a deferred module loader.
///
/// The child is created and a single instance of the Widget is maintained in
/// state as long as closure to create widget stays the same.
class DeferredWidget extends StatefulWidget {
  /// default constructor
  const new(
    this.libraryLoader,
    this.createWidget, {
    super.key,
    this.placeholder,
  });

  /// Triggers the deferred library loading process
  final LibraryLoader libraryLoader;

  /// Creates the actual widget after it's loaded
  final DeferredWidgetBuilder createWidget;

  /// The widget is displayed until [libraryLoader] is done loading.
  ///
  /// Left out, the router's placeholder ([AutoRouterDelegate.placeholder])
  /// shows, or a progress indicator.
  final Widget? placeholder;
  static final Map<LibraryLoader, Future<void>> _moduleLoaders = {};
  static final Set<LibraryLoader> _loadedModules = {};

  static Future<void> _preload(LibraryLoader loader) {
    return _moduleLoaders[loader] ??= _load(loader);
  }

  static Future<void> _load(LibraryLoader loader) async {
    try {
      await loader();
    } on Object {
      // A load that failed, as when the network drops on the web, is tried
      // again by the next page that needs it: loadLibrary() may be called
      // again after a failure. The future taken out is this load's own.
      unawaited(_moduleLoaders.remove(loader));
      rethrow;
    }
    _loadedModules.add(loader);
  }

  @override
  State<DeferredWidget> createState() => _DeferredWidgetState();
}

class _DeferredWidgetState extends State<DeferredWidget> {
  new();

  Widget? _loadedChild;
  DeferredWidgetBuilder? _loadedBuilder;

  @override
  void initState() {
    super.initState();

    /// If module was already loaded immediately create widget instead of
    /// waiting for future or zone turn.
    if (DeferredWidget._loadedModules.contains(widget.libraryLoader)) {
      _createLoadedChild();
    } else {
      unawaited(
        DeferredWidget._preload(widget.libraryLoader).then(
          (_) {
            // The page can leave the tree before its library loads.
            if (mounted) setState(_createLoadedChild);
          },
          // Reported as Flutter reports an image that fails to load; the
          // placeholder stays, and the next visit loads the library again.
          onError: (Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'auto_route',
                context: ErrorDescription(
                  'while loading the deferred library of a page',
                ),
              ),
            );
          },
        ),
      );
    }
  }

  void _createLoadedChild() {
    _loadedBuilder = widget.createWidget;
    _loadedChild = _loadedBuilder!();
  }

  @override
  Widget build(BuildContext context) {
    /// If closure to create widget changed, create new instance, otherwise
    /// treat as const Widget.
    if (_loadedBuilder != widget.createWidget && _loadedBuilder != null) {
      _loadedBuilder = widget.createWidget;
      _loadedChild = _loadedBuilder!();
    }

    return _loadedChild ??
        widget.placeholder ??
        AutoRouterDelegate.of(context).placeholder?.call(context) ??
        const DeferredLoadingPlaceholder();
  }
}
