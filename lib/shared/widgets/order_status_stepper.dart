import 'package:flutter/material.dart';
import '../models/order.dart';
import '../order_status_theme.dart';

class OrderStatusStepper extends StatelessWidget {
  final Order order;

  const OrderStatusStepper({super.key, required this.order});

  List<({OrderStatus status, String label})> get _steps {
    switch (order.direction) {
      case OrderDirection.inboundExternal:
        return [
          (status: OrderStatus.assigned, label: 'تم الإنشاء'),
          (
            status: OrderStatus.deliveredToStorage,
            label: 'تم الاستلام في المخزن',
          ),
        ];
      case OrderDirection.inboundRep:
        return [
          (status: OrderStatus.assigned, label: 'تم الإنشاء'),
          (status: OrderStatus.pickedUp, label: 'تم الشراء'),
          (status: OrderStatus.onTheMove, label: 'في الطريق'),
          (status: OrderStatus.deliveredToStorage, label: 'استلام المخزن'),
        ];
      case OrderDirection.outbound when order.involvesStorage:
        return [
          (status: OrderStatus.assigned, label: 'معين'),
          (status: OrderStatus.pickedUp, label: 'أُرسل من المخزن'),
          (status: OrderStatus.onTheMove, label: 'في الطريق'),
          (status: OrderStatus.delivered, label: 'تم التسليم'),
        ];
      case OrderDirection.outbound:
        return [
          (status: OrderStatus.assigned, label: 'معين'),
          (status: OrderStatus.pickedUp, label: 'تم الاستلام'),
          (status: OrderStatus.onTheMove, label: 'في الطريق'),
          (status: OrderStatus.delivered, label: 'تم التسليم'),
        ];
    }
  }

  int _currentIndex(List<({OrderStatus status, String label})> steps) {
    final index = steps.indexWhere((step) => step.status == order.status);
    if (index >= 0) return index;
    if (order.direction == OrderDirection.inboundExternal &&
        order.status == OrderStatus.delivered) {
      return steps.length - 1;
    }
    if (order.direction == OrderDirection.inboundRep &&
        order.status == OrderStatus.delivered) {
      return steps.length - 1;
    }
    return order.status == OrderStatus.deliveredToStorage
        ? steps.length - 1
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final currentIndex = _currentIndex(steps);
    final compact = order.direction == OrderDirection.inboundExternal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تقدم الطلب',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = compact && constraints.maxWidth > 280
                    ? 280.0
                    : constraints.maxWidth;
                return Align(
                  alignment: AlignmentDirectional.center,
                  child: SizedBox(
                    width: width,
                    height: 76,
                    child: Stack(
                      alignment: AlignmentDirectional.topCenter,
                      children: [
                        PositionedDirectional(
                          top: 14,
                          start: 0,
                          end: 0,
                          child: _StepperConnectors(
                            steps: steps,
                            currentIndex: currentIndex,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(
                            steps.length,
                            (index) => Expanded(
                              child: _StepperStep(
                                status: steps[index].status,
                                label: steps[index].label,
                                reached: index <= currentIndex,
                                current: index == currentIndex,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperConnectors extends StatelessWidget {
  final List<({OrderStatus status, String label})> steps;
  final int currentIndex;

  const _StepperConnectors({required this.steps, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    if (steps.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stepSlotWidth = constraints.maxWidth / steps.length;
        return Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: stepSlotWidth / 2,
          ),
          child: Row(
            children: List.generate(steps.length - 1, (index) {
              final from = steps[index].status;
              final to = steps[index + 1].status;
              final reached = index < currentIndex;
              final active = index == currentIndex;
              final colors = reached
                  ? [from.color, to.color]
                  : active
                  ? [
                      from.color.withValues(alpha: 0.72),
                      to.color.withValues(alpha: 0.5),
                    ]
                  : [
                      from.color.withValues(alpha: 0.24),
                      to.color.withValues(alpha: 0.24),
                    ];

              return Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: colors,
                    ),
                    boxShadow: reached || active
                        ? [
                            BoxShadow(
                              color: colors.last.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _StepperStep extends StatelessWidget {
  final OrderStatus status;
  final String label;
  final bool reached;
  final bool current;

  const _StepperStep({
    required this.status,
    required this.label,
    required this.reached,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: current ? 34 : 30,
          height: current ? 34 : 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reached ? color : Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: reached ? color : Colors.grey.shade300,
              width: current ? 3 : 2,
            ),
            boxShadow: current
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.26),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            reached ? Icons.check_rounded : status.icon,
            size: 16,
            color: reached ? Colors.white : Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: reached ? color : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}
