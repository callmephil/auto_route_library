## 13.0.0-rc.1
- **FIX**: on the web, an app opened at a link into a tabs page with `includePrefixMatches: true` keeps the one browser
  entry the browser made for the link when the tabs show their first tab in its place: while the guard of the tab the
  link names decides, after that guard's "no", or when the link names no tab. Before, Home, which the prefix match
  opens under the tabs page, got an entry of its own, and the back button showed it.
- **FIX**: on the web, the browser's back and forward buttons after a tab change go through each page once, also when
  the guard of the tab they go back into waits, such as a sign-in check that reads a token, and when a guard of the
  page in that tab waits too. A second press while the guard still decides shows the page of the entry the browser
  stands on. Before, the app wrote the url of the tab on screen over the entry of the page in that tab while the guard
  decided: the next presses showed that tab again and moved the browser forward, and the page in the guarded tab was
  lost. A link into such a tab now waits for the guard on every platform: off the web, the app's own history keeps the
  link's entry while the guard decides, and a tab guard that fails after a wait reports its error, which was dropped.
- **FIX**: two links that bring only their own page (on the web by default, and off the web with
  `includePrefixMatches: false`) into a page that is not open, whose nested guard is slow and turns both down, leave
  the user where they were. Before, the page stayed open on its first nested page, at its own url.
- **FIX**, **BEHAVIOR CHANGE**: a guard's "no" inside a new page that holds an `AutoTabsRouter`, or that builds its
  nested router in a `DeferredWidget`, takes that page back, as for a page with a plain nested `AutoRouter`. This
  holds for the tab's own guard and for a guard in the tab's nested router, after `navigate`, `navigatePath` or a link:
  the stack, the url and the open dialogs are as before, and `onFailure` hears the rejection. Before, the page stayed
  on its first tab or first page, a link closed the pages it would close once let in, and the dialogs closed.
- **FIX**: after a link, `navigate` or `navigatePath` into the nested router or tabs of an open page is turned down,
  as by a guard's "no" there or a tab the app removed, the route data of that page keeps its route, query, fragment
  and children. Before, `router.current.queryParams` and the page's `route.children` named the refused navigation,
  also after the user selected another tab.
- **FIX**, **BEHAVIOR CHANGE**: `navigate` and `navigatePath` into the nested router of a tab answer as the page they
  reach there does, as into the nested router of a stack page: after a guard's "no" there, once it has answered; after a
  "yes", once that page closes. Before, they answered as the tab changed, while the guard still decided. Code after an
  `await` of such a call now runs only then; call it without `await` to go on at once. A tab whose own guard makes the
  change wait still answers once the change has started.
- **FIX**, **BEHAVIOR CHANGE**: off the web, while the guard of a link decides, `currentUrl`, `urlState` and the url
  reported to the platform name the page on screen, not the link's page. The link's url comes in with its page, and
  after a "no" it never changed. Before, they named the link from the start, and went back after a "no".
- **FIX**: when a guard rejects its page on `reevaluateGuards()`, the pages above that page, which leave with it,
  report `RouteLeaveKind.removed` to their `AutoRouteLeaveListener`, as the rejected page and a page held for its
  guard do. Before, the top page reported `popped`.
- **FIX**: `await reevaluateGuards()` completes with the error that the guard of a page held off the screen for it
  throws when asked again, as it already did for the guard of a page on the stack. The error no longer also reaches
  the zone as an uncaught error, and the router works on after it. Before, the app's `catch` got nothing.
- **FIX**, **BEHAVIOR CHANGE**: each call of a guard gets a `NavigationResolver` of its own when
  `reevaluateGuards()` calls the guard again before it has answered. A guard that keeps one callback per call, and
  answers each once, no longer fails the assert "Make sure `resolver.next()` is only called once." (in a release
  build, a `StateError`). Only the answer of the latest call decides; a later answer from an earlier call is ignored,
  a yes or a no. A call that waits on the user, behind its `redirectUntil` or on a page or dialog it showed, still
  answers from what the user does there. Before, every call got the same resolver.
- **FIX**: a sign-out closes the pages that need a session at once, also while the guard of a `push`, `replace`,
  `pushAll` or `navigate` awaits a request inside its call, and `reevaluateGuards()` no longer waits for that guard.
  The guard's yes from before the sign-out still opens nothing: it is asked again. A guard in a nested router that
  decides whether a page already on the screen above stays is still awaited. Before, the pages stayed on the screen,
  and `reevaluateGuards()` waited, until the request ended.
- **FIX**, **BEHAVIOR CHANGE**: a navigation that closes the pages over an open page, such as `navigatePath` into
  that page's nested router, also closes for good a page among them that is held off the screen for its guard, as
  after a sign-out. A later sign-in no longer opens that page again, and its caller gets `null` at the close. A held
  page that no navigation closed still comes back on its guard's yes.
- **FIX**: a tab held off the screen for its guard, as after a sign-out, leaves with its tabs page. Once the user
  closes the tabs page, no later change calls that tab's guard, and a later yes of the guard opens nothing. Before,
  each change called the guard again, for a tab that was gone.
- **FIX**: `replaceAll` ends the wait of a page held off the screen for its guard, as after a sign-out. The
  caller of that page's `push()` gets `null` at the `replaceAll`, no later change asks its guard again, and a
  later yes of the guard opens nothing. Before, the caller waited until the guard answered, maybe for good.
- **FIX**, **BEHAVIOR CHANGE**: off the web, `router.back()` returns through every open page, down to the first one,
  as the system back button does. The app's own history no longer keeps at most 21 entries: it keeps one entry for
  each open page. Before, after 30 pushes `back()` stopped after 20 steps with 11 pages open.
- **FIX**: off the web, `router.back()` to a page that is still open asks no guard of that page, as the system back
  button does. Before, a guard that took its time delayed `back()`, and a guard that asks the user asked again.
- **FIX**, **BEHAVIOR CHANGE**: `replace`, `replacePath` and `replaceAll` to a tabs page that is not open, with a tab that
  its `AutoTabsRouter` does not list, change nothing, as `push` does: the stack, the screen and the url stay as they
  were, and `onFailure` gets a `RouteNotFoundFailure`, or the call throws a `FlutterError` without it. Before, the page
  on top was gone, the tabs page showed its first tab, and without `onFailure` nothing was reported. The callers of the
  pages that left heard `null` already.
- **FIX**, **BEHAVIOR CHANGE**: `navigate` or `navigatePath` to a page that the tabs list of a nested `AutoTabsRouter`
  does not hold, into a tab never opened, ends with the tab that was on screen, its url and its history as before.
  `onFailure` gets a `RouteNotFoundFailure`; without it, the error is reported as an uncaught `FlutterError`, as the same
  call does after the tab opened once. The tab shows for one frame before it goes, since its tabs list exists only
  when the tab builds. Before, the call opened the tab on its first page, at its url, and reported nothing.
