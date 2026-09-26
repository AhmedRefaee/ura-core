import 'package:flutter/widgets.dart';

/// An [IndexedStack] that builds each child the first time it is shown, then
/// keeps it alive.
///
/// Home screens used to render `tabs[index]`, so leaving a tab destroyed it
/// and coming back re-created it: spinner, full refetch, a new realtime
/// channel, lost scroll and search. A plain IndexedStack fixes that but
/// builds (and fetches) every tab at startup, including ones never opened.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const LazyIndexedStack({super.key, required this.index, required this.children});

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}
