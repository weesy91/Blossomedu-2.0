import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/academy_service.dart';

/// 채팅방 화면
class ChatRoomScreen extends StatefulWidget {
  final int conversationId;
  final String otherUserName;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final AcademyService _service = AcademyService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _markAsRead();
    // 5초마다 새로고침 (채팅방 안에서는 더 자주)
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchMessages(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final data = await _service.getMessages(widget.conversationId);
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching messages: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead() async {
    try {
      await _service.markMessagesAsRead(widget.conversationId);
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _controller.clear();

    try {
      await _service.sendMessage(widget.conversationId, text);
      await _fetchMessages();
      // 스크롤 맨 아래로
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메시지 전송 실패: $e')),
      );
      // 실패 시 텍스트 복원
      _controller.text = text;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherUserName),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 메시지 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('메시지가 없습니다. 첫 메시지를 보내보세요!',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return _ChatBubble(
                            message: msg['content'] ?? '',
                            isMine: msg['is_mine'] == true,
                            time: msg['created_at'],
                            isRead: msg['is_read'] == true,
                            senderName: msg['sender_name'],
                          );
                        },
                      ),
          ),
          // 입력창
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: '메시지 입력...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, color: Colors.indigo),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

/// 채팅 버블 위젯
class _ChatBubble extends StatelessWidget {
  final String message;
  final bool isMine;
  final String? time;
  final bool isRead;
  final String? senderName;

  const _ChatBubble({
    required this.message,
    required this.isMine,
    this.time,
    this.isRead = false,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMine) ...[
            // 읽음 표시 (내 메시지일 때)
            if (isRead)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text('읽음',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ),
            // 시간
            if (time != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _formatTime(time!),
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
          // 메시지 버블
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? Colors.indigo : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isMine ? const Radius.circular(4) : null,
                bottomLeft: !isMine ? const Radius.circular(4) : null,
              ),
            ),
            child: Text(
              message,
              style: TextStyle(
                color: isMine ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
          if (!isMine) ...[
            // 시간
            if (time != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _formatTime(time!),
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = hour < 12 ? '오전' : '오후';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$ampm $hour12:$minute';
    } catch (_) {
      return '';
    }
  }
}