- **BEHAVIOR CHANGE**: auto_route no longer reads the page transitions of an app's theme from Flutter's built-in
  `MaterialApp` (`package:flutter/material.dart`), which Flutter 3.50.0 deprecates in favor of `material_ui`. Pages
  follow the `pageTransitionsTheme` of `material_ui`'s `Theme` only, so an app still on the built-in `MaterialApp` gets
  auto_route's default page transitions instead of its theme's (support added for #2340). Move the app to `material_ui`.
- **FIX**, **BEHAVIOR CHANGE**: an app that starts at a link its guard turns down, with no page of the app below it (as
  on the web, where a link opens alone), shows its first page, the one marked `initial` or at `/`, and its url, not an
  empty screen. A push meanwhile no longer becomes the only page. Before, the root had no page.
- **FIX**, **BEHAVIOR CHANGE**: the same holds when the app has global guards (`RootStackRouter.guards`) or its first
  page has a guard of its own. The guards of the first page are asked once, as for any navigation, and the app shows
  what they decide: the first page, or the page a guard redirects to, such as a login page. When they turn the first
  page down too and open no page, auto_route reports the error "The app launched with no page to show." in place of a
  silent empty screen. Before, such an app showed an empty screen.
- **BEHAVIOR CHANGE**: `auto_route` requires Flutter 3.50.0 (it allowed 3.47 and later). The package is tested and
  proven on 3.50.0 only, so an app on an older Flutter gets a pub error naming auto_route instead of untested code.
- **FIX**: on the web, the address bar shows each url encoded once on Flutter 3.50.0, such as `/caf%C3%A9` for
  `/café`, not `/caf%25C3%25A9`, so a refresh or a shared link opens the right page. Flutter 3.50.0's web engine no
  longer decodes the url it writes, so auto_route no longer escapes it a second time.
- **FIX**, **BEHAVIOR CHANGE**: on the web, after a reload, the browser's back and forward buttons onto the entries
  from before the reload show the page of each entry, as a link to its url does, in place of the pages open, as the
  browser itself does for such an entry. Before, each back opened its page over the pages open, so Home, Shoes, Runner
  X, a reload and two backs read Runner X, Shoes, Home, with a back arrow on Home; and the first forward press after
  them wrote over the browser's entries.
- **FIX**: off the web, a link to another tab of the tabs page on screen adds one step to `back()`, not three, so
  `back()` walks the tabs the user saw instead of going between the last two again.
- **FIX**: off the web, `back()` in an `AutoRouter.declarative` steps back through every page the app's list showed.
  Before, it stopped after one step, and with an `onNavigate` that sets the list to the routes it is given, it went
  back and forth between the last two pages.
- **FIX**, **BEHAVIOR CHANGE**: a guard's "no" inside a page that was not open no longer moves the user. A link,
  `navigatePath`, `navigate`, `pushPath` or `push` into such a page, whose nested router's guard rejects, takes the page
  back off: the stack, the url and the open dialogs are as before, the page's caller gets `null`, and a link's dialog
  stays open while the guard decides. The pages a link closes on its way in, such as one over Home when the link brings
  Home below the page, stay until the guard lets it in. Before, the page stayed on its first page, or blank when the
  guarded page was its only child, and a link's dialog closed. A page that is the only page of its router, as when the
  app starts at the link, stays, on its first page.
- **FIX**, **BEHAVIOR CHANGE**: the app's own `navigate` and `navigatePath` into a tab never opened, to pages a guard is
  asked about, build the tab off the screen and show it once the guard lets them in, as a link already did. A rejection
  keeps the tab the user is on; before, the tab switched and stayed on its first page, blank while a slow guard decided.
  With any global guard, in `RootStackRouter.guards`, such a call now shows the tab one frame later, even when that
  guard answers at once.
- **FIX**: a guard's rejection inside a page or tab that was not open reaches the `onFailure` of `navigatePath`,
  `navigate` and `pushPath` as a `RejectedByGuardFailure`, as their docs promise.
- **FIX**, **BEHAVIOR CHANGE**: pages pushed over an open page stay while a guard in that page's nested router decides
  about a link, `navigatePath` or `navigate` into it, and after it says no, with the dialog over them and their url.
  They close once it says yes, or first when it shows a page of its own, such as a sign-in page.
- **FIX**: an app started at a link its guard rejects, with the page a link brings below its own on screen, reports that
  page's url in `currentUrl`, `urlState` and to the Router, not the rejected link's.
- **FIX**: on the web, the browser's back button from a page that holds a nested router to a shell at '/' no longer
  writes a new entry, which lost the forward entry and made the next back seem to do nothing.
- **FIX**: `pushAndPopUntil` of a page whose nested guard says no takes the page back when its predicate removed
  nothing, as `push` does. When it removed pages, the page stays, on its first page or its router's placeholder, as
  after `replace` and `replaceAll`, whose docs now say so.
- **FIX**: `pushAll` with a page whose nested guard says no under its last page takes the whole batch back, and
  `onFailure` hears the rejection.
- **FIX**: the same navigation twice into a page whose nested guard decides no longer shows that page twice.
- **FIX**: off the web, `router.back()` and `context.back()` never show a page the app removed. After `removeLast`,
  `removeRoute`, `removeWhere`, `removeUntil`, `replaceAll` or `navigate` to a page underneath, in any stack, back()
  opened the removed page again, such as the sign-in page after a sign-in that ends in `replaceAll`, and a page removed
  from under the top came back over it. `navigationHistory.length` and `canNavigateBack` now count only the pages still
  open.
- **FIX**: off the web, `router.back()` and `context.back()` close one page per call after `pushAll` or a `replaceAll`
  of several pages, as Flutter's Navigator and the browser's back button do. The first back() closed every page opened
  together, or did nothing although pages were left under the top. Pages one link opened together still share its entry,
  as on the web. `navigationHistory.length` now counts one entry for each page the app opened together.
- **FIX**: off the web, `router.back()` never opens a page a platform link opened once the app has removed it, and a
  link to a page already open no longer leaves a first back() that does nothing. `navigationHistory.length` and
  `canNavigateBack` count the pages open right after a change, without waiting for the next url.
- **FIX**: off the web, `router.back()` closes one page per call after the app opens a page together with the pages of
  its nested router, such as `push(Shell(children: [X, Y, Z]))`. The first back() closed them all.
- **FIX**: off the web, `navigationHistory` keeps its limit of 21 entries again after `pushAll` of many pages, and after
  a change of tabs and back.
- **FIX**: off the web, `router.back()` after pages opened together in a tab, as `replaceAll([X, Y])`, shows them before
  an earlier change of tabs. It showed the other tab between them.
- **FIX**: off the web, `router.back()` and `reject(goBack: true)` still leave a link into a nested router while a guard
  there decides, and after its yes back() walks from the page let in to the page before. They did nothing once the
  router had changed meanwhile. back() while such a guard decides after the app's own push of a page with its nested
  pages closes only that page.
- **FIX**: off the web, `router.back()` never opens a page whose guard turned the app's own navigation down, as after a
  `navigatePath` with a push made while the guard decided or with the guard's sign-in page backed out of. And after a
  guard's yes that came after such a push, back() shows the page let in before the page under it; it skipped it.
- **FIX**, **BEHAVIOR CHANGE**: a page whose guard, asked again by the `reevaluateListenable` (as after a sign-out),
  returns without an answer leaves the stack and the screen at once, with the pages above it, and the url names the page
  then shown. It was taken off the stack but stayed on screen, with its url, until the next rebuild, so a pop closed it
  and left its url, and `replace` replaced the page under it. Once the guard says yes, the page goes back on top of the
  stack as it then is, and the pages that were above it follow as their guards let them; a no answers the code that
  opened it `null`, also when it first showed a sign-in page with `redirectUntil` that the user closed. Only a "yes"
  from after the last change counts: one from before it is dropped and the guard asked again. A navigation to the same
  page meanwhile (same route, path parameters and arguments) takes its place. Meanwhile `pop`, system back, `push` and
  `replace` act on the page shown. A router's last page is never taken off: it stays on the stack and on screen until
  the guard answers, while the pages above it leave with the let-go. A guard that wants its page kept while it decides
  awaits its answer inside its call; one that shows a page or a dialog of its own in its call keeps its page under it,
  as one behind `redirectUntil` does.
- **FIX**: a guard asked again that returns without an answer, such as `if (isSignedIn) resolver.next();` with no else,
  no longer freezes its router. Later changes of the `reevaluateListenable` ask the other pages' guards again,
  `reevaluateGuards()` completes, and leave listeners hear each leave; before, none of this happened until that guard
  answered. Such a guard no longer counts in `activeGuardObserver.guardInProgress`, since nothing on screen waits for
  it. The active tab's guard does the same: its tab leaves the screen for the home tab and shows again once the guard
  says yes, unless the user chose another tab meanwhile.
- **FIX**: a tab change whose guard said yes from before a sign-out no longer shows the tab: the guard is asked again
  and its new answer decides, as it already was for a page of a stack. The tabs switched to the tab, built its page off
  the screen for the signed-out user and set its url, then switched back in the same turn.
- **FIX**: a push whose guard returned without an answer, as one that answers from a callback does, no longer holds up
  later changes of the `reevaluateListenable`: a sign-out closes the pages it must close and `reevaluateGuards()`
  completes while that guard waits. A guard that shows a dialog and answers from it is no longer called again, with a
  second dialog, by a change while its dialog is open.
- **FIX**: a guard that changes the `reevaluateListenable` itself, as one that signs the user out when a token is
  refused, is no longer asked without end, whether it guards a tab or a page that let go; that change asks it nothing
  again.
- **FIX**: a navigation whose guard answers later from a callback no longer opens its page on a "yes" from before a
  sign-out: the guard is asked again, and only an answer from after the change counts, as for a guard that awaits a
  request inside its call.
- **FIX**: a change of the `reevaluateListenable` that comes while a page's guard, asked again, awaits a request now
  completes its `reevaluateGuards()`; it stayed open for good once that guard returned without an answer.
- **FIX**: on the web, when the page a link opened on top is removed from under another page, such as with
  `removeWhere`, the pages the link opened under it keep a way back: the nearest of them takes the link's browser entry,
  so the back button closes the pages one at a time. Opened at a link that a `deepLinkBuilder` turns into Home, A and B,
  a push of C and a removal of B left the browser on its first entry, so back left the app with A still open; typed into
  the address bar over Home, one back press from C closed C and A together.
- **FIX**: on the web, `navigationHistory.forward()` with no entry ahead does nothing, as the browser's own
  `history.forward()` does, and the next navigation reaches the address bar at once. The history waited a second for the
  browser to land and held every write behind it, so the address bar kept the old url while the new page showed, and a
  back press in that second closed two pages.
- **FIX**: on the web, a press of the browser's back button that comes while the router's own step back is still on its
  way, as right after `pop`, `pop` and `push` in one handler, ends on the entry where the browser ends, and the app
  shows that entry's page. The app followed the entry between the two steps, so the address bar was left on another page
  than the one shown, and a later back press reopened a page the app had closed.
- **FIX**: on the web, the pages a link opened keep their way back after the link's page leaves from the top, by a pop,
  `removeLast` or a replace: removing the page that took its place later hands the link's entry to the page under it.
  Opened at a link that a `deepLinkBuilder` turns into Home, A and B, a pop of B, a push of C and a removal of A left
  the browser on its first entry, so back left the app with Home still open.
- **FIX**: on the web, when the link's entry is handed over and the nearest page that shared it is kept out of the
  address bar (`neglectWhen`), the next page under it takes the entry, so back from the page on top shows it. The entry
  went with the kept-out page, and back left the app.
- **FIX**: on the web, a step forward that lands on the entry of the page on top before its url is written there, as the
  browser's forward button pressed in the same turn as `pop`, `pop` and `push`, or `navigationHistory.forward()` then a
  push, leaves that page with its own url in the address bar. The address bar showed the url of a closed page, and a
  later back press reopened it.
- **FIX**: on the web, an app opened at a link to a page inside a nested router whose guard takes its time keeps one
  browser entry for the launch, while the guard decides and after it says yes. It ended with three, so the back button
  walked through pages the user never navigated to.
- **FIX**: on the web, pages the app opens together in a tab after a change to another tab and back, as `replaceAll([X1,
  Y1])`, get their entries after that tab change: back from Y1 shows X1, then the other tab. It showed the other tab
  first.
- **FIX**, **BEHAVIOR CHANGE**: a link, `navigatePath` or `navigate` to a tab the app removed from its
  `AutoTabsRouter`'s routes, while the route stays in the router's config, is turned down on every platform: the tab on
  screen, its url and the dialogs over it stay, and `onFailure` hears a `RouteNotFoundFailure`; the app's own call
  without `onFailure` throws, as the tabs router's own `navigate` did. Nothing happened before and nobody was told, and
  on the web the address bar named the removed tab while another tab showed. A navigation that opens a new tabs page on
  such a tab takes that page back when a page is under it, so an app opened at such a link shows the page the link
  brings under the tabs page. Off the web a turned-down link no longer leaves an entry in the app's own history.
- **FIX**: off the web, `router.back()` and `context.back()` into a tab whose guard waits, then lets the tab in, step
  back once: the next back() no longer reopens the tab just left. The same with a guard inside the tab's own stack, and
  with one that shows its sign-in page until it lets the tab in.
- **FIX**: `replacePath`'s `onFailure` hears what the nested router or tabs of the page it puts on turn down, such as a
  tab the app removed, as `pushPath`'s and `navigatePath`'s do.
- **FIX**, **BEHAVIOR CHANGE**: the app's own `navigate`, `navigatePath`, `push`, `pushPath`, `pushAll`, `navigateAll`
  or `popAndPushAll` without `onFailure` to a tabs page not open yet, naming a tab the app removed, completes with a
  `FlutterError`, as the same call into an open tabs page throws. Without `onFailure`, `pushAll` and `popAndPushAll`
  then complete once the new page's nested router has taken the navigation up, a frame later at most.
- **DOCS**: `navigate` says what its future answers: the innermost page it reaches, when that page closes, with its
  result; a navigation into tabs once the tab change has started.
- **FIX**: a router's `pagelessRoutesObserver.hasPagelessTopRoute` is false once its navigator has gone, such as a
  nested router whose pages were all removed while a dialog showed. It said a dialog was still on top.
- **DOCS**: `AutoRouteObserver` says a subclass must call `super` in `didPush`, `didPop`, `didRemove`, `didReplace`,
  `didInitTabRoute` and `didChangeTabRoute`.
- **FIX**, **BEHAVIOR CHANGE**: the app's `navigate` into a page already open keeps the dialogs over it, such as an
  unsaved draft, until the guards of that page's nested router let the navigation in, as a link already did: a
  navigation they reject leaves the dialog open. It closed them before those guards answered. Once let in it closes only
  the dialogs over the page it reached, not one the app opened meanwhile over another page. An app that relied on the
  early close now sees the dialog stay while a slow nested guard decides, and after a rejection; a nested guard that
  shows a page of its own inside the nested router, such as a login, shows it under that dialog.
- **FIX**, **BEHAVIOR CHANGE**: the app's `navigate` or `navigatePath` to a page inside a tab's nested router keeps the
  dialog over the tabs until the guards of that router let the navigation in, as it does for a page of a stack: a
  navigation they reject leaves the dialog open. It closed it at once. An app that relied on the early close now sees
  the dialog stay while such a guard decides, and after a rejection.
- **FIX**, **BEHAVIOR CHANGE**: the app's own change to another tab, opened before, by `navigate` or `navigatePath` to a
  page inside it, shows that tab only once the guards of the tab's nested router let the navigation in, as a link's
  change does: one they reject leaves the tab on screen, the dialog and the url as they were. It switched the tab first.
  A guard there that shows a page of its own in the tab while it decides, such as a sign-in page, shows the tab with it;
  a cancel leaves that tab on screen. With a slow guard there, the tab now shows once it answers, and the tab change
  comes after the nested page is in. A tab never opened is built off the screen and shows once its guards let the
  navigation in, as the first lines of this list say.
- **FIX**: an `AutoRouteAware` tab page that a change of the tabs list opens, after the tab on screen left the list, now
  names that tab as its previous tab in `didInitTabRoute`, as `AutoRouterObserver`s hear it.
- **FIX**: a tab that keeps no state (`maintainState: false`) and whose nested router has no initial child shows the
  pages its `AutoTabsRouter` lists for it when it is opened again, by `setActiveIndex` or by `navigate`. It showed no
  page at all, and `navigate` brought back the page of a path that first opened it.
- **FIX**: pops right after a call that takes the top page off close the pages of the stack, in one handler as a frame
  apart: on Home, A, B, `replace(C)`, `pop()`, `pop()` ends on Home. It ended on Home, A, with A, a page the app had
  closed, back on screen: the second pop closed the route of B, which the navigator still held until its next build. The
  same holds for `maybePop`, `popTop`, `maybePopTop` and `popAndPush` after `replace`, `removeLast`, `removeWhere` and
  `pushAndPopUntil`, in a nested router and in a tab's router, and a `maybePop` there asks the `PopScope` of the page
  then on top. Two `maybePop` calls in one handler still close one page, as two calls of Flutter's `Navigator.maybePop`
  do.
- **FIX**, **BEHAVIOR CHANGE**: off the web, two calls of `router.back()` in one handler step back twice: on Home, A, B
  they end on Home. They ended on Home, A, since the second call found the first step still under way, though the router
  had already taken it. An app that calls `back()` twice in a row now goes back two pages, as two calls of
  `history.back()` in one task take a browser back two entries. While a step back waits on a guard, a second call still
  does nothing.
- **FIX**: off the web, `router.back()` opens no page that was closed before it was ever built. After `push(C)` and
  `pop()` in one handler, a later `back()` put C on screen again, and `replace(C)`, `pop()`, `back()` in one handler
  ended with C on top though its caller had its answer; after `push(A)`, `push(B)`, `popUntilRoot()` in one handler
  `back()` opened B. The app's own history kept the entry of such a page, since no navigator reported its pop.
- **FIX**: a push right after `popUntilRouteWithPath`, or after `popUntil` or `popUntilRouteWithName` with `scoped:
  false`, stays when pages were pushed earlier in the same handler: from Home, `push(A)`, `push(B)`,
  `popUntilRouteWithPath('/a')`, `push(D)` ends on Home, A, D. D was lost, and after an unscoped pop down to the first
  page the screen stayed empty. The pages the navigator has not built yet now leave as the pop is called, as they do for
  `popUntilRoot`.
- **FIX**: the root's `maybePop()` closes the top page of the nested router on top right after a call on that router in
  the same handler: in a shell on X, Y, Z, the shell's `replace(W)` and `pop()`, then the root's `maybePop()`, ends on
  X. It ended on X, Y, and after the shell's `push(W)` it closed Z and left W on top, since the pop went straight to the
  nested navigator, which had not built W yet. The same in a tab's router. `maybePopTop` and the system back button were
  right.
- **FIX**, **BEHAVIOR CHANGE**: a sign-out that lands while a navigation's guard still waits no longer opens the guarded
  page. With `push(AccountRoute())` behind a guard that reads the session and then awaits a request, a change of the
  `reevaluateListenable` during the wait took the guard's answer from before the change, so the page opened for the
  signed-out user and stayed until the next change. The guard is now asked once more before its page goes in, also for
  `replace`, `pushAll`, `replaceAll` and `navigate` and in a nested router, so a guard can run twice for one navigation.
  A change the guard makes itself, as one that restores a stored session does, does not ask it again, and neither does a
  change while the guard waits behind a page or dialog it showed.
- **FIX**: a sign-out as the third of three changes of the `reevaluateListenable` in a row closes the guarded page. A
  change that landed while a guard, asked again, still awaited was followed by one more round of checks only once, so a
  third change during that round took the round's answer from before it and the page stayed open. Every such change that
  is not the guard's own is now followed by another round, three in a row at most.
- **FIX**: a page held back for a guard that answers later comes back when the guard lets it stay, also when the app
  rebuilt its pages meanwhile. A guard asked again by `reevaluateGuards` or the `reevaluateListenable` that returns
  without an answer has its page held back; any navigation or url update during the wait then lost the page for good,
  and the code that awaited its `push` got `null` though the guard let the page stay.
- **FIX**: a page that `replaceAll` set aside for a guard's page is asked again as it comes back when the session
  changed meanwhile. After `replaceAll([VaultRoute()])` showed the guard's pin page and the session ended, canceling the
  pin page brought the account page back for the signed-out user until the next change.
- **FIX**: the pages of a nested router are back with their page when a guard of `replaceAll` rejects. A page that
  `replaceAll` had set aside for a guard's page came back on its nested router's first page, so `[ListRoute(),
  DetailRoute()]` inside it was `[ListRoute()]` after the user canceled the guard's login page. The code that opened a
  nested page still gets `null` as the guard's page goes on: the page that comes back is a new screen.
- **DOCS**: the README's part on guards says that a guard may be asked again before its page goes in when the
  `reevaluateListenable` changes while it checks, except for a change it makes itself or one while it waits behind a
  page or dialog it showed, three times in a row at most; that a change during an extra round of a reevaluation is
  followed by another round too, three in a row at most; and that pages `replaceAll` set aside for a guard's page are
  asked again as they come back when the listenable notified meanwhile.
- **FIX**: an app opened at a link that a guard rejects, such as a browser opened at a protected page, no longer keeps
  the rejected link in its url: the address bar and a reload show the page the app shows, or `/` when it shows none. The
  Router reported nothing until a first page was in, so the browser kept the link.
- **FIX**: an `AutoRouteLeaveListener` in a screen that a navigation reaches again, such as `navigate` or a link to it,
  `replace` with its route or a `replaceAll` that keeps it, goes on hearing the screen leave, as does one in a screen an
  `AutoRouter.declarative` list keeps when the list changes. Since the listener came in (12.4.0) it heard nothing more
  there: it stayed with the screen's first page, and the leave went to the page that took the screen over. Flutter's
  Navigator keeps the route of a page of the same type and key, and a `PopScope` in it keeps hearing its pops.
- **FIX**: `removeRoute` with the `RouteData` of a screen kept from before a navigation reached that screen again, such
  as a link to it with new query params, counts as the app's own removal, as with the `RouteData` the screen shows now.
  A push of the same route right after it builds a new page; it took over the screen just removed, with its old state.
  Such a `RouteData` still removes the screen, as Flutter's `Navigator.removeRoute` removes a route it kept for a new
  page.
- **FIX**: a screen that `replaceAll` keeps below the top, such as `ARoute` in
  `replaceAll([HomeRoute(), ARoute(), CRoute()])` over `[HomeRoute(), ARoute(), BRoute()]`, keeps the code that opened
  it waiting for the result it closes with, as Flutter's Navigator keeps the route of a page of the same type at the
  same place. That code got `null` at once, and a screen opened with a result type, such as with `push<int>`, was built
  anew there, losing its state.
- **FIX**: a page holding a nested router or tabs that `replaceAll` keeps below the top, such as
  `ShellRoute(children: [ChildBRoute()])` under a new top page, now shows the children `replaceAll` names, as one kept
  on top already did. It kept showing its old children, and as the last page it stacked the new child over them.
- **FIX**: a `replaceAll` that keeps the shell on top, such as `[HomeRoute(), ShellRoute(children: [ChildBRoute()]),
  GuardedRoute()]` over `ShellRoute(children: [ChildARoute()])`, changes the shell's children only once every guard
  lets the batch in. While a guard took its time, the shell already showed ChildBRoute and sent its url, and the new
  top page then went in as a new history entry; a guard that rejected the batch left the shell on ChildBRoute, with
  ChildARoute's state lost. A rejected batch also gives every kept screen's nested router back its own page's route
  data, which the rejected page had taken.
- **FIX**: the nested router of a shell that `replaceAll` keeps below the top keeps the route data of the page that
  keeps the shell. When a guard rejected the batch before that page went in, the next page of the shell's route, such
  as a `ShellRoute(children: [ChildCRoute()])` pushed later, took the old shell's nested router; and a page of the
  shell's route earlier in the same batch took it from the page that keeps the shell. The shell's children then read
  the other page's path params.
- **FIX**: `navigate` to a route already in the stack that a guard rejects leaves the stack, the screen and the url as
  they were, as a rejected `replace` and `replaceAll` do. It took the page it reached, and every page above it, off the
  stack before the guards ran: with `[HomeRoute(), ShellRoute(children: [ChildARoute()]), FirstRoute()]`, a rejected
  `navigate` to the shell with `ChildBRoute` left only `HomeRoute` on the stack, and a pop then showed a blank screen.
- **FIX**: `replacePath` that a guard rejects keeps the page it would replace, as `replace` does. It took the top page
  off before the guards ran, so the code that pushed that page was told it had closed, and back from the next push
  skipped it.
- **FIX**, **BEHAVIOR CHANGE**: a guard that rejects one route of a batch now rejects the whole batch, as `replaceAll`
  already did: `pushAll`, `popAndPushAll`, `navigatePath` with `includePrefixMatches` and a link the platform hands the
  running app leave the stack as it was. The pages before the rejected route stayed on the stack unseen, and the next
  change of the stack showed them. A batch that starts on an empty stack, as when the app opens at a link, still keeps
  the pages its guards let through.
- **FIX**: a page a batch takes off answers the code that opened it only once every guard lets the batch in. When a
  later guard rejected `pushAll([FirstRoute(), SecondRoute()])` over a page that keeps no history, the page came back
  on screen, but `push<int>` of it had already finished with `null`, so the result the page closed with reached no one.
  The page `replacePath` with `includePrefixMatches` replaces, and the pages above its target that a link takes off,
  did the same when a later guard rejected the batch or its login page was canceled.
- **FIX**: off the web, a link with a query or a fragment, such as `/secret?x=1`, whose guard calls
  `reject(goBack: true)` leaves the stack as it was. Debug builds failed Flutter's duplicate page key assertion, and
  release builds kept the page on screen twice, so closing it showed it again: the rejected batch and the router's
  `back()` both put the page back.
- **FIX**: a page behind an async guard stays on the stack and on screen, with the pages above it, when the app rebuilds
  while `reevaluateGuards` or the `reevaluateListenable` asks its guard again; only the guard's answer closes it. It
  closed, or the app went blank, as soon as anything rebuilt the app during the guard's check.
- **FIX**, **BEHAVIOR CHANGE**: `replaceAll` keeps the pages on the stack, with their state, until a page goes on in
  their place, and replaces them in one step once every guard has let the new routes through; a `replaceAll` that a
  guard rejects changes nothing. It emptied the stack before the guards ran: a rebuild of the app while a guard decided
  showed a blank screen, for good behind a guard that asks in a dialog, and a rejection brought the pages back with
  their state lost. A page that goes on for a guard before it answers takes the place of the old pages as it goes on, as
  before: a login the guard shows with `redirectUntil`, awaited or not, or one the app shows once the guard has asked
  for a sign-in and returned. Back from that page shows none of them, and they come back only if the guard then rejects;
  until the guard answers, the code that opened one of them goes on waiting for its result. A guard that shows no page
  keeps them until it answers. A guard of `replaceAll` that reads `router.stack` or `router.current` before it shows a
  page now sees the pages on screen, not an empty stack, and a page the app pushes while a guard's call still runs, as
  while it awaits a request, goes on over the old pages and is replaced with them.
- **FIX**: when the `reevaluateListenable` notifies again while a guard still runs its check, the guards are asked once
  more when that round ends, so the last change decides. The second change took the answer the guard had read before it,
  so a page stayed open after a session ended during the guard's wait.
- **FIX**, **BEHAVIOR CHANGE**: the pages of `pushAll`, `popAndPushAll`, `navigatePath` and `replacePath` with
  `includePrefixMatches`, and a link that comes with the pages below its own go on in one step, once every guard has let
  its route through, as Flutter's Navigator takes a new list of pages as one update. Each page went on as its own guards
  accepted it, so `router.stack` and `router.current` showed the first pages while a later guard still decided, and a
  rebuild of the app brought them on screen. An app opened at a link still opens each page as its guards let it through.
  Two things an app can notice: a guard of a batch reads the stack without the batch's earlier pages while it decides,
  and a login page that a later guard of `pushAll` shows over a page with `keepHistory: false` now takes that page off,
  as a single push with that guard already did, so canceling the login shows the page below it.
- **FIX**: `resolver.redirectUntil(route, replace: true)` takes the page on top off only once the guards have let its
  target through. It took the page off the stack first, so after a target that a guard rejects, or that no route
  matches, the page was still on screen but no longer on the stack: the next change of the stack took it away, and back
  skipped it.
- **FIX**: a guard that throws, as an async guard does when its request fails, leaves the router working: the navigation
  fails with the guard's error, the stack stays as it was, `activeGuardObserver.guardInProgress` goes back to `false`,
  and later reevaluations still ask the guards. A throw during a push left `guardInProgress` on `true` for good, and
  after a throw during a reevaluation the guards were never asked again, so a later sign-out closed nothing.
- **FIX**: the `onFailure` callback of `replaceAll` and `navigatePath` hears a guard's rejection, as a
  `RejectedByGuardFailure`, as the callback of the other navigation calls does. It was never called for one.
- **FIX**: `reevaluateGuards` and the `reevaluateListenable` ask the guards of every page again, also in the nested
  router or the tabs of a page that another page covers, as Flutter's Router parses its whole configuration again when
  its route information changes. Only the nested router of the page on top was asked, so a guarded page under another
  page stayed open after a sign-out and showed on back. The nested routers are asked one after another, from the bottom
  of the stack up, so two guards that answer a sign-out with a login page show one login page.
- **FIX**, **BEHAVIOR CHANGE**: a screen that stays when `replace` puts a page of the same route in its place, or when a
  page of the same route is pushed over it and it keeps no history (`keepHistory: false`), keeps the code that opened it
  waiting, and that code gets the result the screen closes with, as Flutter's Navigator keeps the route of a page of the
  same type and key. That code got `null` as the `replace` or the push went in, although the screen stayed. Code that
  awaits the first push now runs on when the screen closes; what should run as the screen is replaced belongs after the
  `replace` call.
- **DOCS**: the README's section on guards says what a guard that awaits must mind: the state can change during the
  wait, such as a sign-out during its request, so it reads what its answer depends on after its last `await`, right
  before `resolver.next()`. It also says how `replaceAll` and a batch of pages wait for their guards.
- **FIX**, **BEHAVIOR CHANGE**: a navigation called right after another, in the same handler with no await between them,
  acts on the pages of the first. From Home, `push(A)` then `replace(B)` gives Home, B; `push(A)` then `replaceAll`,
  `navigate`, `popAndPush` or `removeLast` no longer takes off the page below A; `pushAll([A, B])` then `push(C)` puts C
  on top; `replaceAll([B])`, `push(A)`, `replace(C)` gives B, C. The first call added its pages a microtask or more
  later, so the second acted on the stack without them. `push`, `replace`, `pushAll`, `replaceAll`, `navigate` and the
  path calls now put their pages on the stack as the call returns, as Flutter's Navigator changes its history at each
  call, when the route has no guard or each guard answers in its own call, as one that reads a flag and calls
  `resolver.next()` does. An app sees the router's listeners run inside the call, not a microtask after it, and
  `router.stack` hold the pages as the call returns. A guard that awaits before it answers, or shows a page of its own,
  makes the navigation wait as before, and a call made meanwhile does not wait behind it. Called while widgets are
  built, as from `initState`, a navigation starts a microtask later; two of them in one build start in order, but
  `replace`, `navigate` and `removeLast` pick the pages they take off as they are called.
- **FIX**, **BEHAVIOR CHANGE**: `navigate` to an open page that holds a nested router, with a route given no children
  and with no initial child, as a "back to the shop" button calls `navigate(ShopRoute())`, keeps the pages that router
  shows, and so does a tab reached that way. It left the nested router blank under a url that still named the child. An
  app that called it to empty the nested router names the children it wants, or uses `navigatePath`. `navigatePath`, a
  link, `back()` and the browser's buttons name the whole state, as a url does, and still empty a nested router they
  name no page for; they now tell the router's listeners, so the url drops the child. It stayed `/mail/42` after
  `navigatePath('/mail')` had emptied the detail pane.
- **FIX**: `insert` below the top no longer closes a top page with `keepHistory: false`, which leaves when a page goes
  on above it, not under it. An `insert` at the top index over such a page takes it off, as `push` does. It threw a
  `RangeError`.
- **FIX**: leaving a nested router while a guard's `redirectUntil` page is open in it, as when the user leaves a shell
  from its login page, throws nothing. It threw "used after being disposed" once the guard answered, and left the url
  marked, so the next page took the history entry of the page before it.
- **FIX**, **BEHAVIOR CHANGE**: `parentAsStackRouter` and `parent<T>()` answer `null` when the parent is a router of the
  other kind, as `parent<StackRouter>()` does in the router of a tab, as their nullable types say. They threw a type
  error there, so a page shown both in a tab and outside one could not ask. Code that caught that error gets `null` now.
- **FIX**, **BEHAVIOR CHANGE**: `removeWhere(notify: false)` tells no listener and leaves the url until the next change,
  as `removeRoute(notify: false)` does. It notified once for every page it removed. With `notify` on, listeners now hear
  one change for the whole call, not one per removed page and one more.
- **FIX**, **BEHAVIOR CHANGE**: a guard that answers in its own call delays nothing, with any number of guards on the
  route and in `RootStackRouter.guards`. Each answer was awaited for several microtasks, so the same two calls ended in
  different stacks with a guard and without one. A guard that calls `resolver.next()` and then goes on working, such as
  an `async` guard that awaits after its answer, no longer holds the navigation until it returns: the page opens at the
  answer, and an error the guard throws after it is an uncaught error, not the navigation's. Do what must happen before
  the page opens before the answer. While widgets are built, guards are asked a microtask after the call, not in it, so
  `activeGuardObserver` no longer notifies inside a build. A page replaced with `replace` or `replaceAll` in the
  `initState` that also changes the `reevaluateListenable`, such as a splash page that signs the user in, stays
  replaced. It came back under its replacement when the new page had no guard.
- **FIX**, **BEHAVIOR CHANGE**: a link from the platform that the app turns down keeps the dialog or sheet the user has
  open, such as a draft: one a guard rejects, also a guard in a nested router or on a tab, or one `deepLinkBuilder`
  answers with `DeepLink.none`. It closed it before the guards answered. The dialogs now close only once the link is let
  in, and a browser back or forward that lands on the page already on top keeps them.
- **FIX**, **BEHAVIOR CHANGE**: with `rebuildStackOnDeepLink`, a link a guard rejects keeps the pages the user has open,
  and the url. The stack was popped before the guards ran, and nothing put it back. A link now replaces the stack as
  `replaceAll` does, once its guards let it in, so the pages it replaces are reported to their leave listeners as
  replaced, not popped. A page a guard shows meanwhile, such as a sign-in page, goes on over the open pages, and back
  from it shows them.
- **FIX**: after a link a guard rejects, or one `deepLinkBuilder` answers with `DeepLink.none`, the running app's url
  names the page on screen: `currentUrl`, `urlState` and `isPathActive`, and on the web the address bar, which the app
  writes over the turned-down link's entry, as after browser forward to an entry whose guard now rejects. They kept the
  rejected link.
- **FIX**: of two links handed to the app, the one handed over last stays on screen when `deepLinkBuilder` answers the
  earlier one later or takes its time on every link, as on an iOS cold start from a link with a builder that waits for a
  session. The earlier link's page opened over it.
- **FIX**, **BEHAVIOR CHANGE**: `DeepLink.prefixStripper` strips its prefix from the link's path alone, as whole
  segments: `prefixStripper('/app')` turns https://app.example.com/app/books/1 into https://app.example.com/books/1 and
  leaves /application alone. It cut the text out of the host. A prefix without its leading '/', as the README showed it,
  now strips too.
- **FIX**: `AutoTabsRouter.pageView` opened under another page, such as by a link, a restored session or `replaceAll`,
  shows the tab chosen once it is uncovered. A tab change while it was covered threw "Null check operator used on a null
  value".
- **FIX**: `AutoTabsRouter.pageView` keeps the active tab on screen when a tab whose guard is still deciding is swiped
  to a second time, as `.tabBar` does. It rested on that tab's empty page.
- **FIX**: `AutoTabsRouter.tabBar(duration: Duration.zero)` jumps back to the active tab when a swipe ends on a tab its
  guard rejects. It failed the assertion "duration > Duration.zero".
- **FIX**: with `AutoTabsRouter.pageView` and `.tabBar`, a tab with `maintainState: false` that a drag only peeked at is
  disposed once the view settles back, as Flutter's `PageView` disposes a page scrolled out. It stayed built in the
  background.
- **FIX**: in right-to-left apps and with `scrollDirection: Axis.vertical`, a swipe in `AutoTabsRouter.pageView` or
  `.tabBar` toward a tab not opened yet shows its page as it comes in. It uncovered blank space.
- **FIX**, **BEHAVIOR CHANGE**: `AutoTabsRouter.builder` calls `didChangeTabRoute` and `onNavigate` only when another
  tab shows, as the other tabs do. It also called them when a guard rejected a tab, when the open tab got new params,
  and when a change of the tabs list moved the open tab to another index. An app that heard new params of the open tab
  this way can listen to the `TabsRouter`, which still notifies.
- **FIX**: the default `AutoTabsRouter` and `AutoTabsScaffold` no longer report `didInitTabRoute` again for a tab kept
  across a change of the tabs list. They reported it on every change, though the tab's page was kept.
- **FIX**: the default `AutoTabsRouter` and `AutoTabsScaffold` with `lazyLoad: false` report `didInitTabRoute` each time
  a tab with `maintainState: false` opens, since its page is built anew. They reported nothing after its first opening.
- **FIX**: the default `AutoTabsRouter`, and `AutoTabsScaffold` with `animationDuration` and `animationCurve`, take a
  new duration and curve when rebuilt with them, as Flutter's implicit animations do. They kept the first ones.
- **FIX**: `AutoTabsRouter.pageView` ends a swipe on a tab whose async guard lets it in at once, such as one that reads
  a cached session. It slid back to the tab it left while the new tab was active.
- **FIX**, **BEHAVIOR CHANGE**: `AutoTabsRouter.builder` reports a tab's first opening through `didInitTabRoute` and a
  return to it through `didChangeTabRoute`, as the other tabs do. It reported every tab but the first through
  `didChangeTabRoute`. An observer that sets a tab up when it first opens does so in `didInitTabRoute`.
- **FIX**: the default `AutoTabsRouter` and `AutoTabsScaffold` with `lazyLoad: false` report `didInitTabRoute` for a tab
  with `maintainState: false` when it opens, not at the start, since they build it only then. They reported two inits
  for one page.
- **FIX**: `AutoTabsRouter.tabBar` ends on the chosen tab when a drag during a tab change lets go over a tab whose guard
  rejects. It failed the assertion "!indexIsChanging".
- **FIX**: `AutoTabsRouter.pageView` shows only the tab left and the tabs chosen when the tab changes again while it
  still moves, such as on two quick taps in a bottom bar. A tab between them flashed by.
- **FIX**: two pages of one route in a stack, such as `/item/1` under `/item/2`, each hear only their own
  `AutoRouteAware` events, as Flutter's `RouteObserver` tells each route its own. Each heard the other's before.
- **FIX**: a tab's page built under a page that a deep link stacks over the tabs hears `didPushNext`, so its
  `didPopNext` has a pair. It heard only `didInitTabRoute`, then an unpaired `didPopNext`.
- **FIX**: an `AutoLeadingButton` above a nested router hides its back button once the page under the nested top page is
  removed and nothing can pop. The button stayed and did nothing when tapped.
- **FIX**: an `AutoLeadingButton` above a nested router shows the back button for a page the nested router opens with
  `pushWidget`, `pushNativeRoute` or `Navigator.push`. It showed no button though the page could be popped.
- **FIX**, **BEHAVIOR CHANGE**: `AutoLeadingButton(builder:)` is told `LeadingType.drawer` on a page with a drawer, as
  the default button shows the drawer there, like Flutter's `AppBar`. It was told `back` when the page could pop; a
  builder that relied on that should check for `LeadingType.drawer`.
- **FIX**: a page pushed over a page opened with `pushWidget` hears `didPop` when it is popped, as Flutter's
  `RouteObserver` tells the route that leaves. It heard `didPush` and never `didPop`.
- **FIX**: a nested router whose pages are all removed while a dialog shows over them no longer says it can pop, and
  the `AutoLeadingButton` above it hides. `canPop()` stayed true and the button showed back with nothing to go back to.
- **FIX**: off the web, `router.back()` leaves a page that a link with a percent-escape in its path opened, such as
  `/books/a%20b`. The link took the history entry of the page before it, so back stayed on it.
- **FIX**: off the web, `router.back()` after `popUntilRoot` or `popUntil` no longer reopens a page they closed. The
  closed pages kept their history entries.
- **FIX**: on the web, the browser's back button leaves an entry made by `pushPathState`, also on a page whose
  `PopScope` refuses to be left, and its forward button returns to it. The app wrote the state again as a new entry at
  once, so back never left it; between two entries of one page no page closes, so the `PopScope` is not asked, as a
  browser asks nothing between two states of one document.
- **FIX**, **BEHAVIOR CHANGE**: on the web, `pushPathState` adds a browser entry also right after a replace, and
  `pushPathState(null)` adds one without a state, as `history.pushState` does. Right after a replace it wrote over the
  entry, and with `null` it did nothing; an app that called `pushPathState(null)` to change nothing now gets a new
  entry, so skip the call instead.
- **FIX**, **BEHAVIOR CHANGE**: on the web, `neglectWhen` gets the location as the address bar shows it, such as
  `/books/a%20b?note=x%26y`, the same on every platform. It got the string escaped once more for the web engine,
  `/books/a%2520b`; a callback that matched that form must match the url as shown now. Its doc comment, which said the
  opposite of what `true` does, now says that `true` keeps the location from the engine.
- **FIX**: on the web, the browser's back button after `popUntilRoot` or `popUntil` no longer reopens a page they
  closed: the browser steps back to the entry of the page now on top. It stayed on the entry of the last page closed,
  now showing the url of the page on top, so back reopened the page under it.
- **FIX**: off the web, a `router.back()` whose target page a guard rejects keeps the history as it was, so a later
  `back()` can still reach that page. It dropped the current entry before the guard answered, so once the guard let the
  user through, `back()` skipped the guarded page.
- **FIX**: on the web, a push and a replace of the pushed page in one frame keep the browser entry of the page under,
  and the forward button after back reopens the new page with its arguments. The one url the router writes per frame
  replaced the entry of the page under, so back had no entry of the app to go to.
- **FIX**: on the web, two pushes in one turn get a browser entry each, so the browser's back button returns to the
  first, as two `history.pushState` calls do. Only the second got an entry: back skipped the first page, still on the
  stack, and forward reopened the second without its arguments.
- **FIX**, **BEHAVIOR CHANGE**: on the web, the browser's back button walks the pages the way the system back does on a
  phone, however fast the app navigates: each press closes the page on top, and a page the app closed never comes back.
  After several navigations in one turn, or one made while the browser was still stepping back after a pop, the back
  button could show a closed page, skip a page or need a press too many. Flutter's Router wrote the url once a frame and
  the web history moved the browser between frames, each from its own account of where the browser stood. Now the web
  history alone writes the browser, one operation at a time, and the Router writes nothing on the web.
- **FIX**, **BEHAVIOR CHANGE**: on the web, pages the app opens together, with `pushAll`, `replaceAll` or
  `popAndPushAll`, have a browser entry each, so the back button closes them one by one, as the system back does. Only
  the page on top had one. Pages a link opens together still share the link's entry.
- **FIX**: on the web, a page the app takes off the stack without a pop, with `navigate` to a page underneath,
  `removeLast`, `removeWhere`, `removeUntil`, `replaceAll` or `pushAndPopUntil`, leaves no entry on the way back. Its
  entry stayed under the page on top, so the back button showed the closed page. After `replaceAll` or
  `pushAndPopUntil` with no page kept, the new page has the app's first entry, and the back button leaves the app, as
  the system back does after `Navigator.pushAndRemoveUntil`.
- **FIX**: on the web, an app opened at a url the router writes otherwise, such as `/a?b=` for `/a`, one with a
  trailing slash or one a route redirects, has one browser entry, with the url as the router writes it. It had two, so
  the first press of the back button seemed to do nothing. A guard's login page shown at launch no longer leaves an
  entry under the page it guards.
- **FIX**: on the web, after a reload, a call that leaves one page, such as `pushAndPopUntil` with no page kept, ends
  on the entry the app was reloaded on. It could step the browser under it, onto an entry from before the reload.
- **FIX**: on the web, with a url kept out of the address bar by `neglectWhen`, a replace, `popUntilRoot` or several
  navigations in one turn over the page kept out leave one entry for each page not kept out. They could leave an entry
  too many or the url of a page under the one shown.
- **BEHAVIOR CHANGE**: on the web, `AutoRouterDelegate.currentConfiguration` is null, which is how Flutter has a
  delegate report no route to the Router. Read `router.urlState` for the url; off the web nothing changes.
- **CHANGE**: on the web, when the active tab of an `AutoTabsRouter` is removed, or a guard closes a page after a
  logout, the browser steps back to the entry of the page now shown, and when the browser's forward button lands on an
  entry whose guard rejects it, the browser steps back to the entry it came from. The url of the page shown was
  written over the other entry before, which gave that page two entries.
- **CHANGE**: on the web, an app whose `routeInformationProvider` writes no browser entry is never stepped through the
  browser's history. A pop stepped the browser back before, for an entry the app had not written.
- **FIX**: a `RedirectRoute` among a route's children whose target is shorter than its path, such as `old/users` to
  `users`, or the catch-all `*` to `''` for two segments, opens its target. It matched nothing before.
- **FIX**: a url whose fragment holds a `?`, such as `/books/a%20b#what?`, opens its page. It threw a `RangeError`
  before.
- **FIX**: an app started at a link with an escape that isn't valid UTF-8, such as `/books/%FF`, shows a page, on the
  web too; such bytes read as U+FFFD, as browsers read them. It showed no page at all before.
- **FIX**: a link that repeats a query key, such as `?page=1&page=2`, gives `int`, `double`, `num` and `bool` params its
  last value, as `String` params get. They got the default or a `MissingRequiredParameterError` before.
- **DOCS**: `RouteData.fragment`, `RouteMatch.fragment` and `PageRouteInfo.fragment` say that a fragment reads as the
  url has it, not decoded, and that a fragment pushed in code is passed already encoded (`my%20section`) if it must read
  the same after a reload.
- **FIX**: `pushPath` and the other path calls open a relative path whose first segment holds a `:`, such as `user:5` or
  `12:30`. They opened another page or threw before.
- **FIX**: a `RedirectRoute` whose `redirectTo` has a fragment, such as `/docs#faq`, keeps it. The url's own fragment
  took its place before.
- **FIX**: `navigatePath`, `pushPath` and the other path calls open a nested page from a url with a scheme and host, as
  they already did for a top-level page. They matched nothing below the top before.
- **FIX**: `Parameters` holding lists, `PageRouteInfo` with `argsEquality: false`, and `AutoRouteInformation` hash the
  same when they are equal, so they work as keys of a `Map` or `Set`. Equal values could hash differently before.
- **FIX**, **BEHAVIOR CHANGE**: a `RedirectRoute` whose `redirectTo` is only partly matched, such as `/profile/settings`
  where only `/profile` is a page, opens what that url opens by itself: the `*` page, or nothing. It opened the page of
  the first segments before; point `redirectTo` at a page's full path to keep that page.
- **FIX**: a nested router inside a page of `AutoRouter.declarative` stays in the url and the router tree when the
  declarative list around it changes, and a page it opens reads its host's new path params. Once the list changed, the
  url, `topRoute`, `canPop` and `topMostRouter` no longer saw the nested router's pages, though they were still on
  screen, and a page it opened read the host's old path params. Flutter's Navigator keeps the route and state of a page
  it updates in place.
- **FIX**: the first page of `AutoRouter.declarative` drops its back button once the page above it is popped, and
  widgets that watch the router, such as `context.watchRouter` and `context.topRoute`, see the pages the navigator
  shows. They stayed one update behind, so the first page kept a back button that did nothing.
- **FIX**, **BEHAVIOR CHANGE**: in `AutoRouter.declarative`, a page closed by back opens again when the app's list names
  it again. It stayed closed as long as the list came back unchanged, such as when the user picked the same item again.
  The list is the truth, as a Navigator's `pages` are: a page the list still names after back closed it now comes back
  at the next rebuild of the widget that builds the router, whatever caused that rebuild. Take the page out of the list
  in `onPopRoute`, as the README's example now does.
- **FIX**: after state restoration, a nested page that reads a path param of its parent route through
  `inheritedPathParams` comes back. It was left out of the restored pages.
- **FIX**, **BEHAVIOR CHANGE**: a deferred page whose library failed to load, as when the network drops on the web,
  loads when it is opened again. Every later visit showed the loading placeholder until the app was reloaded. The
  failure is now reported through `FlutterError.reportError`, so the app's `FlutterError.onError` sees it; it reached
  the app as an unhandled async error.
- **FIX**, **BEHAVIOR CHANGE**: `DeferredWidget` shows the `placeholder` it is given while its library loads; without
  one, the router's placeholder shows as before. It ignored the parameter, so an app that builds a `DeferredWidget` with
  its own `placeholder` now sees that placeholder.
- **FIX**: a Cupertino page updated in place shows the new page's title in its navigation bar. It kept the title of the
  page it first showed.
- **FIX**, **BEHAVIOR CHANGE**: back on a Cupertino page asks the page's `PopScope` first, also while a drawer or
  another local history entry is open, as Material pages and Flutter's own routes do. Back closed the drawer and the
  `PopScope` heard nothing. A page whose `PopScope` blocks now hears the refused back, and can close the drawer itself
  in `onPopInvokedWithResult`; a page with no blocking `PopScope` still closes its drawer on back.
- **DOCS**: say what `enablePredictiveBackGesture` does to a route's transitions on Android without a
  `predictiveBackPageTransitionsBuilder`: Flutter's predictive back builder runs all of them, push included, so a
  `CustomRoute`'s own `transitionsBuilder` never runs. Give the route a `predictiveBackPageTransitionsBuilder` to keep
  its own transition outside the gesture.
- **FIX**: a nested `AutoRouter` whose first page has a guard, built and dropped within one frame, such as by a
  `LayoutBuilder` in a viewport that lays it out twice, no longer throws a null check error after that frame.
- **FIX**: route types that differ only in `enablePredictiveBackGesture` or `predictiveBackPageTransitionsBuilder` no
  longer compare equal or share a hash code.
- **FIX**: tabs of one route, such as one tab per list item, keep the tab on screen when the tabs list changes, and back
  keeps their history. A change of the list showed the first tab of that route.
- **FIX**: a tab whose guard is still deciding shows itself once the guard lets it in, also when the tabs list changes
  meanwhile, and a tab that left the list no longer shows. The tab that took its old index showed, without asking its
  own guard, and a shorter list failed an assertion.
- **FIX**: when the active tab leaves the tabs list, the url names the tab shown instead, and Android's back stays in
  the app. In a browser that url takes the place of the removed tab's entry, so the back button never shows its url
  again. The url kept naming the removed tab, and on Android 13 and later back closed the app.
- **FIX**: a tab whose guard threw once opens when it is chosen again, and the guard no longer stays in
  `activeGuardObserver`. Choosing it again did nothing until another tab was opened first.
- **FIX**: a tab change that another choice replaces while its guards decide asks none of its later guards, so a later
  guard's login page no longer opens over the tab chosen instead.
- **FIX**: a guard on a tab route can set the tab's children with `overrideNext`, as its doc says. It threw "does not
  have children".
- **FIX**: navigating to the tab on screen calls off a change to another tab still waiting for its guards, so the tab
  navigated to stays. The waiting tab opened once its guards let it in. `setActiveIndex` with the active index still
  calls off nothing, as Flutter's `TabController` ignores a choice of the selected tab.
- **FIX**, **BEHAVIOR CHANGE**: reevaluating the guards, as after a sign-out, asks the guards of the active tab again,
  and a tab they keep out gives way to the home tab, or the first. The tab stayed on screen and its guards were not
  asked. A tab guard now runs once more on each reevaluation, with `resolver.isReevaluating` true, and one that
  redirects opens its page then. A tabs page under other pages is asked as a stack asks its pages, one after another, so
  a sign-out that a guard in the tabs and a guard above them answer with a login page shows one login page, not two.
- **FIX**: `TabsRouter.previousIndex` follows the tab shown before when the tabs list changes, and is null once that tab
  is gone or is the active one. It kept its old index, which could name another tab or point past the end.
- **FIX**: `navigate` to a tab not shown yet, with a route object that names no children, opens the tab with the
  children its `AutoTabsRouter` gave it. Its nested router opened empty. A path names the whole state, so `navigatePath`
  to the tab with no child opens it with no page, as for a tab already shown.
- **FIX**: a listener of `TabsRouter` that calls `setActiveIndex` for the tab whose guard is deciding, while it is told
  of that change, gets that change. It threw "Null check operator used on a null value".
- **FIX**: when the guard of a tab that a link opens answers after the tabs were left, the next page gets a history
  entry of its own, so back no longer skips a page. The next page replaced the previous page's entry.
- **FIX**, **BEHAVIOR CHANGE**: signing in closes the login page of a guard that awaits its redirect, `await
  resolver.redirectUntil(...)`, when the `reevaluateListenable` notifies, as it closes the one of a guard that starts
  its redirect and returns. The guard was asked again only once its call had returned, which it does when the login page
  closes, so the page stayed open after the sign-in, and a login page that signed in and closed itself had its
  navigation rejected. Such a guard is now called again while its first call still awaits the redirect. A login page
  that also answers the guard itself, later than the listenable notifies, checks `resolver.isResolved` first, as with
  the other shape of guard.
- **FIX**: a page the app takes off while a guard is asked again by `reevaluateGuards` or the `reevaluateListenable`,
  with `replace`, `replaceAll`, `removeWhere` or `navigate`, stays off whatever the guard then answers. When the guard
  let its page stay, the page came back: `replace(OtherRoute())` during a slow guard's check over `[HomeRoute(),
  AccountRoute(), BillsRoute()]` ended as `[HomeRoute(), AccountRoute(), BillsRoute(), OtherRoute()]`, and a login page
  that signed in and called `replaceAll` in one handler kept the old page under the new one. A guard that rejects late
  now closes only pages still on the stack, and one that then redirects opens no page.
- **FIX**: `replaceAll` from the login page a sign-out was answered with, such as a "continue as guest" button on the
  page a guard showed with `redirectUntil` when the `reevaluateListenable` notified, leaves the router working.
  `activeGuardObserver.guardInProgress` stayed `true`, the next time the session ended no guard was asked, and code that
  awaited a `push` never resumed when `replaceAll` took its page off. The pages `replaceAll` takes off now answer the
  code that opened them in the step that replaces them, as a route that leaves Flutter's Navigator completes its future.
- **FIX**: the pages a guard's page took the place of under `replaceAll` stay gone once the app replaces that page with
  one of its own. After a sign-out with `replaceAll([HomeRoute()])` showed the guard's login page,
  `replaceAll([WelcomeRoute()])` or `replace(WelcomeRoute())` on it brought the old pages back, so back from the new
  page showed the account to a signed-out user. They still come back when the guard rejects or its page closes with
  nothing in its place.
- **FIX**: a router disposed with its widgets still mounted, as when an app swaps its router in one `setState`, while a
  guard asked again by `reevaluateGuards` or the `reevaluateListenable` still decides asks no further guard. It asked
  the guards of the nested router of its first page once more and threw "used after being disposed".
- **FIX**: a `RedirectRoute` among a route's children whose `redirectTo` starts with a path param opens its target when
  the param's value holds a `:`, such as `/slots/at/12:30` to `:time`. It threw a `FormatException` or opened another
  item before.
- **FIX**: a nested page whose path is generated from its name, pushed from a router above its parent, gets its own url,
  such as `/shop/cart-route`. It got its parent's url before, so a reload opened another page.
- **FIX**: a fragment given to a child route reaches the url and the page when the child is pushed with its parent, as
  `HelpRoute(children: [DocsRoute(fragment: 'faq')])` gives `/help/docs#faq`. The parent's empty fragment took its place
  before.
