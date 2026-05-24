import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../profile/ui/profile_screen.dart';
import '../logic/stats_cubit.dart';
import '../data/stats_models.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _selectedPeriod = '30d';
  String _entityFilter = 'all'; // 'all' | 'outbound' | 'inbound'

  static const _periodLabels = {
    '7d': '7 أيام',
    '30d': '30 يوم',
    '3m': '3 أشهر',
    '6m': '6 أشهر',
    '1y': 'سنة كاملة',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatsCubit>().load(_selectedPeriod);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocProvider.value(
      value: sl<NotificationsBadgeCubit>(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          top: true,
          bottom: false,
          child: BlocBuilder<StatsCubit, StatsState>(
            builder: (context, state) {
              if (state is StatsLoading) {
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildSliverAppBar(context),
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }
              if (state is StatsError) {
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _buildSliverAppBar(context),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(state.message,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => context
                                  .read<StatsCubit>()
                                  .load(_selectedPeriod),
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              if (state is StatsLoaded) {
                return RefreshIndicator(
                  onRefresh: () =>
                      context.read<StatsCubit>().load(_selectedPeriod),
                  child: _buildContent(context, state.data),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      title: const Text('الإحصائيات'),
      floating: true,
      snap: false,
      pinned: false,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      centerTitle: true,
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.go('/notifications'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, StatsData data) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _buildSliverAppBar(context),
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(child: _buildKpiCards(context, data.globalOverview)),
        SliverToBoxAdapter(child: _buildMonthlyTrendSection(context, data.monthlySummary)),
        SliverToBoxAdapter(child: _buildRepPerformanceSection(context, data.repPerformance)),
        SliverToBoxAdapter(child: _buildTopEntitiesSection(context, data.entityFrequency)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Period picker header ────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            'الفترة الزمنية',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: _selectedPeriod,
            onSelected: (value) {
              setState(() => _selectedPeriod = value);
              context.read<StatsCubit>().load(value);
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (_) => _periodLabels.entries
                .map((e) => PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          if (e.key == _selectedPeriod)
                            Icon(Icons.check, size: 18, color: colorScheme.primary)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(e.value),
                        ],
                      ),
                    ))
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    _periodLabels[_selectedPeriod]!,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more,
                      size: 18, color: colorScheme.onPrimaryContainer),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI cards ───────────────────────────────────────────────────────────────

  Widget _buildKpiCards(BuildContext context, GlobalStatsSummary overview) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _KpiCard(
              title: 'إجمالي الطلبات',
              value: overview.totalOrders.toString(),
              icon: Icons.inventory_2_outlined,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              title: 'تم التسليم',
              value: overview.deliveredOrders.toString(),
              icon: Icons.check_circle_outline,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              title: 'نشطة',
              value: overview.activeOrders.toString(),
              icon: Icons.pending_outlined,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiCard(
              title: 'متوسط الوقت',
              value: overview.avgTotalHours != null
                  ? '${overview.avgTotalHours!.toStringAsFixed(1)} س'
                  : '—',
              icon: Icons.access_time,
              color: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  // ── Monthly trend ───────────────────────────────────────────────────────────

  Widget _buildMonthlyTrendSection(
      BuildContext context, List<MonthlyOrderStat> monthlySummary) {
    if (monthlySummary.isEmpty) return const SizedBox.shrink();

    final maxY = monthlySummary
            .map((e) => e.totalOrders.toDouble())
            .reduce((a, b) => a > b ? a : b) *
        1.2;

    return _SectionCard(
      title: 'الاتجاه الشهري',
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Colors.grey[800]!,
                tooltipPadding: const EdgeInsets.all(8),
                tooltipMargin: 8,
                getTooltipItem: (group, _, rod, _) {
                  final stat = monthlySummary[group.x];
                  return BarTooltipItem(
                    '${stat.month}\n',
                    const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: '${stat.totalOrders} طلب',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i >= monthlySummary.length) {
                      return const SizedBox.shrink();
                    }
                    final parts = monthlySummary[i].month.split('-');
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${parts[1]}/${parts[0].substring(2)}',
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  getTitlesWidget: (value, _) => value == value.toInt()
                      ? Text(value.toInt().toString(),
                          style: const TextStyle(fontSize: 10))
                      : const SizedBox.shrink(),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            barGroups: monthlySummary.asMap().entries.map((entry) {
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.totalOrders.toDouble(),
                    color: Colors.blue,
                    width: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Rep performance ─────────────────────────────────────────────────────────

  Widget _buildRepPerformanceSection(
      BuildContext context, List<RepPerformanceStat> repPerformance) {
    if (repPerformance.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      title: 'أداء المناديب',
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: repPerformance.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _RepPerformanceCard(rep: repPerformance[index]),
      ),
    );
  }

  // ── Top entities ────────────────────────────────────────────────────────────

  Widget _buildTopEntitiesSection(
      BuildContext context, List<EntityFrequencyStat> entityFrequency) {
    if (entityFrequency.isEmpty) return const SizedBox.shrink();

    // Filter & sort by direction
    final filtered = entityFrequency.where((e) {
      if (_entityFilter == 'outbound') return e.outboundCount > 0;
      if (_entityFilter == 'inbound') return e.inboundCount > 0;
      return true;
    }).toList();

    if (_entityFilter == 'outbound') {
      filtered.sort((a, b) => b.outboundCount.compareTo(a.outboundCount));
    } else if (_entityFilter == 'inbound') {
      filtered.sort((a, b) => b.inboundCount.compareTo(a.inboundCount));
    }

    final maxCount = filtered.isEmpty
        ? 1
        : (_entityFilter == 'outbound'
            ? filtered.first.outboundCount
            : _entityFilter == 'inbound'
                ? filtered.first.inboundCount
                : filtered.first.orderCount);

    return _SectionCard(
      title: 'أكثر الجهات تداولاً',
      headerTrailing: _EntityFilterChips(
        selected: _entityFilter,
        onChanged: (v) => setState(() => _entityFilter = v),
      ),
      child: filtered.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('لا توجد بيانات للفلتر المحدد')),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _EntityFrequencyBar(
                entity: filtered[index],
                maxCount: maxCount,
                filter: _entityFilter,
              ),
            ),
    );
  }
}

// ── Section card container ──────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerTrailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              if (headerTrailing != null) ...[
                const Spacer(),
                headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── KPI card ────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(title,
              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ── Rep performance card ────────────────────────────────────────────────────

class _RepPerformanceCard extends StatelessWidget {
  final RepPerformanceStat rep;

  const _RepPerformanceCard({required this.rep});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(
              profile: Profile(
                id: rep.repId,
                fullName: rep.repName,
                role: UserRole.rep,
                isApproved: true,
              ),
              isSelf: false,
            ),
          ),
        ),
        child: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          child: Text(
            rep.repName.isNotEmpty ? rep.repName[0] : '؟',
            style: const TextStyle(
                color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      title: Text(rep.repName,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${rep.totalOrders} طلب'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _PerformanceRow(
                label: 'تم التسليم',
                value: '${rep.deliveredOrders} طلب',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              const SizedBox(height: 8),
              _PerformanceRow(
                label: 'متوسط وقت الاستلام من المخزن',
                value: rep.avgHoursToPickup != null
                    ? '${rep.avgHoursToPickup!.toStringAsFixed(1)} ساعة'
                    : '—',
                icon: Icons.access_time,
                color: Colors.blue,
              ),
              const SizedBox(height: 8),
              _PerformanceRow(
                label: 'متوسط وقت التوصيل للجهة',
                value: rep.avgHoursInTransit != null
                    ? '${rep.avgHoursInTransit!.toStringAsFixed(1)} ساعة'
                    : '—',
                icon: Icons.local_shipping,
                color: Colors.orange,
              ),
              const SizedBox(height: 8),
              _PerformanceRow(
                label: 'متوسط الوقت الإجمالي',
                value: rep.avgTotalHours != null
                    ? '${rep.avgTotalHours!.toStringAsFixed(1)} ساعة'
                    : '—',
                icon: Icons.timeline,
                color: Colors.purple,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _PerformanceRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ── Entity filter chips ─────────────────────────────────────────────────────

class _EntityFilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _EntityFilterChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(label: 'الكل', value: 'all', selected: selected, onChanged: onChanged),
        const SizedBox(width: 6),
        _FilterChip(label: 'صادر', value: 'outbound', selected: selected, onChanged: onChanged, color: Colors.blue),
        const SizedBox(width: 6),
        _FilterChip(label: 'وارد', value: 'inbound', selected: selected, onChanged: onChanged, color: Colors.green),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: isSelected ? chipColor : Colors.grey[300]!,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? chipColor : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── Entity frequency bar ────────────────────────────────────────────────────

class _EntityFrequencyBar extends StatelessWidget {
  final EntityFrequencyStat entity;
  final int maxCount;
  final String filter;

  const _EntityFrequencyBar({
    required this.entity,
    required this.maxCount,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = filter == 'outbound'
        ? entity.outboundCount
        : filter == 'inbound'
            ? entity.inboundCount
            : entity.orderCount;
    final percentage = maxCount > 0 ? displayCount / maxCount : 0.0;
    final barColor =
        entity.outboundCount >= entity.inboundCount ? Colors.blue : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entity.entityName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(entity.entityType,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Text('$displayCount طلب',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _DirectionBadge(
                label: 'صادر', count: entity.outboundCount, color: Colors.blue),
            const SizedBox(width: 8),
            _DirectionBadge(
                label: 'وارد', count: entity.inboundCount, color: Colors.green),
          ],
        ),
      ],
    );
  }
}

class _DirectionBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DirectionBadge(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $count',
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
