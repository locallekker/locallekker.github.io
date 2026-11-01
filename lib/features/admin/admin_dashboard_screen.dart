import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_lekker/core/theme/app_colors.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import '../../services/chat_service.dart';
import 'admin_overview_screen.dart';
import 'admin_members_screen.dart';
import 'admin_partners_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_support_inbox_screen.dart';
import 'widgets/admin_promo_key_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;
  int _unreadChatCount = 0;
  Timer? _unreadChatTimer;
  RealtimeChannel? _chatMessagesChannel;

  final GlobalKey<AdminPartnersScreenState> _partnersKey =
      GlobalKey<AdminPartnersScreenState>();

  static const _titles = [
    'Admin Dashboard',
    'Manage Members',
    'Manage Partners',
    'Promotions',
    'Support',
    'Settings',
  ];

  late final List<Widget> _screens = <Widget>[
    const AdminOverviewScreen(),
    const AdminMembersScreen(),
    AdminPartnersScreen(key: _partnersKey),
    const AdminPromotionsScreen(),
    const AdminSupportInboxScreen(),
    const AdminSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadChatCount();
    _unreadChatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadUnreadChatCount(),
    );
    try {
      _chatMessagesChannel = ChatService.instance
          .subscribeToChatMessageChanges(onChange: _loadUnreadChatCount);
    } catch (_) {}
  }

  @override
  void dispose() {
    _unreadChatTimer?.cancel();
    try {
      _chatMessagesChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadUnreadChatCount() async {
    try {
      final count =
          await ChatService.instance.fetchAdminUnreadConversationCount();
      if (!mounted) return;
      if (count != _unreadChatCount) {
        setState(() => _unreadChatCount = count);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: Text(_titles[_currentIndex]),
        centerTitle: false,
        elevation: 0,
        actions: [
          if (_currentIndex == 2)
            IconButton(
              icon: const Icon(Icons.person_add, color: AppColors.primary),
              tooltip: 'Add Partner',
              onPressed: () {
                _partnersKey.currentState?.navigateToAddPartner();
              },
            ),
          IconButton(
            icon: const Icon(Icons.vpn_key, color: Colors.orange),
            tooltip: 'Generate Promo Key',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const AdminPromoKeyDialog(),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          // Refresh badge when leaving the support tab so reads are reflected.
          _loadUnreadChatCount();
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Members',
          ),
          const NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label: 'Partners',
          ),
          const NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Promos',
          ),
          NavigationDestination(
            icon: _supportIcon(selected: false),
            selectedIcon: _supportIcon(selected: true),
            label: 'Support',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _supportIcon({required bool selected}) {
    final icon = Icon(
      selected ? Icons.support_agent : Icons.support_agent_outlined,
    );
    if (_unreadChatCount <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            constraints: const BoxConstraints(
              minWidth: 18,
              minHeight: 18,
            ),
            child: Text(
              _unreadChatCount > 9 ? '9+' : '$_unreadChatCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