- **FIX**, **BEHAVIOR CHANGE**: the top-level `*` page opened in code, such as `router.replace(UnknownRoute())`, is at
  the url `/*`, and `currentUrl` and `currentPath` read `/*`. They read `*` before, which the browser resolved against
  the page shown; an app that compares them with `'*'` compares with `'/*'` now.
- **FIX**: with `usesPathAsKey`, a page that a link opened is not pushed a second time when the app navigates to it,
  also when the link escapes a character the route writes as it is, such as `user:5` or `%40` for `@`. The page was on
  the stack twice before.
- **FIX**: a `Set` given as a query param reads back as its values from `RouteData.queryParams`, as a `List` does.
  `optList` gave the one text `{red, blue}` before.
- **FIX**, **BEHAVIOR CHANGE**: an empty query value reads as absent: `?b=`, a bare `?c`, and an empty entry of a
  repeated key such as `?tag=a&tag=`, from a url or in a route pushed in code. A page no longer reads an empty text for
  such a key, so it reads the same before and after a reload; the url already left such a value out, and now leaves out
  an empty entry of a repeated key too.
- **FIX**: every kind of `AutoTabsRouter` tells its observers when a change of the tabs list shows another tab, such as
  when the tab on screen leaves the list: `didChangeTabRoute` from the tab that left, or `didInitTabRoute` for a tab
  that opens now, and the page shown hears it as an `AutoRouteAware`. They reported nothing, and `.pageView` and
  `.tabBar` never reported the init of a tab that opened this way.
