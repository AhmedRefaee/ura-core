import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/theme_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('الإعدادات'),
        ),
        body: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, state) {
            final themeCubit = context.read<ThemeCubit>();
            final isDarkMode = state.isDarkMode;

            return SingleChildScrollView(
              child: Column(
                children: [
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: ListTile(
                      leading: Icon(
                        isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        color: isDarkMode ? Colors.amber : Colors.orange,
                      ),
                      title: const Text('الوضع الليلي'),
                      subtitle: Text(
                        isDarkMode ? 'مفعّل' : 'معطّل',
                      ),
                      trailing: Switch(
                        value: isDarkMode,
                        onChanged: (_) {
                          themeCubit.toggleDarkMode();
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'سيتم تطبيق تغيير الوضع الليلي على التطبيق كاملاً',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).disabledColor,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
  }
}
