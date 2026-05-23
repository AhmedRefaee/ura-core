part of '../chat_hub_screen.dart';

class ChatHubBody extends StatefulWidget {
  const ChatHubBody({super.key});

  @override
  State<ChatHubBody> createState() => _ChatHubBodyState();
}

class _ChatHubBodyState extends State<ChatHubBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChatDirectoryCubit>()..load(),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'المحادثات الأخيرة'),
              Tab(text: 'جميع المحادثات'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _RecentChatsTab(),
                _AllChatsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