- **FIX**: `AutoTabsRouter.tabBar` rests on the tab the router names when the tabs list changes while the view still
  moves, such as when a sign-in adds a tab right after a tap in the tab bar, as Flutter's `TabBarView` jumps to a new
  controller's index. It rested on another tab's page, often a blank one.
- **FIX**: the default `AutoTabsRouter` and `AutoTabsScaffold` name the tab each change left as the previous tab when
  the tab changes twice before a frame, such as two `setActiveIndex` calls in one turn. Both changes named the tab of
  the last frame.
- **FIX**: after state restoration, a page that holds `AutoRouter.declarative` shows the pages of the app's restored
  state, not those of the link that first opened it. A shop opened by a link to its cart, whose cart the user had
  closed, came back with the cart open.
- **FIX**: `waitForTransitions()` waits for a page that a navigation updated in place, as after `navigate` with new
  params, `replace` with the same route or a new list of `AutoRouter.declarative`. It returned at once while such a page
  still left or came in, so a bottom sheet opened after it closed at once.
- **FIX**: on the web, `replaceAll` and a `push` in one turn give each page a browser entry, so the browser's back
  button returns to the page `replaceAll` left. Only the pushed page got one, written over the entry of the page
  `replaceAll` took off, so back went to the entry under and put that page on top.
- **FIX**: off the web, `router.back()` leaves a page opened by a link whose path the router writes differently than the
  link has it: a trailing or doubled slash, a link a `RedirectRoute` sends on, one that `DeepLink.prefixStripper` or
  another transformer changes, or a nested segment written again. The link took the history entry of the page before it,
  so `back()` did nothing.
- **FIX**: on the web, a `replace` and a `pop` in one turn end on the browser entry of the page under, as the same calls
  a frame apart do. The browser stood on a new entry with the replaced page's entry under it, so back did nothing at
  first and then reopened that page.
- **FIX**: a screen that closes while a new page of its route goes on in the same step, such as `/item/2` when
  `replaceAll([HomeRoute(), ItemRoute(id: 3)])` replaces Home, `/item/1`, `/item/2`, hears its `AutoRouteLeaveListener`.
  It heard nothing whenever a new page shared its route, though the new page took over another screen.
- **FIX**: tabs of one route, such as one tab per list item, keep their pages when the guards are reevaluated, as on a
  token refresh. The last tab's page took the place of the tab on screen, and `AutoTabsRouter.pageView`, `.tabBar` and
  `.builder` threw "Multiple widgets used the same GlobalKey".
- **FIX**: a tab not opened yet, or not opened since the app was restored, keeps the pages it is to open with when the
  guards are reevaluated meanwhile, as when the session is read at start. It opened on its first page only.
- **FIX**: among tabs of one route, a path, a link, the app's start link or `navigate` that names one item's tab, such
  as `/item/3`, opens that tab. It turned the tab on screen, or the first tab at start, into that item, so two tabs
  showed it. A path to an item no tab has still updates the tab on screen in place.
- **FIX**, **BEHAVIOR CHANGE**: a `navigate` through the root that names children for the nested router or the tabs of
  an open page, or a path into its tabs, reaches them as the call returns, when no guard makes them wait. A call made
  right after it in the same handler acts on them as they then are: with the shell on A,
  `router.navigate(ShellRoute(children: [BRoute()]))` then `inner.push(CRoute())` gives A, B, C, and
  `router.navigatePath('/profile')` then `tabs.setActiveIndex(0)` ends on the first tab. The nested part came some
  microtasks after the call, so the second call acted on the old state: A, C, B, and the Profile tab. `replaceAll` does
  the same for a shell it keeps. An app sees the listeners of the nested router or the tabs run inside the call, not
  after it. A child whose guard awaits makes its own page wait as before, and the nested router of a page that is new
  opens its children when it is built.
- **FIX**: a link or a path to a guarded page inside a nested router that is not built yet, a shell that is not open or
  a tab never opened, leaves that router on its first page when the guard rejects the page, at the url of the page on
  screen: after `navigatePath('/mail/13')` Mail shows its inbox at `/mail`, and one step back leaves it. Mail opened
  with nothing in it, under `/mail/13`, and so it did after a link and in an app opened at the link. On the web a
  canceled navigation leaves the url of the document on screen, and in debug builds Flutter's Navigator reports an error
  for an empty list of pages.
