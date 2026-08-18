import 'package:flutter/material.dart';
import '../models/order.dart';

class DirectionSelector extends StatelessWidget {
  final OrderDirection selected;
  final ValueChanged<OrderDirection> onChanged;
  const DirectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<OrderDirection>(
      segments: [
        for (final direction in OrderDirection.values)
          ButtonSegment(value: direction, label: Text(direction.label)),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
