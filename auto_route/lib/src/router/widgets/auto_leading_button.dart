import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Signature function to customize the
/// build of a leading button
typedef AutoLeadingButtonBuilder = Widget Function(
  BuildContext context,
  LeadingType leadingType,
  VoidCallback? action, // could be popTop, openDrawer or null
);

/// Signature function to provide nullable leading widget
/// based on the current router state
typedef NullableWidgetBuilder = Widget Function(
  BuildContext context,
  Widget? leading,
);

/// An AutoRoute replacement of appBar aut-leading-button
///
/// Unlike the default [BackButton] this button will always
/// the top-most route in the whole hierarchy not only current-stack
///
/// meant to be used with AppBar -> AppBar(leading: AutoLeadingButton())
///
/// e.g if we have such hierarchy
/// - page1
/// - page2
///     - sub-page1
///     - sub-page2
/// and Page2 has an AutoLeadingButton(), clicking
/// it will pop sub-page2 then page2
///
class AutoLeadingButton extends StatefulWidget {
  /// Default constructor
  const new({
    super.key,
    this.color,
    bool? showIfParentCanPop,
    this.showIfChildCanPop = true,
    this.ignorePagelessRoutes = false,
    this.builder,
  }) : assert(
         color == null || builder == null,
         'Pass either color or builder, not both.',
       ),
       _nullableBuilder = null,
       _shouldShowIfParentCanPop = showIfParentCanPop ?? true;

  /// builds a nullable leading widget based on the current router state
  ///
  /// This meant to be used above the AppBar so the `leading` property
  /// is passed to the AppBar's leading property,
  ///
  /// e.g
  /// ```dart
  ///
  ///    AutoLeadingButton.builder(
  ///    builder: (context, leading) {
  ///     return AppBar(
  ///            leading: leading,
  ///            title: Text('My Page'),
  ///            ),
  ///        ..
  ///         ),
  ///     ),
  const new builder({
    required NullableWidgetBuilder builder,
    super.key,
    this.color,
    bool? showIfParentCanPop,
    this.showIfChildCanPop = true,
    this.ignorePagelessRoutes = false,
  }) : _nullableBuilder = builder,
       builder = null,
       _shouldShowIfParentCanPop = showIfParentCanPop ?? true;

  /// The color of [BackButton] and [CloseButton]
  final Color? color;

  /// Whether to pop current stack and not care about
  /// child routes
  final bool showIfChildCanPop;

  /// Whether to ignore pageless routes when
  /// calculating top-most route
  ///
  /// What is a (PagelessRoute)?
  /// [Route] that does not correspond to a [Page] object is called a pageless
  /// route and is tied to the [Route] that _does_ correspond to a [Page] object
  /// that is below it in the history.
  final bool ignorePagelessRoutes;
  final bool _shouldShowIfParentCanPop;

  /// Clients can use this builder to customize
  /// the looks and feels of their leading buttons
  ///
  /// It is told the [LeadingType] the default button would show:
  /// [LeadingType.drawer] on a page whose [Scaffold] has a drawer, otherwise
  /// [LeadingType.back] or [LeadingType.close] when the router can pop.
  final AutoLeadingButtonBuilder? builder;

  final NullableWidgetBuilder? _nullableBuilder;

  @override
  State<AutoLeadingButton> createState() => _AutoLeadingButtonState();
}

class _AutoLeadingButtonState extends State<AutoLeadingButton> {
  late final PagelessRoutesObserver _pagelessRoutesObserver;

  // Tells the button of each change that can change what canPop says.
  final _changes = _ChangeRelay();

