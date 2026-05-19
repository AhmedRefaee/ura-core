import 'package:flutter/material.dart';

/// Wraps content in a NestedScrollView with a floating SliverAppBar.
///
/// AppBar + optional TabBar (via [sliverBottom]) collapse together as the
/// user scrolls down, and return as soon as they scroll up — Twitter/X style.
///
/// Usage for tabs (AppBar + TabBar collapse together):
/// ```dart
/// CollapsingHeaderWrapper(
///   title: const Text('My Screen'),
///   actions: [IconButton(...)],
///   sliverBottom: TabBar(controller: _tabController, tabs: [...]),
///   body: TabBarView(
///     controller: _tabController,
///     children: [
///       Builder(builder: (ctx) => RefreshIndicator(
///         onRefresh: ...,
///         child: CollapsingInnerScrollBody(slivers: [SliverList(...)]),
///       )),
///     ],
///   ),
/// )
/// ```
///
/// Usage without TabBar (AppBar only):
/// ```dart
/// CollapsingHeaderWrapper(
///   title: const Text('Chat'),
///   body: ChatListView(),
/// )
/// ```
class CollapsingHeaderWrapper extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;

  /// Optional TabBar or compound header (search + TabBar) to place in
  /// the SliverAppBar's bottom slot. Must implement [PreferredSizeWidget].
  final PreferredSizeWidget? sliverBottom;

  /// The scrollable body. For tabbed screens, pass a [TabBarView] whose
  /// children each use [CollapsingInnerScrollBody]. For simple screens,
  /// pass a plain [ListView] or a widget that contains one.
  final Widget body;

  const CollapsingHeaderWrapper({
    super.key,
    required this.title,
    this.actions = const [],
    this.sliverBottom,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: true,
        bottom: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                title: title,
                actions: actions,
                floating: true,
                snap: false,
                pinned: false,
                forceElevated: innerBoxIsScrolled,
                bottom: sliverBottom,
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                centerTitle: true,
                titleTextStyle: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
                actionsIconTheme:
                    IconThemeData(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
          body: body,
        ),
      ),
    );
  }
}

/// Inner scroll body for use inside [CollapsingHeaderWrapper]'s [TabBarView].
///
/// Injects the outer header's overlap so content begins below the floating
/// AppBar rather than being clipped underneath it.
///
/// Must be called inside a [Builder] to get a context that is a descendant
/// of [NestedScrollView]:
/// ```dart
/// Builder(builder: (ctx) => RefreshIndicator(
///   onRefresh: ...,
///   child: CollapsingInnerScrollBody(slivers: [
///     SliverList(delegate: SliverChildBuilderDelegate(...)),
///   ]),
/// ))
/// ```
///
/// For empty states use [SliverFillRemaining] with `hasScrollBody: false`
/// so the list remains overscrollable and [RefreshIndicator] still fires:
/// ```dart
/// CollapsingInnerScrollBody(slivers: [
///   SliverFillRemaining(
///     hasScrollBody: false,
///     child: Center(child: Text('No items')),
///   ),
/// ])
/// ```
class CollapsingInnerScrollBody extends StatelessWidget {
  final List<Widget> slivers;

  /// Provide an explicit controller when the list needs to detect scroll
  /// position changes (e.g. infinite-scroll load-more logic).
  final ScrollController? controller;

  const CollapsingInnerScrollBody({
    super.key,
    required this.slivers,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        ...slivers,
      ],
    );
  }
}
