// Statistics data models for URA Core Manager Dashboard
// Read-only display models - no Equatable needed

/// Global statistics summary for a date range
class GlobalStatsSummary {
  final int totalOrders;
  final int deliveredOrders;
  final int activeOrders;
  final int outboundCount;
  final int inboundCount;
  final double? avgTotalHours;

  const GlobalStatsSummary({
    required this.totalOrders,
    required this.deliveredOrders,
    required this.activeOrders,
    required this.outboundCount,
    required this.inboundCount,
    this.avgTotalHours,
  });

  factory GlobalStatsSummary.fromJson(Map<String, dynamic> json) {
    return GlobalStatsSummary(
      totalOrders: json['total_orders'] as int? ?? 0,
      deliveredOrders: json['delivered_orders'] as int? ?? 0,
      activeOrders: json['active_orders'] as int? ?? 0,
      outboundCount: json['outbound_count'] as int? ?? 0,
      inboundCount: json['inbound_count'] as int? ?? 0,
      avgTotalHours: (json['avg_total_hours'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_orders': totalOrders,
      'delivered_orders': deliveredOrders,
      'active_orders': activeOrders,
      'outbound_count': outboundCount,
      'inbound_count': inboundCount,
      'avg_total_hours': avgTotalHours,
    };
  }
}

/// Performance statistics for a single representative
class RepPerformanceStat {
  final String repId;
  final String repName;
  final int totalOrders;
  final int deliveredOrders;
  final double? avgHoursToPickup;
  final double? avgHoursInTransit;
  final double? avgTotalHours;

  const RepPerformanceStat({
    required this.repId,
    required this.repName,
    required this.totalOrders,
    required this.deliveredOrders,
    this.avgHoursToPickup,
    this.avgHoursInTransit,
    this.avgTotalHours,
  });

  factory RepPerformanceStat.fromMap(Map<String, dynamic> map) {
    return RepPerformanceStat(
      repId: map['rep_id'] as String,
      repName: map['rep_name'] as String,
      totalOrders: map['total_orders'] as int? ?? 0,
      deliveredOrders: map['delivered_orders'] as int? ?? 0,
      avgHoursToPickup: (map['avg_hours_to_pickup'] as num?)?.toDouble(),
      avgHoursInTransit: (map['avg_hours_in_transit'] as num?)?.toDouble(),
      avgTotalHours: (map['avg_total_hours'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rep_id': repId,
      'rep_name': repName,
      'total_orders': totalOrders,
      'delivered_orders': deliveredOrders,
      'avg_hours_to_pickup': avgHoursToPickup,
      'avg_hours_in_transit': avgHoursInTransit,
      'avg_total_hours': avgTotalHours,
    };
  }
}

/// Monthly order statistics summary
class MonthlyOrderStat {
  final String month; // Format: "YYYY-MM"
  final int totalOrders;
  final int deliveredOrders;
  final int outboundOrders;
  final int inboundOrders;

  const MonthlyOrderStat({
    required this.month,
    required this.totalOrders,
    required this.deliveredOrders,
    required this.outboundOrders,
    required this.inboundOrders,
  });

  factory MonthlyOrderStat.fromMap(Map<String, dynamic> map) {
    return MonthlyOrderStat(
      month: map['month'] as String,
      totalOrders: map['total_orders'] as int? ?? 0,
      deliveredOrders: map['delivered_orders'] as int? ?? 0,
      outboundOrders: map['outbound_orders'] as int? ?? 0,
      inboundOrders: map['inbound_orders'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'month': month,
      'total_orders': totalOrders,
      'delivered_orders': deliveredOrders,
      'outbound_orders': outboundOrders,
      'inbound_orders': inboundOrders,
    };
  }
}

/// Entity frequency statistics - top entities by order count
class EntityFrequencyStat {
  final String entityId;
  final String entityName;
  final String entityType;
  final int orderCount;
  final int outboundCount;
  final int inboundCount;

  const EntityFrequencyStat({
    required this.entityId,
    required this.entityName,
    required this.entityType,
    required this.orderCount,
    required this.outboundCount,
    required this.inboundCount,
  });

  factory EntityFrequencyStat.fromMap(Map<String, dynamic> map) {
    return EntityFrequencyStat(
      entityId: map['entity_id'] as String,
      entityName: map['entity_name'] as String,
      entityType: map['entity_type'] as String,
      orderCount: map['order_count'] as int? ?? 0,
      outboundCount: map['outbound_count'] as int? ?? 0,
      inboundCount: map['inbound_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entity_id': entityId,
      'entity_name': entityName,
      'entity_type': entityType,
      'order_count': orderCount,
      'outbound_count': outboundCount,
      'inbound_count': inboundCount,
    };
  }
}

/// Aggregated statistics data container
class StatsData {
  final GlobalStatsSummary globalOverview;
  final List<RepPerformanceStat> repPerformance;
  final List<MonthlyOrderStat> monthlySummary;
  final List<EntityFrequencyStat> entityFrequency;

  const StatsData({
    required this.globalOverview,
    required this.repPerformance,
    required this.monthlySummary,
    required this.entityFrequency,
  });

  StatsData copyWith({
    GlobalStatsSummary? globalOverview,
    List<RepPerformanceStat>? repPerformance,
    List<MonthlyOrderStat>? monthlySummary,
    List<EntityFrequencyStat>? entityFrequency,
  }) {
    return StatsData(
      globalOverview: globalOverview ?? this.globalOverview,
      repPerformance: repPerformance ?? this.repPerformance,
      monthlySummary: monthlySummary ?? this.monthlySummary,
      entityFrequency: entityFrequency ?? this.entityFrequency,
    );
  }
}