- **FIX**: two `navigate` calls to a page that is open, the first waiting on its guard, leave one page of the route: the
  one whose guard answers last shows in it, and a navigation whose guard rejects changes nothing. The first call's page
  went on as a second page with the key of the other's, so a debug build failed the Navigator's check for duplicate page
  keys and a release build showed the earlier page over the later one.
- **FIX**: the page a link brings below its own, such as the inbox under a message, shows while the guard of the link's
  page decides, when the link opens a page whose nested router is not built yet. That router showed its placeholder
  until the guard answered, although the page was on its stack. A path the app calls names its page alone, so there the
  router still shows its `placeholder` while that page's guard decides; the doc of `AutoRouter.placeholder` says so.
- **FIX**, **BEHAVIOR CHANGE**: a link to a page inside a tab other than the one on screen, which that page's guard
  rejects, keeps the tab on screen, the dialog the user has open and the url. It switched the tab and closed the dialog,
  and a tab never opened showed blank under the rejected url. A link into another tab now shows the tab once the guards
  in that tab's nested router let it in, so a slow guard there delays the switch; a tab never opened is built offstage
  on its first page first.
- **FIX**: a link a guard rejects no longer cancels an earlier link that waits behind a sign-in page or a guard that
  awaits a request: once the user signs in, the earlier link's page opens. It never opened, and with
  `rebuildStackOnDeepLink`, or in an app opened at the earlier link, the sign-in page closed over a blank screen.
- **FIX**: of two links into a nested router, the one handed over last stays on screen when the guard of the first
  answers later. The first landed over it as a second page with the same key, which a debug build reports as a duplicate
  page key.
- **FIX**, **BEHAVIOR CHANGE**: a push right after `popUntilRoot`, `popUntil` or `popUntilRouteWithName` stays when
  pages were pushed earlier in the same handler: from Home, `push(A)`, `popUntilRoot()`, `push(D)` ends on Home, D. D
  was lost, and with two pages pushed before it Flutter's "An OverlayEntry should be removed only once" assertion failed
  and the screen stayed empty. The pages the navigator has not built yet now leave as the pop is called, not a frame
  later: an app sees the stack without them as the call returns, the callers of their pushes get null then, and the
  predicate of `popUntil` is asked about such a page through a stand-in page route that has the page as its settings.
  Pages on screen are popped as before.
- **FIX**: `pushAndPopUntil` with `ModalRoute.withName`, or any predicate that asks for a `ModalRoute` or a `PageRoute`,
  keeps the named page when it was pushed in the same handler: from Home, `push(A)` then
  `pushAndPopUntil(D, predicate: ModalRoute.withName('ARoute'))` ends on Home, A, D. It ended on D alone, with no page
  to go back to, because the predicate was asked about a stand-in that was no `ModalRoute`.

## 12.6.0
- **FIX**, **BEHAVIOR CHANGE**: the future that `push`, `navigate`, `navigatePath` or `replaceAll` returns now completes
  with `null` once its page leaves the stack, as a removed route's does in Flutter: when a later `navigate` or
  `replaceAll` takes the page off, or when the page's nested router closes. It never completed, and each call waiting
  on it kept the pages it worked with in memory: one more page on every `replaceAll` in release builds, and in debug
  builds and tests also the nested routers and page widgets of every link through nested routers. A navigation that
  reaches a screen already shown keeps that screen, so the code that opened it keeps waiting and gets the result the
  screen closes with, as Flutter's Navigator keeps the route of a page with the same type and key. The first build of
  12.6.0 (b705ff78) answered that code `null` at once: a picker answered `null` while still open, and a link to the
  redirect a guard showed with `redirectUntil` left a blank screen.
- **FIX**: a screen opened with a result type, such as with `push<int>`, and then reached again by `navigate`, a link,
  `replace` or `replaceAll` closes again, even with system back. Since 12.5.0 closing it threw
  `type 'AutoRoutePage<Object?>' is not a subtype of type 'Page<int>'`. The page that takes over a screen now keeps
  its result type, and a page whose type the screen's route can't hold gets a route of its own, as in Flutter.
