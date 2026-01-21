import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

/// 대화 목록 화면
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final AcademyService _service = AcademyService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchConversations();
    // 10초마다 새로고침
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchConversations(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchConversations() async {
    try {
      final data = await _service.getConversations();
      if (mounted) {
        setState(() {
          _conversations = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching conversations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('메시지'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('대화 내역이 없습니다',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchConversations,
                  child: ListView.separated(
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final unread = conv['unread_count'] ?? 0;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Text(
                            (conv['other_user_name'] ?? '?')[0],
                            style: TextStyle(
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              conv['other_user_name'] ?? '알 수 없음',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (conv['other_user_info'] != null &&
                                conv['other_user_info']
                                    .toString()
                                    .isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                conv['other_user_info'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          conv['last_message'] ?? '대화 없음',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? Colors.black87 : Colors.grey,
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: unread > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                              )
                            : null,
                        onTap: () {
                          context.push(
                            '/chat/${conv['id']}',
                            extra: {
                              'otherUserName': conv['other_user_name'],
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
