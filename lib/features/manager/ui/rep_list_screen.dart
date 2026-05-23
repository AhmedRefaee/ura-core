import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/order.dart';
import '../../../shared/order_status_theme.dart';
import '../../profile/ui/profile_screen.dart';
import '../logic/rep_list_cubit.dart';

/// Shows all reps with cards colored by their latest task status.
class RepListScreen extends StatelessWidget {
  const RepListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<RepListCubit>()..load(),
      child: const _RepListView(),
    );
  }
}

class _RepListView extends StatelessWidget {
  const _RepListView();

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('المناديب'),
      actions: [
        BlocBuilder<RepListCubit, RepListState>(
          builder: (context, state) => AppIconButton(
            icon: Icons.refresh,
            variant: AppIconButtonVariant.text,
            onPressed: () => context.read<RepListCubit>().load(),
            tooltip: 'تحديث',
          ),
        ),
      ],
      body: BlocBuilder<RepListCubit, RepListState>(
        builder: (context, state) {
          if (state is RepListLoading || state is RepListInitial) {
            return Builder(
              builder: (ctx) => const CollapsingInnerScrollBody(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: AppLoadingIndicator()),
                  ),
                ],
              ),
            );
          }
          if (state is RepListError) {
            return Builder(
              builder: (ctx) => CollapsingInnerScrollBody(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.message,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                          SizedBox(height: AppSpacing.verticalMedium),
                          AppButton(
                            text: 'إعادة المحاولة',
                            onPressed: () => context.read<RepListCubit>().load(),
                            variant: AppButtonVariant.elevated,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          if (state is RepListLoaded) {
            if (state.reps.isEmpty) {
              return Builder(
                builder: (ctx) => const CollapsingInnerScrollBody(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('لا يوجد مندوبون مسجلون')),
                    ),
                  ],
                ),
              );
            }
            return Builder(
              builder: (ctx) => RefreshIndicator(
                onRefresh: () => context.read<RepListCubit>().load(),
                child: CollapsingInnerScrollBody(
                  slivers: [
                    SliverPadding(
                      padding: AppSpacing.allMedium,
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _RepCard(rep: state.reps[i]),
                          childCount: state.reps.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return Builder(
            builder: (ctx) => const CollapsingInnerScrollBody(
              slivers: [SliverFillRemaining(child: SizedBox.shrink())],
            ),
          );
        },
      ),
    );
  }
}

// ── Rep card ──────────────────────────────────────────────────────────────────

class _RepCard extends StatelessWidget {
  final RepWithStatus rep;
  const _RepCard({required this.rep});

  @override
  Widget build(BuildContext context) {
    final status = rep.latestStatus;
    final cardColor = status?.color ?? AppColors.textTertiary;

    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      shape: RoundedRectangleBorder(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        side: BorderSide(color: cardColor.withAlpha(80), width: 1.5),
      ),
      child: InkWell(
        borderRadius: AppConstants.borderRadiusMediumRadius,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(profile: rep.profile, isSelf: false),
          ),
        ),
        child: Padding(
          padding: AppSpacing.allLarge,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cardColor.withAlpha(30),
                child: Icon(Icons.delivery_dining, color: cardColor, size: 24),
              ),
              SizedBox(width: AppSpacing.horizontalMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rep.profile.fullName,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (rep.profile.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        rep.profile.phone!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null)
                _StatusBadge(status: status)
              else
                Text(
                  'لا توجد مهام',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              SizedBox(width: AppSpacing.horizontalXSmall),
              Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  String get _label => switch (status) {
        OrderStatus.assigned || OrderStatus.pickedUp => 'قبل التنقل',
        OrderStatus.onTheMove => 'في الطريق',
        OrderStatus.delivered || OrderStatus.deliveredToStorage => 'مكتمل',
      };

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: AppSpacing.symmetric(
        horizontal: AppSpacing.horizontalSmall,
        vertical: AppSpacing.verticalXSmall,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusXLarge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