- **BEHAVIOR CHANGE**: `AutoTabsRouter` passes a new `homeIndex` on when it is rebuilt with one, so back goes to the new
  home tab. A `homeIndex` past the end of the tabs counts as no home tab instead of throwing (#1759).
- **BEHAVIOR CHANGE**: a guard that rejects a page of a nested router when the guards are reevaluated now updates the
  url, replacing the closed page's entry, and a nested router left empty that way shows its first page again instead
  of keeping the closed page on screen (#1740).
- **FIX**: `replaceAll` listing an open parent and then one of its children, such as `[MainRoute(), SearchRoute()]`,
  no longer fails Flutter's duplicate page key assertion (#1586).
- **BEHAVIOR CHANGE**: a tab opened by a url, such as after a browser refresh, keeps the args its `AutoTabsRouter`
  `routes` list gives it, instead of throwing `MissingRequiredParameterError`. A url with path or query params still
  builds the args from those (#2107).
- **FIX**, **BEHAVIOR CHANGE**: `AutoRouter.declarative` gets the routes a link opens: `handler.initialPendingRoutes`
  now holds them when the routes callback first runs. It was always `null`, so a refresh or link at a nested page showed
  the list and put the wrong url in the address bar.
- **FIX**, **BEHAVIOR CHANGE**: `onNavigate` of `AutoRouter.declarative` runs once per navigation. A navigation that
  came through a parent router, such as a browser back or a platform link, ran it twice.
- **FIX**: `pop` on the only page of a router built by `AutoRouter.declarative` closes the page that holds the router. It
  took the page away and left a blank screen.
- **FIX**, **BEHAVIOR CHANGE**: `AutoRouter.of` and `context.router` in a page of `AutoRouter.declarative` return that
  declarative router, as `RouterScope.of` always did. They returned the router above it, so `router.parent()` was one
  level too high. `push`, `replace`, `navigate` and paths still reach the router that can take the route. What now acts
  on the declarative router: `stack`, `current`, `pop`, and `popUntil` and its kin, which stop at it; call them on
  `router.parent<StackRouter>()` to reach the router above.
- **FIX**, **BEHAVIOR CHANGE**: off the web, with `includePrefixMatches: false`, a platform link that reaches an app still
  showing the page it launched with, and that has stayed on screen since, takes that page's place, unless a guard
  rejects it. iOS hands the link of a cold start over after the first frame, so the stack held the home page below the
  link's page.
- **BEHAVIOR CHANGE**: `AutoTabsRouter` passes a new `backThroughHistory` on when it is rebuilt with one, so back
  follows the latest value. Turning it off forgets the tab history.

## 12.5.0
- **CHORE**: the lint setup is simpler: `lines_longer_than_80_chars`, `prefer-single-widget-per-file`,
  `prefer-prefixed-global-constants` and `prefer-match-file-name` are off, and DCM runs its recommended rules plus a
  short list.
- **FIX**: reading a page, tab, guard or url segment past the end of its list no longer throws inside the router; what
  isn't there is skipped.
- **CHANGE**: `StackRouter.replaceAll` with an empty list does nothing, instead of throwing a `StateError`. `pushAll` and
  `popAndPushAll` still assert in debug builds, and do nothing in release builds.
- **FIX**: `navigate<void>`, or `navigate` with any named type, no longer rebuilds the pages on its way to the target when
  the app started through `DeepLink.path`, which reset the tabs inside them.
- **CHANGE**: `RouteMatch.toString` shows its key's hash code, and a guard without a `toString` of its own prints as
  `AutoRouteGuard(<hash>)`.
- **FEAT**: `AutoRouteGuard.simple`, `redirect` and `redirectPath`, `DefaultRouteParser` and `AutoRouteAware` can be
  created with `const`.
- **CHANGE**: `AutoTabsScaffold.bottomNavigationBuilder` gets a context below the `Scaffold`, so `Scaffold.of(context)`
  works in it.
- **FIX**: two edge shadows of a Cupertino transition with the same colors now compare equal, so a rebuild doesn't
  repaint them.

## 12.4.0
- **FEAT**: `AutoRouter` and `AutoRouter.declarative` take a `heroControllerBuilder`, so Heroes fly between two pages
  of a nested router: pass `MaterialApp.createMaterialHeroController` or `CupertinoApp.createCupertinoHeroController`,
  and the router disposes the controller it creates. Left out, `AutoRouter` flies none, as before (#372,
  flutter/flutter#90103).
- **BEHAVIOR CHANGE**: `AutoRouter.declarative` no longer creates a hero controller by itself; pass
  `heroControllerBuilder` to keep hero animations between its pages.
- **BREAKING CHANGE**: every `RouteMatch<dynamic>` in the API is `RouteMatch<Object?>`, among them `RouteData.route`,
  `RouteData.topMatch`, `RoutingController.topMatch`, `NavigationResolver.route` and `RouteMatch.children`, so a match's
  `args` is `Object?`, no longer `dynamic`. Read it with a cast, `match.args as MyArgs`, or with
  `routeData.argsAs<MyArgs>()`.
- **BREAKING CHANGE**: every `RouteData<dynamic>` in the API is `RouteData<Object?>`, among them `RouteData.of`,
  `context.routeData`, `context.topRoute`, `RoutingController.current`, `topRoute` and `stackData`,
  `AutoRoutePage.routeData` and the `AutoRoutePageBuilder` and `RouteDataPredicate` callbacks, so the result `popped`
  completes with is `Object?`. Read it with a cast, `await routeData.popped as bool?`.
- **BREAKING CHANGE**: every `Route<dynamic>` in the API is `Route<Object?>`: the `didPush`, `didPop` and `didRemove` of
  `AutoRouterObserver`, and `PagelessRoutesObserver`'s `current`, `routeOf`, `topPageRoute`, `routeWhere`,
  `pagelessRoutesOver` and observer methods. An override that names `Route<dynamic>` still compiles, as the two types
  are interchangeable there; a route read from them gives `Object?` where it gave `dynamic`, so cast what it returns,
  `await route.popped as bool?`.
- **BREAKING CHANGE**: every `AutoRoutePage<dynamic>` in the API is `AutoRoutePage<Object?>`: `RoutingController.stack`
  and `topPage`, `KeepAliveTab.page` and the `PageBuilder` callback. Code that declares one of these types names
  `AutoRoutePage<Object?>`, and a value read through it is `Object?`, read with a cast.
- **BREAKING CHANGE**: `AutoRoutePage.canUpdate` and `PagelessRoutesObserver.routeOf` take a `Page<Object?>`, not a
  `Page<dynamic>`. A subclass that overrides `canUpdate` with `Page<dynamic>` still compiles; write `Page<Object?>` to
  match.
- **BREAKING CHANGE**: `PendingRoutesHandler.peek` and `initialPendingRoutes` return `List<PageRouteInfo<Object?>>?`,
  not `List<PageRouteInfo<dynamic>>?`. Code that stores the list names `PageRouteInfo<Object?>`.
- **BREAKING CHANGE**: `RouteData.animation` is an `Animation<double>?`, not an `Animation<dynamic>?`, the type of the
  route animation it holds, so `routeData.animation?.value` is a `double`. Code that sets it passes the route's own
  `animation`, as before.
- **BREAKING CHANGE**: `ReevaluateListenable.stream` takes a `Stream<Object?>`, not a `Stream<dynamic>`. Any stream
  still fits, so a call needs no change; code that tears the constructor off as a function names `Stream<Object?>`.
- **BREAKING CHANGE**: `Parameters.get` takes and returns `Object?`, not `dynamic`, and
  `UrlState.normalizeQueryParamValue` does the same. Read a typed value with `getString`, `getInt` and their kin, or
  cast, `params.get('id') as String?`.
- **BREAKING CHANGE**: each file in `lib/src` is named after the first type it declares. Only imports of
  `package:auto_route/src/...` change; every name an app writes stays. Old → new, all under `src/`:
  `common/auto_route_annotations.dart` → `common/auto_router_config.dart`,
  `common/auto_route_observer.dart` → `common/auto_router_observer.dart`,
  `route/auto_route_config.dart` → `route/auto_route.dart`,
  `route/errors.dart` → `route/missing_required_parameter_error.dart`,
  `router/controller/controller_scope.dart` → `router/controller/router_scope.dart`,
  `router/controller/route_leave.dart` → `router/controller/auto_route_leave_listener.dart`,
  `router/controller/navigation_history/navigation_history.dart` →
  `router/controller/navigation_history/stub/navigation_history_impl.dart`,
  `router/controller/navigation_history/native_navigation_history.dart` →
  `router/controller/navigation_history/native/navigation_history_impl.dart`,
  `router/controller/navigation_history/web_navigation_history.dart` →
  `router/controller/navigation_history/web/navigation_history_impl.dart`,
  `router/controller/navigation_history/navigation_history_base.dart` →
  `router/controller/navigation_history/navigation_history.dart`,
  `router/parser/route_information_parser.dart` → `router/parser/default_route_parser.dart`,
  `router/transitions/custom_page_route.dart` → `router/transitions/auto_page_route_builder.dart`,
  `router/transitions/predictive_back_page_detector.dart` → `router/transitions/predictive_back_gesture_detector.dart`,
  `router/widgets/custom_cupertino_transitions_builder.dart` →
  `router/widgets/cupertino_route_transition_override_mixin.dart`.
- **CHORE**: DCM's `prefer-boolean-prefixes` and `prefer-correct-callback-field-name` are switched off for now, so
  the package's own booleans and callback fields keep their names; every other analyzer and DCM rule stays on.

## 12.3.0
- **BREAKING CHANGE**: `Parameters.optBool` and `getBool` take their default by name:
  `getBool('key', defaultValue: false)` instead of `getBool('key', false)`. Routers generated by auto_route_generator
  write the new form; regenerate them.
- **BREAKING CHANGE**: `MissingRequiredParameterError` is an `Exception`, no longer an `Error`; catch it with
  `on MissingRequiredParameterError`. Its name and message are unchanged.
- **BREAKING CHANGE**: `RouteMatch.copyWith(pathParams:)` is removed; pass `params:`.
- **BREAKING CHANGE**: `ReevaluatableRouteMatch.copyWith(pathParams:)` is removed; pass `params:`.
- **BREAKING CHANGE**: `PageRouteInfo.copyWith(params:)` is removed; pass `rawPathParams:`.
- **BREAKING CHANGE**: `PageRouteInfo.copyWith(queryParams:)` is removed; pass `rawQueryParams:`.
- **BREAKING CHANGE**: `PageRouteInfo.copyWith(children:)` is removed; pass `initialChildren:`.
- **BREAKING CHANGE**: `PageRouteInfo.copyWith(path:)` is removed; it was ignored, since a `PageRouteInfo` holds no
  path, so drop the argument.
- **BREAKING CHANGE**: `PageRouteInfo.copyWith(match:)` is removed; it was ignored, since a `PageRouteInfo` holds no
  match, so drop the argument.
- **BREAKING CHANGE**: `RouteData.setAnimation(animation)` is removed; set `routeData.animation = animation`.
- **BREAKING CHANGE**: `NavigationResolver.next(bool continueNavigation)` no longer takes a bool; call `next()` to
  continue or `reject()` to stop.
- **BREAKING CHANGE**: `NavigationResolver.resolveNext(bool continueNavigation, {bool reevaluateNext})` is removed;
  call `next()`, or `reject(reevaluateNext: false)` to stop, or `overrideNext(reevaluateNext: false)` to continue
  without pushing the pending routes again.
- **BREAKING CHANGE**: `NavigationResolver.nextOrBack(bool continueNavigation)` no longer takes a bool; call
  `nextOrBack()` to continue or `reject(goBack: true)` to stop and go back.
- **BEHAVIOR CHANGE**: on the web, a WillPopScope no longer blocks the browser back button; use PopScope, which Flutter replaced it with in 3.12 and which still blocks it (#1588).
- **FEAT**: `PathParam.inherited` says whether a path param is inherited from a parent route; the generator reads it.
- **CHORE**: every analyzer and DCM rule is on, with no rule switched off and no ignore; the code is formatted at 80
  columns, and CI checks that it stays so.

## 12.1.0
- **FEAT**: path and query params can be the app's own types: give `@PathParam` or `@QueryParam` a
  `ParamConverter<T>`, a top-level const, and the route reads the param with the new `Parameters.getTyped` or
  `optTyped` and writes it back with `toParam` (#1794).
- **FEAT**: a page class with type parameters gets a generic route: `PickerPage<T>` gives `PickerRoute<T>`, and
  `push<int>(PickerRoute<int>(...))` builds `PickerPage<int>`; a page opened from a link gets each type
  parameter's bound (#2050, #1879, #1739).
- **FEAT**: in debug builds, two routes with the same full path make the router throw a `FlutterError` naming
  both when it first reads its routes; paths that differ only in param names count as the same
  (flutter/flutter#190741).
- **FEAT**: `AutoTabsRouter` and `AutoTabsScaffold` take `backThroughHistory`: back shows the tabs visited before,
  the latest first, then leaves the tabs (#1789, #830).
- **FEAT**: `AutoTabsRouter.tabBar` and `AutoTabsRouter.pageView` take `lazyLoad`; `false` builds every tab's page
  up front (#2013).
- **FEAT**: every page's semantics carry its route name as their identifier, so UI testing tools such as Appium and
  Maestro, and `find.bySemanticsIdentifier` in widget tests, find a page by its route name, whatever its route
  type (#2115).
- **FEAT**: `CustomRoute(enableCupertinoBackGesture: true)`, also on `RouteType.custom`, keeps the iOS back swipe on a
  page with a custom transition, on iOS and macOS (flutter/flutter#183252).
- **FEAT**: `router.waitForTransitions()` completes once every page has stopped moving after a push, a replace or a
  pop, for example to open a bottom sheet once a page has come in (flutter/flutter#162789).

## 12.0.0
- **BREAKING CHANGE**: `RouteMatch.pathParams` and `RouteData.pathParams`, deprecated since 11.2.0, are removed;
  use `params`.
- **BREAKING CHANGE**: the `durationInMilliseconds` and `reverseDurationInMilliseconds` parameters of `CustomRoute`
  and `RouteType.custom`, deprecated since 11.2.0, are removed; pass `duration` and `reverseDuration`.
- **BREAKING CHANGE**: the `animatePageTransition` parameter of `AutoTabsRouter.tabBar`, deprecated since 11.2.0, is
  removed; pass `duration: Duration.zero` to switch tabs without animating.
- **FIX**: an app can catch a bad path param's error by its type: `MissingRequiredParameterError` is exported
  from `package:auto_route/auto_route.dart` (flutter/flutter#155598).
- **FIX**: a page view tabs router with a zero duration switches tabs without animating (#1150).
- `NavigationHistory`, the type of `router.navigationHistory`, is exported from `package:auto_route/auto_route.dart`,
  so an app can name it in a variable, a parameter or a test.
- **DEPRECATION**: passing a bool to `NavigationResolver.next` is deprecated; call `next()` to
  continue and the new `reject()` to stop, so `resolver.next(false)` becomes `resolver.reject()`.
- **DEPRECATION**: passing a bool to `NavigationResolver.nextOrBack` is deprecated;
  `nextOrBack(false)` becomes `reject(goBack: true)`.
- **DEPRECATION**: `NavigationResolver.resolveNext` is deprecated. `resolveNext(true, reevaluateNext: false)`
  becomes `overrideNext(reevaluateNext: false)`, and `resolveNext(false, reevaluateNext: false)`
  becomes `reject(reevaluateNext: false)`.
- **BREAKING CHANGE** (behavior): the futures of `pushAll` and `popAndPushAll` complete once every
  guard has decided, instead of at once, as `replaceAll`'s already did. Code after `await router.pushAll(...)` now sees
  the new stack, or the old one when a guard rejected it; don't await it inside a guard of the same
  routes.
- **BREAKING CHANGE** (an analyzer warning only): `Parameters`, `PageInfo`, `RouteType`,
  `RouteCollection`, `HierarchySegment` and `AutoRouteInformation` are `@immutable`, since they
  define `==`. A subclass with a field that isn't `final` now gets `must_be_immutable`; make it final.
- **DEPRECATION**: `copyWith` takes each field's own name. On `PageRouteInfo`, write `rawPathParams`,
  `rawQueryParams` and `initialChildren` instead of `params`, `queryParams` and `children`, and drop
  `path` and `match`, which did nothing; it can now also set `stringMatch`, `redirectedFrom` and
  `argsEquality`. On `RouteMatch`, write `params` instead of `pathParams`; it can now also set `id`.
- **BREAKING CHANGE**: `CupertinoRoute`, `AdaptiveRoute` and `CustomRoute` no longer take a type
  argument, which they never used. Write `CustomRoute(...)` instead of `CustomRoute<void>(...)`.
- **BREAKING CHANGE**: `OnNavigationChanged` is `void Function(TabsRouter)`, and `popAndPushAll`'s
  `onFailure` is an `OnNavigationFailure?` instead of `dynamic`. Callbacks written as closures
  compile as before; pass `onFailure` a `void Function(NavigationFailure)`, as `pushAll` takes.
- **DEPRECATION**: `RouteData.setAnimation(a)` is deprecated; write `routeData.animation = a`.
  `RouteData.animation` can now be read too. `RouteData.args` stays `Object?`: a route's args can be
  any class, so read them typed with `argsAs<T>()`.
- **BREAKING CHANGE**: `NavigationResolver.redirectUntil` returns `Future<void>` instead of `void`,
  completing once the redirect route closes. Calls compile as before; a class that overrides it
  must return `Future<void>`, and a lint that asks for it is answered with `unawaited(...)`.
- **CHORE**: require Dart 3.13, the version Flutter 3.47 ships. The package already required
  Flutter 3.47, so no app that could use it before is left out.
- **BEHAVIOR CHANGE**: `pushAndPopUntil` now removes the routes below the new page instead of
  popping them, like `Navigator.pushAndRemoveUntil`, so they no longer flash while the new page
  slides in. Navigator observers get `didRemove` for those routes, not `didPop`; the PopScope of
  the removed routes is not asked; their push futures complete with null. They are removed only
  once the new page's guards let it through, so a rejected push leaves the stack as it was,
  fixes #1797
- **BEHAVIOR CHANGE**: urls split only at '/' on every platform, so on Windows a backslash in a
  route path no longer separates segments, and `RouteData.match` joins segments with '/', not '\'.
- **FIX**: on web, a url whose first segment ends in ':' (like `/c:/files`) keeps its leading '/'.
- **FIX**: a `CustomRoute` or `RouteType.custom` with `barrierDismissible: true` pops on a tap on its
  barrier; the flag had no effect. `CustomRoute`'s `barrierDismissible` now defaults to false, as
  `RouteType.custom` and `PageRouteBuilder` do, so a route that doesn't set it behaves as before.
- **BREAKING CHANGE**: `auto_route` requires Flutter 3.47 (its pubspec now says so; it imported
  `material_ui` and `cupertino_ui`, which already needed it, and on older Flutter pub's error named
  those packages instead of this one). Upgrade Flutter, or stay on the release you use.
- **BEHAVIOR CHANGE**: an enum query parameter is read and written by its name. Before, a page
  with `@QueryParam('type') CartType? type` opened from `/cart?type=rm` threw a type error, and a
  push wrote `type=CartType.rm`. Now the url holds `type=rm`; an unknown name reads as null, or as
  the default. Regenerate your router; a link you saved in the old `CartType.rm` form no longer
  reads, fixes #2148
- **BEHAVIOR CHANGE**: a path param holding '/', '?' or '#' is encoded in the url and read back
  whole: `FilesRoute(path: 'reports/2024')` is `/files/reports%2F2024`, and a link with `%2F` no
  longer splits into two segments. `currentUrl` also keeps `=`, `&`, `+` and the other delimiters
  of a param encoded, so opening `currentUrl` again reads the same query, fixes #2070, #1925
- **BEHAVIOR CHANGE**: every tab change asks the tab route's guards, as a stack asks before a push.
  A tab whose guard rejects no longer shows when you call `setActiveIndex`, navigate to it, open
  its url or swipe to it; a guard that decides later (`redirectUntil`) keeps the current tab until
  then. Guards in `RootStackRouter.guards` are still not asked for tabs. A guard on a tab route
  that rejected without anyone noticing now takes effect, fixes #2218
- **BEHAVIOR CHANGE**: a guard that redirects a route to itself (`redirectUntil` to a route its
  own guard sends back) now reports a `FlutterError` naming the route and rejects the navigation,
  instead of looping to a white screen, fixes #2213, #1818
- **BEHAVIOR CHANGE**: `replace()` removes the page only once the new route's guards let it
  through, so a rejected `replace()` keeps the page and the url, fixes #2046. `replaceAll()` keeps
  the old pages until then and, when a guard rejects one of the new routes, puts them back: a
  rejected route rejects the whole batch, in nested routers too, fixes #2299
- **BEHAVIOR CHANGE**: a page whose required args weren't saved is left out of a restored stack
  instead of failing, fixes #2098
- **BEHAVIOR CHANGE**: `AutoRouteObserver` tells the popped page `didPop` before it tells the page
  under it `didPopNext`, on a pop and on a remove that uncovers a page; before, the page under
  heard first. A push already ran in this order, flutter/flutter#26902
- **BEHAVIOR CHANGE**: `navigate()` from a tab to a route that is a child of the tabs host's route
  but not one of its `AutoTabsRouter`'s routes now calls `onFailure` with a
  `RouteNotFoundFailure`, or throws; before, it did nothing, fixes #1371
- **BEHAVIOR CHANGE**: `popUntil` and `popUntilRoot` remove the pages between the top page and the
  one the predicate meets, then pop the top page with its animation, so the pages in between no
  longer show. Navigator observers hear `didRemove` for those pages, not `didPop`; their push
  futures complete with null as before, flutter/flutter#59990
- **BEHAVIOR CHANGE**: two `RedirectRoute`s that point at each other report a `FlutterError`
  naming the loop instead of overflowing the stack, flutter/flutter#104441
- **BEHAVIOR CHANGE**: a global guard's `redirect()` or `redirectPath()` that redirects again to
  where it came from, and two guards whose `redirectUntil()` send the user to each other's route,
  now report a `FlutterError` naming the loop and reject the route, instead of overflowing the
  stack or opening pages without end, flutter/flutter#118061
- **BEHAVIOR CHANGE**: `replace()` with a route of the same name and no children opens the route's
  initial child, as `navigate()` with the same route does; before, the nested router kept the child
  it showed. A route with no initial child still keeps it.
- **FEAT**: routers save their pages for state restoration (off the web): every page's name, path,
  query params and fragment, and each nested router's pages. Route args are your own objects and
  are not saved, so a page that needs required args is left out when restored.
- **FIX**: state restoration brings back every page of every stack and every tab, not only the
  one in the url, fixes #2040, #2041, #2099
- **FIX**: `Parameters.optBool` and `getBool` no longer crash on a bool pushed in code
  (`NamedRoute('Flag', queryParams: {'f': true})`) or restored by state restoration, fixes #2222
- **FIX**: `optString` and `getString` no longer throw a `TypeError` when the url repeats a query
  key (`/products?tag=red&tag=blue` reads the last value, `blue`) or when a number was pushed
  (`{'page': 2}` reads as '2').
- **FIX**: `AutoRouter.declarative(key: ...)` uses the key it is given.
- **FIX**: since 11.2.0 pages ignored the app's `Theme.pageTransitionsTheme` when the app's
  `MaterialApp` came from `package:flutter/material.dart`; they use it again, fixes #2340
- **FIX**: a deferred page popped before its library loads no longer throws "setState() called
  after dispose()".
- **FIX**: leaving a page no longer leaks, one more object on each visit, in a nested router, an
  `AutoTabsRouter` (the tab fade animation, and the `PageController` of `.pageView` and the tab-bar
  view) or an `AutoRouter.declarative` (its `HeroController`). Disposing a `RootStackRouter` now
  disposes its delegate, url provider and navigation history too, and disposing them twice is safe.
- **FIX**: a navigation stops when its nested router is disposed while a guard runs, fixes #2248
- **FIX**: a nested router keeps its open pages when its page builds it in another place, such as a
  list-detail page when a foldable phone folds.
- **FIX**: a pushed route with children keeps its fragment in the url (`/books#top`, not `/books`);
  `PageRouteInfo.copyWith` no longer drops `fragment`, `stringMatch`, `redirectedFrom` or
  `argsEquality`.
- **FIX**: on web, a deep link to an app that builds its router after the first frame keeps one
  history entry.
- **FIX**: on web, a deep link with an encoded character adds no second history entry.
- **FIX**: on web, the browser's back button leaves a page whose query params changed in place (`/page` to
  `/page?p=true`): it shows `/page` again, instead of staying on `/page?p=true`, flutter/flutter#108714.
- **FIX**: on web, the browser forward button returns to a page pushed over one with the same url.
- **FIX**: on web, going back returns to a previous page with the same url, such as a `Book` page
  pushed twice with different args.
- **FIX**: on web, a url with a letter outside ASCII follows the pages; a '#' in a path param
  survives a refresh, fixes #1812
- **FIX**: `back()` and the browser's back button return to the first of a route pushed twice with
  equal arguments, instead of the page before both; `back()` twice in a row works, and on native
  platforms `back()` over two pages with the same url returns to the first.
- **FIX**: the args and the children a guard sets with `overrideNext` show on the page and open
  in its nested router, also on a guard re-check.
- **FIX**: a guard re-check no longer runs an async simple guard twice.
- **FIX**: a page popped while guards are reevaluated stays closed, fixes #1643, #1785
- **FIX**: `replaceAll()` right after the reevaluate listenable changes replaces the stack, fixes #2172
- **FIX**: `replaceAll` and `pushAll` open routes of a closed nested router together, fixes #2214
- **FIX**: `popAndPushAll` from a router's only page replaces that page, fixes #1948
- **FIX**: `removeWhere` on a page below a page of the same route no longer removes the top page,
  fixes #1943
- **FIX**: a guard's redirect page leaves no history entry behind, fixes #2331
- **FIX**: awaiting `pushAll` waits for its guards to decide (see the breaking change).
- **FIX**: `pushAndPopUntil` no longer shows the pages it removes, fixes #1797
- **FIX**: `pushAndPopUntil(scopedPopUntil: false)` removes the pages a nested router's predicate
  rejects instead of animating them out, and leaves the page of a nested router that goes with its
  shell under the new page, not a blank shell (#1797).
- **FIX**: `navigate()` opens the right tab when two tabs share a route, keeps the path params it
  inherits (#1816), and fills a path param into the parent path that holds it (#2066).
- **FIX**: `navigatePath()` with an absolute path from a nested page opens its page, fixes #2317
- **FIX**: `currentHierarchy()` lists the children of a router nested twice, fixes #2321
- **FIX**: a tabs page opened at its own url (`/tabs`) now records its first tab in the url, so
  going back to that entry from another tab shows the first tab.
- **FIX**: observers hear `didInitTabRoute`, not `didChangeTabRoute`, when a swipe opens a tab
  for the first time.
- **FIX**: the url follows the active tab when two tabs share a parent route, fixes #1874
- **FIX**: removing a tab before the active tab keeps the active tab shown (#1786, also in the page-view kind); removing the
  active tab no longer throws a `RangeError` (#2308); a tab-bar `AutoTabsRouter` removed
  mid-animation no longer crashes (#1765).
- **FIX**: screen readers work again in `AutoTabsRouter.pageView` and `.tabBar`: tabs beside the
  open tab no longer reach them, fixes #2170
- **FIX**: back on a tab away from the home tab shows the home tab instead of closing the app on
  Android 13 and later, fixes #2059; back acts on the tab on screen, not a hidden one, fixes #2225
- **FIX**: a `PopScope` on a declarative nested router's page blocks the back gesture, fixes #2023
- **FIX**: a Hero flies from a page to the first page of a nested router, fixes #2024, #1873
- **FIX**: a `customRouteBuilder` page shows new query params after `replace()`, fixes #1857
- **FIX**: observers hear the right events: `navigateTo()` back to a page right after closing a
  dialog tells it `didPopNext` (#1774); a page in a nested router hears `didPop` when its host
  route is popped (#1863) and hears its host route covered and uncovered (#1954).
- **FIX**: "Can not resolve initial route" names the link no route matched and the catch-all
  `RedirectRoute(path: '*', redirectTo: '/')` that answers it, fixes #2119
- **FIX**: the example app builds for Android again on Flutter 3.47.
- **FIX**: routes with equal list or set url params are equal and hash equally, so
  `TagsRoute(tags: {'a'}) == TagsRoute(tags: {'a'})`.
- **FIX**: a path param whose name starts another param's name expands whole: with params `id`
  and `idx`, `/a/:idx` no longer becomes `/a/1x`, also through a `RedirectRoute`.
- **FIX**: `pop()` right after `push()` closes the pushed page instead of the page under it; on
  the first page it no longer leaves only the pushed one, flutter/flutter#145573. System back,
  `pop` or `maybePop` in the same frame as `replaceAll([Home])` keeps the new page instead of
  leaving none.
- **FIX**: `navigate`, `navigatePath` and `replaceAll` close the routes pushed with
  `Navigator.push` over the page they land on, flutter/flutter#171962
- **FIX**: a pushed page's future completes with its route's `currentResult` when the back gesture
  or system back closes it, as `Navigator.push` does, instead of null, flutter/flutter#171130
- **FIX**: two buttons pressed at once open only the first page, and a finger lifted from a
  button after another page opened over it opens nothing, flutter/flutter#160504
- **FIX**: opening a deeper page by its path (`/a`, then `/a/b`) no longer builds the pages under
  it again, flutter/flutter#147639
- **FIX**: routes added to the router before a hot reload open by path, push or link, also as
  children of a nested router on screen, flutter/flutter#105553
- **FIX**: on web, the browser's back button walks back through one route pushed several times
  with different params, flutter/flutter#186052
- **FIX**: on web, the browser's back button leaves the login page a guard redirected to after a
  logout, instead of showing it again on every press, flutter/flutter#135359
- **FIX**: on web, an app the user comes back to with the browser's back button, or reloads, reads
  the state it saved with `pushPathState`, instead of null, flutter/flutter#108697
- **FIX**: with state restoration, a link that starts an app the platform ended in the background
  opens its page instead of being ignored, flutter/flutter#161858
- **FIX**: a page built under a deep link (Home under `/b`) hears `didPushNext` when it subscribes
  to `AutoRouteObserver`, flutter/flutter#70272
- **FIX**: a widget with `AutoRouteAwareStateMixin` shown in a dialog no longer throws,
  flutter/flutter#62023
- **FIX**: widgets laid out before a nested router stay in the semantics tree, so screen readers
  read them, flutter/flutter#150978
- **FIX**: the predictive back gesture belongs to the page on screen when a nested router sits
  under a root page, flutter/flutter#152323
- **FIX**: a page closed in the same frame as its dialog animates out with it instead of
  vanishing at once, flutter/flutter#111137
- **FIX**: an empty list query param leaves no '?' at the end of the url (`/items`, not `/items?`),
  flutter/flutter#127373
- **FIX**: a path param named with a '$' (`:user$id`) is filled into the url, fixes #1163
- **FIX**: `replace()` and `pushAndPopUntil()` with a route of the same name and new nested
  children show only those children; before, both kept the nested pages they showed, fixes #1363
- **FIX**: `popUntilRouteWithName` and `popUntilRouteWithPath` with a page that isn't in the stack
  stop at the first page instead of leaving a blank screen, fixes #1502
- **FIX**: `pushPath` of an unknown relative path in a nested router calls `onFailure`, or throws,
  instead of pushing the router's first page again, fixes #1648
- **FIX**: a link that comes while the first page waits on its guard keeps its pages, instead of
  the first page coming back on top once its guard resolves, fixes #1668
- **CHORE**: `AutoRoutePage` no longer removes a popped page from its router's stack itself. It did
  so to stop a flicker on Flutter 3.38 to 3.41 (flutter/flutter#178570), which Flutter 3.44 fixed.
- **PERF**: a url is matched against the routes several times faster, and the matcher splits urls
  at '/' itself; a tab switch builds the readable url once instead of on every read.
## 11.2.0
- **CHORE:** Migrate to material_ui and cupertino_ui packages
## 11.1.0
- **CHORE:** deprecate animatePageTransition #2301
- **Enhance:** add .named constructor to PageRouteInfo and AutoRoute to enable usage for shorthand
  named routes without code generation.

## 11.0.0 [Breaking Changes]

- **BREAKING CHANGE**: The `redirectUntil` method now returns `void` instead of `Future<T?>` and
  handles the completion of the pop completer internally
- **BREAKING CHANGE**: The `redirect` method in `AutoRouteGuard` has been renamed to `redirectUntil`
  to better reflect its behavior and avoid confusion
- **BREAKING CHANGE**: Removed deprecated APIs: `navigateNamed`, `popForced`, `replaceNamed`,
  `pushNamed`, and `navigateNamedTo`. Use `navigatePath`, `pop`, `replacePath`, `pushPath` instead

## 10.3.0

- **FEAT**: Correct back-navigation behavior with proper state tracking
- **FEAT**: Add async support and debug labels to `AutoRouteGuard`
- **FEAT**: Add `checkGuard` method to `NavigationResolver` for sequential guard execution
- **FEAT**: Implement comprehensive navigation history tracking with proper state management
- **FEAT**: Prevent duplicate consecutive entries in navigation history

## 10.2.3

- **REFACTOR**: Preserve match ID on route updates to prevent breaking child controllers during
  route updates or when replacing a route, fixes #2294
- **FIX**: AutoTabsRouter.tabBar: Switching non-adjacent tabs shows the initial tab briefly when
  tapping a tab then swiping, instead of the tab you're swiping toward, fixes #2283
- **REFACTOR**: Simplify PagelessRoutesObserver and address pop flicker by using the more efficient
  `didChangeTop` callback

## 10.2.2

- **FIX**: known predictive back gesture issues.
- **FIX**: add meta import to routing_controller.dart because some flutter versions require it.

## 10.2.1

- **FIX**: correctly handle parameter names by removing leading underscores
- **Enhance**: appBarBuilder in AutoTabsScaffold can return null now
- **FIX**: Fix WASM type mismatch.

## 10.2.0

- **FIX**: respect page.opaque for transparent route.
- **FIX**: handle dart:xxx.xxx.dart imports in type resolution (af60d79) when using lean_builder
- **REFACTOR**: introduce _genericRef function for improved type reference handling (d5ecf13)
- **FIX**: respect page.opaque for transparent route (52b71b7)
- **FIX**: Use immutable array for pending child routes, fixes #2210 (beb3ce0)
- **CHORE**:: extend support to analyzer 8 (b2cb61d)

## 10.1.2

- **FIX**: routing_controller.dart missing meta import

## 10.1.1

- **CHORE**: tidy up dependencies and sync with updated analyzer version.
- **FIX**: Add indexed stack semantics
- **FIX**: Allow PopCompleter to complete during route reevaluation when pop-completers are disabled

## 10.1.0+1

- **FEAT**: Add experimental support for lean_builder

## 10.1.0

- **FEAT**: Expose routeTraversalEdgeBehavior property from the underlying Navigator to allow
  customization of navigation stack edge behavior.
- **FIX**: Improve focus and semantics handling in AutoTabsRouter IndexedStack to exclude inactive
  tabs from focus traversal and semantics tree while preserving widget state.
- **FIX**: Fix tab routes observing issue where initiating tabs can be reported twice.
- **FIX**: Fix a couple core reevaluation issues.
- **FIX**: Generated code is not properly formatted #2174
- **FIX**: Fixed PageRouteInfo equality check regression introduced in v10.0.1 when using code
  generation with argsEquality: false, which now defaults to true. The equality operator no longer
  compares args by default unless argsEquality: true is explicitly set in AutoRouterConfig. This
  restores compatibility with previous versions and prevents navigation test failures due to custom
  argument classes lacking a proper == override.

## 10.0.1

- **REFACTOR**(custom_route): update route duration type from int to Duration.
- **FEAT**: add onGeneratePath callback to RootStackRouter to allow custom path generation.

## 10.0.0 [Minor Breaking Changes]

- **BREAKING CHANGE**: DeepLink and DeepLink.path will now use 'navigate' instead of push unless
  specified
- **BREAKING CHANGE**: ActiveGuardObserver.value will now return a GuardEntry instead of an
  AutoRouteGuard, use 'activeGuards' to get the list of active guards
- **FEAT**: add support for using auto_route with out code generation using NamedRouteDef and
  NamedRoute
  otherwise.
- **FEAT**: add support for android's predictive back gesture
- **FEAT**: optional args equality by setting AutoRouterConfig(argsEquality: true)
- **FEAT**: insert route method to StackRouter
- **FIX**: guard reevaluation was re-implemented to fix previous issues
- **FEAT**: expose Navigator.clipBehavior in both AutoRouterDelegate and AutoRouter
- **FIX**: using AutoTabsRouter.tabBar with maintainState: false and TabBar together, fails to load
  routes in some cases #2113
- **FEAT**: safe build context can now be accessed in AutoRouteGuard.onNavigation ->
  NavigationResolver.context
- **FEAT**: add a new way to override guarded routes using
  NavigationResolver.overrideNext
- **FIX**: AutoLeadingButton is not showing anything on a screen that combines
  AutoTabsScaffold and NestedRoute #2141
- **FIX**: redirect route doesn't pass query params the to redirectTo path
- **FIX**: generated PageRouteInfo breaks if widget tagged with @RoutePage parameter named
  children. #2149
- **FEAT**: add an AutoLeadingButton.builder to enable passing of nullable leading widget
- **FIX**: Fix a couple internal issues and migrate to using didRemovePage api
- **FEAT**: Parameters.getList now supports a default value
- **FIX**: Add required keyword to named required parameters in function parameters' arguments
- **FIX**: fix inheritPathParam didn't use the .inherit constructor
- **REFACTOR** rename a couple of apis (popForced -> pop, pushNamed -> pushPath, replaceNamed ->
  replacePath, navigateNamed -> navigatePath, pathParams -> params)

## 9.3.0+1

- **CHORE**: Fix some static analysis warnings

## 9.3.0

- **CHORE**: Resolve some deprecated APIs.

## 9.2.2

- **FIX**: Redirect route names are getting overridden in route collection.

## 9.2.1+1

No changes, changelog fix only.

## 9.2.1

- **CHORE**: Update web package to 1.0.0

## 9.2.0

- **FIX**: revert web package back to version ^0.5.1 because it's pinned in a lot of other packages.

## 9.1.0

- **FEAT**: Add query params options to redirectTo in RedirectRoute #1721.

## 9.0.1

- **FIX**: make EmptyShellRoute() a const.
- **Chore**: Add Declarative navigation example link
- **Chore**: Add Nested Navigation example link

## 9.0.0 [Breaking Changes]

- **BREAKING CHANGE**: No Router class will be generated anymore. Instead, you
  extend `RootStackRouter` from the `auto_route` package.
- **BREAKING CHANGE**: Providing return types inside `@RoutePage<Type>()` is no longer needed. you
  just provide the type as you push the page.
- **BREAKING CHANGE**: Providing a global route is now done by overriding the `guards` property
  inside the router. implementing AutoRouteGuard is no longer supported.
- **BREAKING CHANGE**: `AutoRouterConfig.module` is removed as it's no longer
  needed. `PageRouteInfos` are now self-contained.

For more info read the complete migration guide
[Migrating to v9](https://github.com/Milad-Akarie/auto_route_library/blob/master/migrations/migrating_to_v9.md)

- **FIX**: Fix Aliased types are not generated correctly.
- **FEAT**: You can now create empty shell routes like follows:
  ```dart
     const BooksTab = EmptyShellRoute('BooksTab');
     context.push(BooksTab());
  ```

## 8.3.0

- **FEAT**: add url#fragment support.
- **FIX**: queryParams are not passed to child routes when matching by route name
- **FIX**: array query params are not parsed correctly.

## 8.2.0

- **FEAT**: migrate conditional import to js_interop.
- **FEAT**: update to web library.

## 8.1.4

- **FIX**: fix an error when popping a nested route after flutter 3.22.0 #1973.

## 8.1.3

- **FIX**: Fixed back gesture when nested navigator only has multi nested entries.
- **FIX**: Can not swipe back on iOS when using nested navigation #1932.

## 8.1.2

- **FIX**: Fixed back gesture when nested navigator only has one entry #1940

## 8.1.1

- **FIX**: Can not swipe back on iOS when using nested navigation #1932.

## 8.1.0

- **FEAT**: add deep-link transformer. Allows parsing the URI for deep links before the
  route matcher performs a match on the URI. Especially useful when you use intent-filter
  prefix on Android to only handle links from e.g com.example/FILTER.

  ```dart
  RouterConfig `<UrlState>` config({
  deepLinkTransformer : Deelkink.prefixStripper('FILTER'),
  )
  ```

  The resulting URI will be : com.example

## 8.0.2

- **FIX**: only disable parent back gesture if the active child can pop.
- **FIX**: AutoTabsRouterTabBarState was disposed with active Ticker #1910

## 8.0.1

- **FIX**: back-gesture does not respect sub-routes.

## 8.0.0

- **FEAT**: AutoTabsRouter will now use the declared routes if AutoTabsRouter.routes is not
  provided, if any of the tabs has required parameters it will throw an error.
- **BREAKING CHANGE**: deep-links with no host e.g scheme://page/sub-page are no longer
  automatically handled, flutter's deep-link handler will treat [page] as host so we end up
  with [/sub-page] as a path which of course not going to match. if your deep-links are hostless
  you'll need to handle them manually inside deepLinkTransformer or deepLinkBuilder.

## 7.9.2

- **HOTFIX**: fix an issue with deep-linking to tab-routes
- **CHORE**: remove deprecated apis

## 7.9.1

- **FIX**: incorrect top route information when deep-linking to an uninitialized tab route.

## 7.9.0

- **FIX**: unable to get the label for back button(previous route title) and current route title on
  CupertinoNavigationBar and CupertinoSliverNavigationBar #1795.
- **FIX**: CupertinoNavigationBar and CupertinoSliverNavigationBar unable to get route title and
  previous route title.
- **Fix**: PopScope.onPopInvoked not called when canPop is set to true,
- **Refactor**: rename router.pop to router.maybePop to avoid confusion
- **Refactor**: rename router.popTop to router.maybePopTop to avoid confusion
- **Refactor**: rename context.popRoute to context.maybePop

## 7.8.5

- **FEAT**: add back mixin to AutoRouteAware
- **FIX**: keep TabsRouter.homeIndex in sync with AutoTabsRouter.homeIndex

## 7.8.4

- **FIX**: Build Runner Efficiency Warning #1737
- **FIX**: ensure dynamic tab updates are handled in AutoTabsRouter.tabBar.
- **FEAT**: AutoRoute.copyWith

## 7.8.3

- **FIX**:

## 7.8.2

- **HOTFIX**: update sdk constrains to flutter: >=3.13.0 and dart: >=3.0.0 <4.0.0

## 7.8.1

- **FIX**: crash if pendingChildren are passed in as unmodifiable list.
- **DOCS**: Fix typos and a broken links.
- **REFACTOR**: remove usages of RouteInformation.location in favor of RouteInformation.uri

## 7.8.0

- **FEAT**: add PlatformDeepLink.initial flag to tell whether we're coming from setInitialRoutePath
  or setNewRoutePath.
- **FEAT**: add option to pass custom ignore_for_file rules to the generated file.
- **FEAT**: support the new allowSnapshotting flag.

## 7.7.1

- **FIX**: tab routes should be matched by key not name.

## 7.7.0

- **FEAT**: Add basic support to dart records.
- **FIX**: encoded path segments are not decoded in RouteMatch.pathParams
- **FIX**: encoded browser path is checked against a decoded matched path when deciding whether to
  replace route #1637

## 7.6.0

- **FEAT**: add 'scoped' argument to to StackRouter.removeUntil, if true the predicate will visit
  all StackRouters in hierarchy.
- **FEAT**: add 'scoped' argument to to StackRouter.popUntil, if true the predicate will visit all
  StackRouters in hierarchy.

## 7.5.0

- **FIX**: Uri percent-encoded characters encoded twice #1620.
- **FIX**: delegate missing arguments in auto_route_guard redirect.
- **FEAT**(auto_route): add `AutoPageRouteBuilder.opaque` argument.

## 7.4.0

- **FIX**: StackRouter.replaceAll does not work with nested tab-routes.
- **FEAT**: add optional flag to either update existing routes or not to StackRouter.replaceAll

## 7.3.2

- **FIX**: Remove guard from ActiveGuardObserver when resolved with false.

## 7.3.1

- **FIX**: DeferredWidget's default loader not working.
- **FEAT**: DeferredWidget will now take AutoRouterDelegate.placeholder value if provided

## 7.2.3

- **FEAT**: Add global guards reevaluate listenable
- **DOCS** Add reevaluate listenable docs to README.md
- **FEAT**: Add NavigationResolver.redirect method to auto-remove routes pushed by guards when
  resolving is complete
- **FEAT**: Add AutoRoute.guarded constructor for cleaner single guard implementation

## 7.2.0

- **FEAT**: add more flexible multi package support.
- **REFACTOR**: resolve some flutter 3.10 deprecations.
- **DOCS**(auto_route): fix typo.

## 7.1.0

- **FEAT**: add support to process files in micro-packages.

## 7.0.0

> Note: This release has breaking changes.

- **FIX**: deepLinkBuilder is not called on newRoutePath.
- **BREAKING** **CHANGE**: DefaultRouteParser.includePrefixMatches's value is now set to '!kIsWeb'
  instead of 'false'.
- **FEAT**: add rebuildStackOnDeepLink flag to rebuild the whole stack on incoming deep-links

## 6.4.0

- **REFACTOR**: deprecated initialDeepLink and initialRouts.
- **FEAT**: Added DeepLinkBuilder to validate or override platform deep-links
- **FEAT**: Added Route.data ext to get routeData of auto routes
- **DOCS**: Updated docs

## 6.3.0

- **FEAT**: Bring AutoRoute.initial back.

## 6.2.1

- **REFACTOR**: make AutoRouterState and AutoTabsRouterState public.

## 6.2.0

- Add public apis docs

# ChangeLog

## [6.1.0]

- The missing hierarchy to a pushed child-route will now be auto_created if there are no required
  args
- The root router can implement an AutoRouteGuard and guard all Stack-routes
- Add restorationId builder to AutoRoute
- Mark annotations with supported types [for static analysis]

## [6.0.5]

- Fix RouteMatch.fullPath is not joined properly
- Add helper method to get route match PageRouteInfo().match(context)

## [6.0.4]

- Fix inherited path params are not working in v6
- Add option to use cached_builds for more optimized generation

## [6.0.3]

- include merged pr's
- ## [6.0.2]
- Make AutoRoute.path call save

## [6.0.1]

- Fix bug with nested parent routes without path #1411

## [6.0.0+1]

- Use updated readme file

## [6.0.0]

- Fix secondAnimation value is always 0 in custom route transition

## [6.0.0-rc-7]

- Fix fullscreenDialog and maintainState flags are not passing to route data

## [6.0.0-rc-6]

- Fix topMostRouter is not always called on root-scope

## [6.0.0-rc-5] Breaking

- Fix but with new AutoTabsRouter.transition builder
- rename AutoRouteBuilder to auto_route_generator in build.yaml file to follow naming
  convention [breaking]

## [6.0.0-rc-4]

- Fix android back button closes App
- Add check for root routes must start with '/' or "*"

## [6.0.0-rc-3] Breaking

- Add transition builder to AutoTabsRouter and AutoTabsScaffold to only rebuild the body for
  animation and remove animation property from builder [breaking]
- Add router.currentHierarchy() helper method for debugging and testing.
- Add keepHistory flag to AutoRoute(), to remove route from stack on pushNext

## [6.0.0-rc-2]

- Fix CustomRoute.opaque not working

## [6.0.0-rc-1]

- Add path property to CustomRoute,CupertinoRoute and AdaptiveRoute
- Add functionality to push path states to browser history and read it

## [6.0.0-rc] Breaking

make sure you check
the [Migration guide](https://github.com/Milad-Akarie/auto_route_library/tree/v6.0.0_redesigned#migrating-to-v60)

- AutoRoute now takes a PageInfo object from the generated routes instead of Type
- Introduce @RoutePage() annotation to annotate routable widgets
- Routes are defined in the body of the router class instead of inside the annotation
- Remove replace @MaterialAutoRouter,@CupertinoAutoRouter ...etc with @AutoRouterConfig annotation
- Remove EmptyRouterPage & EmptyRouterScreen
- "initial" flag is removed now, use "/" for initial routes or empty path "" for nested-initial
  routes.
- Passing route guards is also changed now, instead of passing guards as types you now pass
  instances.
- Add title builder for AutoRoute(title: (ctx,data){})
- Docs are changed to reflect the new changes so make sure you re-read them.

---

## [5.0.4]

- Fix #1288

## [5.0.3]

- Fix redirect-route related issues
- Fix didChangeTabRoute not called when using AutoTabsRouter.tabBar()

## [5.0.2]

- Change analyzer constrains to support up to version 6.0.0
- Merge #1236
- Merge add opaque property to AdaptiveRoute #1224
- Merge readme.md file updates

## [5.0.1]

- Add ignorePagelessRoutes and ignoreChildRoutes property to AutoLeadingButton
- Add builder property to AutoLeadingButton
- Fix deferredLoading and AutoRouteWrapper are not working together

## [5.0.0]

- Add deferred loading support for web to enable code splitting for routes [By Garzas]
- Move EmptyRouterScreen and EmptyRouterPage to a separate file to avoid import conflict when using
  deferred loading.
- Fix a bug in Navigation History
- Add License file to root package
- Fix TabController dispose issue in AutoTabsRouter.tabBar
- Add neglectWhen call back to ignore reporting location to engine
- Remove universal_html dependency and implement own conditional html import

## [4.2.1]

- Fix AutoTabsRouter animation controller is disposed after super.dispose()
- merge readme fixes

## [4.2.0]

- Add generate-time check for unresolvable path params
- You can now access inherited path params using @pathParam annotation

## [4.1.0]

- Upgrade minimum Flutter SDK to 3.0.0
- Upgrade minimum Dart SDK to 2.17.0
- Fix PageView tabs implementation non-neighbor transition issue
- Add scroll physics and dragStart behavior to booth tabBar nad pageView implementations

## [4.0.1]

- Fix incompatibility issues with flutter 3.0.0
- fix reverseDurationInMilliseconds not being generated from router config

## [4.0.0] (Breaking changes)

- Refactor AutoRedirectGuard [Breaking Change]
- Add AutoRouteAwareStateMixin to minimize boilerplate for AutoRouteAware states
- Add NoShadowCupertinoTransitionsBuilder to remove unwanted shadow in nested cupertino routes
- Add PageView support to AutoTabsRouter
- Add TabBar support to AutoTabsRouter
- Add custom builder support to AutoTabsRouter
- Remove AutoTabsRouter.declarative implementation (replaced with builder) [Breaking Change]
- AutoRouter.declarative routes now accepts a PendingRoutesHandler instead of
  context [Breaking Change]
- Fix wrapped routes are rebuilt everytime the stack changes
- Fix query params are not updated in Tab-Routes
- Add router.activeGuardObserver to access active guards. e.g to implement loading indicator
- Fix initial route is not showing when nested router is rebuilt
- Replace AutoBackButton with AutoLeadingButton to support drawer and close icons

## [3.2.4]

- Fix path/query params are not updated in url when navigating to the same current path #854 #944

## [3.2.3+1]

- Remove forgotten print statement

## [3.2.3]

- Fix routes with empty path don't update url #960
- Fix RouteInformationProvider.routerReportsNewRouteInformation required 'type' issue #958

## [3.2.2]

-Add removeAllAndPush route strategy to auto_redirect_route

## [3.2.1]

- Merge some readme file typo-fixes
- Add @optionalTypeArgs to AutoRoute annotations
- Fix AdaptiveRoute issue with CustomRoute
- Change analyzer constrains to include version 3.0.0
- Add notify flag to removeWhere method inside of StackRouter

## [3.2.0]

- Merge fix conform new API in Flutter 2.6
- Fix declarative routes update issue
- Add Router tests

## [3.1.3]

- Fix navigateNamedTo does not update the stack #831
- Refactor navigation history and set kept history records to 20 entries max

## [3.1.2]

- Fix Bad state: No element exception when setting initialRoutes #826
- Fix conflict when param name is 'name' #824

## [3.1.1]

- Fix Regression bug (caused by immutable pendingRoutes list) #822

## [3.1.0]

- Prefer previous-current route index as new current index when updating tab routes #797
- Improve native navigation history
- Use browser history as navigation history in web
- Fix path/query params not updating issue #809
- Fix generic nullable types are generated as non-nullables #811
- Override toString method inside of generated arg classes [FR] #820
- Support redirect paths with path params [FR] #818
- Fix replace/replaceNamed/replaceAll do not replace current url in browser #781

## [3.0.4]

- Fix IndexedStack widgets are not updated on tabs routes change.
- Fix RangeError when updating routes in AutoTabsScaffold #788

## [3.0.3]

- Fix dynamic routes for AutoTabsScaffold don't work #783

## [3.0.2]

- Make AutoTabsScaffold builders rebuild on global routes hierarchy changes

## [3.0.1]

- Fix conflict with source_gen:combining_builder by using .gr.dart instead of .g.dart

## [3.0.0]

- Add option to use part builder .g.dart
- Add option to pass const meta data from annotation to consumed route data.
- Show better error message when router can not navigate to given route.
- ancestor router can now push directly to nested router if it's already in stack.
- Add navigateBack functionality
- Add AutoRedirectRoute which reevaluates guarded routes that's already in stack

## [2.4.2]

- Add fullscreenDialog flag to pushWidget method
- Add pushNativeRoute method

## [2.4.1]

- Fix pushing same route not rebuilding stack; effecting #717 #710
- Fix dialogs/bottom sheets don't play nicely with auto_route when using nested routers
- Add option to push an un-routable widgets to StackRouters
- Add a comment containing the widget type reference to generated routes for easy source jumping

## [2.4.0]

- Fix url updates delay
- Fix navigate does not update url
- Add auto_route_information_provider.dart to fix infinite browser back button when using url
  redirects
- optimize routes rebuild -> only rebuild if route data changes
- Change routers are now not ( Watched ) by default to reduce rebuilds [ may Break]
- Add optional homeIndex property to AutoTabsRouter to make sure we always pop from home tab
- Change AutoBackButton to use StackRouterScope instead of RouterScope

## [2.3.2]

- Merge fix(generator): Bool opt type as num #688
- Fix nested back gesture issue #686

## [2.3.1]

- Fix navigate to nested routes open last visited nested route #676
- Add pop parent route support in AutoBackButton

## [2.3.0]

- Fix crash when passing non-string values as query params #606
- Update analyzer version to 2.0.0
- Update build_runner,build and source_gen versions
- Merge #616 Export navigation failure
- Merge #550 Enable AutoTabsScaffold to support custom appbar [Breaking]
- Update README file

## [2.2.1]

- Fix crash when passing non-string values as query params #606
- Update analyzer version to 2.0.0
- Update build_runner,build and source_gen versions

## [2.2.0] Breaking changes!

- Remove helper methods pushToChild and replaceInChild from TabsRouter [Bad idea]. [Breaking]
- Add navigate and navigateNamed methods to TabsRouter
- Add navigateNamedTo method to context extension
- Change context.navigateTo and context.navigateNamedTo will be fired
  by nearest RouterScope weather it's a StackRouter or a TabsRouter
- Fix AutoRouteGuard is not fired when route is updating #517
- Fix DidInitTabRoute method is fired when a route is pushed in AutoRouteAware widgets #518

## [2.1.1] Breaking changes!

- AutoRouteGuard's canNavigate method is now called onNavigation. [Breaking]
- Add AutoRouteObserver to add support tab route observing.

## [2.1.0] Breaking changes!

- AutoRouteGuard no longer returns a future`<bool>` and passes in a resolver. [Breaking]
- Remove onInitialRoutes from AutoRouterDelegate. [Breaking]
- Rename RoutingControllerScope to RouterScope. [Breaking]
- Expose provided navigatorObservers in RouterScope
- Route name is now default page key with option to use path as key.
- Add onNavigate callback function to AutoRouterDelegate
- Add onNavigate all back to AutoRouter.declarative
- Add declarative option to AutoTabsRouter

## [2.0.1] Breaking changes!

- OnPopRoute includes a results object now. [Breaking]
- Remove usesTabsRouter property from AutoRoute as it's no longer needed.
- Required queryParams to either be nullable or have a default value

## [2.0.0] Breaking changes!

##### breaking changes

- Remove usesTabsRouter property from AutoRoute as it's no longer needed.
- onGenerateRoutes is now shortened to just routes and initial routes are no longer pass
- Legacy generator is completely dropped now.
- navigatorObservers is not a callback function that returns a list of observers

##### enhancements

- Bring back the good old await for pop results feature.
- The root AutoRouterDelegate can now be declarative.
- Push, replace and navigate will now bubble up if they can't be handled by the router they're
  called from.
- Enhance the navigate function to behave like navigating from the browser's bar.
- Add new methods to navigate by path pushNamed, replaceNamed and navigateNamed.
- Add AutoBackButton to handle nested routers popping with ease.
- Add some helper/shortcut methods to context extension, pushRoute, replaceRoute, navigateTo and
  popRoute.
- Add some helper methods to the RoutingController like popTop, topRoute and more.
- Pages will rebuild when an ancestor router updates if you depend on it.
- Add Auto RedirectRoute generation for Routes with none initial paths that's marked as initial.
- Add AutoRouteObserver to add tabs observing to the native observer.
- NavigatorObservers are now passed through a builder so nested navigators can inherit them.
- Add HeroControllerScope to nested AutoRouters
- Pomp up code_builder version to 4.0.0 and build_runner to 2.0.1
- Fix #458, #456 #421 and #453
- Minor fixes and enhancements

## [1.0.2]

- Pomp up versions of build, build_runner, dart_style and source_gen
- Using pathParam annotation is not more flexible and has less constrains
- Remove dart:io import to include (web) as a supported platform
- other fixes

## [1.0.1]

- Fix Stack overflow in RootStackRouter popUntilRoot() #401
- Fix path parameters are assigned an undefined var when alias is different than param name.

## [1.0.0]

- Migrate to null-safety
- Add option to pass restoration id
- Add option to specify the root navigator background color

## [1.0.0-beta.10]

- Fix generic parameters crash the generator
- Add support for array type query params

## [1.0.0-beta.9]

- Fix navigatorKey state is lost on hot reload
- Add stackRouterOfIndex getter function to AutoTabsRouter

## [1.0.0-beta.8]

- Add support for null-Safety to generated code.
- Fix pop issues
- Add popUntil, popUntilRoot and popUntilRouteWithName helper functions to StackRouter
- Minor fixes
  Edit [BC] pushAndPopUntil uses the native predicate now.

## [1.0.0-beta.7]

- Fix onRoutePop not called in declarative router #310
- Fix App reloads after pressing browser's back button #309
- Fix TabsRouter not displaying current route when pressing the browser's back button
- Add pop until method to StackRouter
- Prefix parent routes are now included if includePrefixMatches is true
- Add RouteMatcher tests
- Minor improvements

## [1.0.0-beta.6]

- Fix reload issue when pressing the browser's back button #309
- Fix onPopRoute is not called in declarative Router #310
- Include empty paths as prefix-matched paths when deep-linking.
- Remove unnecessary dependencies
- Some minor improvements and code refactor

## [1.0.0-beta.5]

- Refactor some code
- Update readme file

## [1.0.0-beta.4]

- Fix page can not be used for multiple routes
- Add duplicate route-names check in generator.

## [1.0.0-beta.3+1]

- Fix badge alignment in readme file

## [1.0.0-beta.3]

- Fix crash on empty path deep-linking
- Fix parent does not take priority when child can't pop
- Change includePrefixMatches default value to false in DefaultRouteParser
- Add some updates to Readme file

## [1.0.0-beta.2]

- Add lazyLoad option to AutoTabsRouter
- Replace AutoRouterConfig with an implementation of StackRouter
- Root delegate is now lazyLoaded

## [1.0.0-beta.1] Breaking Changes!

- Add TabsAutoRouter
- Refactor some code

## [1.0.0-beta] Breaking Changes!

- Rebuild auto_route to work with Navigator 2.0

---

## [0.6.9]

- Fix generator error running flutter version 1.22
- Fix bar-url not updated in flutter version 1.22

## [0.6.7]

- Fix blue screen issue when using guards on initial route #189
- Fix relative import issues
- Add option to not prefer relative imports
- Fix some linter warnings
- Fix issue #176

## [0.6.6]

- Fix hot reload issue #170
- Fix Hero animations not working with the new ExtendedNavigator # 169
- Add static builder to ExtendedNavigator to use with MaterialApp's builder

## [0.6.5]

- Downgrade path package to >= 1.6.4 to solve conflict with flutter_test
- Clean up auto_route index file

## [0.6.4]

- Add usage of const constructors when possible
- Fix material package is only imported if needed
- Fix spelling mistakes in changeLog

## [0.6.2] Breaking Change

- Fix deep linking issue for nested routes
- Change ExtendedNavigator to wrap the native navigator instead of extending it
- Change generated class applies to most of effective dart rules including preferring relative
  imports
- Change initial route placeholder color to white
- Add extension to BuildContext to easily access the navigator
- Remove NestedNavigator, ExtendedNavigator can be used directly as a nested navigator
- Rename some properties and deprecate their older names
- Remove ExtendedNavigator.ofRouter method
- Minor fixes and enhancements

## [0.6.1]

- Fix pop until name issue by implementing PopUntilPath and RouteData.withPath
- Fix opening deep links in new tabs pushes initial route only

## [0.6.0+1]

- Fix README file links

## [0.6.0] Breaking Change

- Change the way routes are declared from class fields to a static list
- Add support for path & query parameters
- Add support for path wildcards
- Add support for nested routes
- Add support for generic result types
- Add a get ExtendedNavigator by name feature
- Merge a fix for adaptive route web support issue
- Change generating arguments holder for single parameter routes is not optional anymore
- Minor fixes and enhancements

## [0.5.0]

- Add allRoutes getter to RouterBase
- minor fixes

## [0.4.6] Skip

## [0.4.5] Breaking Change

- Add AdaptiveAutoRouter and AdaptiveRoute for native platforms
- Change using leading slashes is now options
- Change wrappedRoute is now a function that takes in build context
- Fix calling nested route returns null after popping parent route
- Fix initial route ignore custom transitions
- Add ability to name routes class

## [0.4.4]

- Change generating arguments holder for single parameter routes is not optional
- Fix android soft back button always pops root navigator

## [0.4.3] Breaking Changes

- Add ability to pass initial route arguments to ExtendedNavigator
- Change single route parameters will have argument holder classes too as requested
- Fix ExtendedNavigator.ofRouter`<T>`() returns null in inspector mode

## [0.4.2]

- Fix Android soft back button always exists App

## [0.4.1] Breaking Changes

- Fix isInitialRoute not defined for RouteSettings in flutter 1.15.+

## [0.4.0] Breaking Changes

- Change using ExtendedNavigator instead of the native Navigator
- Fix initial route does not go through guards
- Change generated router class is no longer static
- Change routes are generated in their own class now "Routers"
- Add option to generate navigation helper methods extension
- Update README file

## [0.3.1]

- Fix Compilation Fails in flutter 1.15.+
- Fix third party imports src instead of library
- Fix guardedRoutes is generated even if it's empty
- Add support for custom unknown route screen

## [0.3.0] Breaking Changes!

- Add global route customization
- Use MaterialAutoRouter, CupertinoAutoRouter or CustomAutoRouter instead of AutoRouter
- Navigator key is now accessed by calling Router.navigator.key instead of Router.navigatorKey.
- Add Route guards
- Add optional returnType param in all AutoRoute types.
- Remove generate Navigator Key optional.
- Fix generate error when using dynamic vars in route widget constructors

## [0.2.2]

- Add option to generate a list with all route names
- change generating navigator key is now optional
- Fix prevent importing system library files
- Change generated route path name are now Kabab cased (url-friendly)
- Add ability to use custom path names in all route types
- Update README file

## [0.2.1]

- add Route Wrapper
- add initial flag as a property in all route types
- change prefix const route names with class name.
- add fullscreenDialog property to @CustomRoute()

## [0.2.0+1]

- format README file

## [0.2.0]

### Breaking Changes!

- change to using a single config file instead of annotating the actual widget class due to
  performance issues.
- add @MaterialRoute(), @CupertinoRoute() and @CustomRoute() annotations
- remove @AutoRoute() annotation and add @AutoRouter()
- handle required parameters.
- add navigating with a global navigator key [without context].
- support nested navigators.

## [0.1.1]

- code formatting.

## [0.1.0]

- initial release.