  @override
  void initState() {
    super.initState();
    _pagelessRoutesObserver = AutoRouter.of(context).pagelessRoutesObserver;
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  // [router] and the pageless routes observers of it and of every router
  // nested in it.
  static Iterable<Listenable> _listenablesOf(RoutingController router) sync* {
    yield router;
    if (router is StackRouter) yield router.pagelessRoutesObserver;
    for (final child in router.childControllers) {
      yield* _listenablesOf(child);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = RouterScope.of(context, watch: true);
    return ListenableBuilder(
      listenable: _changes,
      builder: (leadingContext, _) => _buildLeading(leadingContext, scope),
    );
  }

  Widget _buildLeading(BuildContext context, RouterScope scope) {
    // canPop also reads the routers nested in the page and the routers
    // around it. The button rebuilds when the pages of any router change, as
    // each change reaches the root router, and when a pageless route, such
    // as a dialog or a page opened with pushWidget, opens or closes in any
    // stack router. The routers are found again on each build, as they come
    // and go with their pages. The root is found through the app's Router,
    // so a button built around a stand-in router, as in a widget test, reads
    // nothing more of it.
    _changes.listenTo({
      _pagelessRoutesObserver,
      if (Router.maybeOf(context)?.routerDelegate
          case final AutoRouterDelegate delegate)
        ..._listenablesOf(delegate.controller),
    });
    Widget? leading;
    // A page with a drawer gets the drawer button, and the back button only
    // otherwise, as Flutter's AppBar chooses its leading widget.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.hasDrawer == true) {
      if (widget.builder != null) {
        return widget.builder!(context, .drawer, _handleDrawerButton);
      }
      leading = IconButton(
        key: const ValueKey(LeadingType.drawer),
        icon: const Icon(Icons.menu),
        iconSize: Theme.of(context).iconTheme.size ?? 24,
        onPressed: _handleDrawerButton,
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      );
    } else if (scope.controller.canPop(
      ignoreChildRoutes: !widget.showIfChildCanPop,
      ignoreParentRoutes: !widget._shouldShowIfParentCanPop,
      ignorePagelessRoutes: widget.ignorePagelessRoutes,
    )) {
      final topPage = scope.controller.topPage;
      final shouldUseCloseButton = topPage?.fullscreenDialog ?? false;
      if (widget.builder != null) {
        return widget.builder!(
          context,
          shouldUseCloseButton ? .close : .back,
          () => unawaited(scope.controller.maybePopTop()),
        );
      }
      leading = shouldUseCloseButton
          ? CloseButton(
              key: const ValueKey(LeadingType.close),
              color: widget.color,
              onPressed: () => unawaited(scope.controller.maybePopTop()),
            )
          : BackButton(
              key: const ValueKey(LeadingType.back),
              color: widget.color,
              onPressed: () => unawaited(scope.controller.maybePopTop()),
            );
    }

    if (widget.builder != null) {
      return widget.builder!(context, .noLeading, null);
    }
    if (widget._nullableBuilder != null) {
      return widget._nullableBuilder!(context, leading);
    }
    return leading ??
        const SizedBox.shrink(key: ValueKey(LeadingType.noLeading));
  }

  void _handleDrawerButton() {
    Scaffold.of(context).openDrawer();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<AutoLeadingButtonBuilder?>(
          'builder',
          widget.builder,
        ),
      )
      ..add(
        DiagnosticsProperty<NullableWidgetBuilder?>(
          'nullableBuilder',
          widget._nullableBuilder,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'showIfChildCanPop',
          widget.showIfChildCanPop,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'ignorePagelessRoutes',
          widget.ignorePagelessRoutes,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'showIfParentCanPop',
          widget._shouldShowIfParentCanPop,
        ),
      )
      ..add(DiagnosticsProperty<Color?>('color', widget.color))
      ..add(DiagnosticsProperty<RouterScope>('scope', RouterScope.of(context)))
      ..add(
        DiagnosticsProperty<PagelessRoutesObserver>(
          'pagelessRoutesObserver',
          _pagelessRoutesObserver,
        ),
      );
  }
}

/// AppBar Leading button types
enum LeadingType {
  /// Whether to show a back button
  back,

  /// Whether to show a close button
  close,

  /// Whether to show a drawer toggle
  drawer,

  /// Whether to show no leading at all
  noLeading;

  /// Helper to check if this instance is [back]
  bool get isBack => this == back;

  /// Helper to check if this instance is [close]
  bool get isClose => this == close;

  /// Helper to check if this instance is [drawer]
  bool get isDrawer => this == drawer;

  /// Helper to check if this instance is [noLeading]
  bool get isNoLeading => this == noLeading;
}

// Tells its listeners of a change in any of the listenables it listens to.
// A navigator can report a change while the app builds, when a widget
// outside that navigator can't be marked to build again: such a change is
// told after the frame.
class _ChangeRelay extends ChangeNotifier {
  final _sources = <Listenable>{};
  bool _isDisposed = false;

  // Listens to [sources] from now on, and no longer to the others.
  void listenTo(Set<Listenable> sources) {
    for (final gone in _sources.difference(sources)) {
      gone.removeListener(_relay);
    }
    for (final added in sources.difference(_sources)) {
      added.addListener(_relay);
    }
    _sources
      ..clear()
      ..addAll(sources);
  }

  void _relay() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == .persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final source in _sources) {
      source.removeListener(_relay);
    }
    _sources.clear();
    super.dispose();
  }
}
