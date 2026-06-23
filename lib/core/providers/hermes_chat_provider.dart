import '../../core/models/chat_message.dart';
import '../../core/services/chat/chat_service.dart';
import '../../hermes/hermes_rpc.dart';
import '../../hermes/hermes_stream_adapter.dart';
import 'hermes_gateway_provider.dart';

export '../../hermes/hermes_stream_adapter.dart'
    show HermesStreamChunk, HermesToolCall, HermesToolResult;

/// Count user/assistant Hermes messages that would be imported.
int countImportableHermesMessages(List<Map<String, dynamic>> raw) {
  var count = 0;
  for (final item in raw) {
    final msg = HermesChatMessage.fromHermes(item);
    if (msg.role == 'tool' || msg.role == 'system') continue;
    final content = msg.content?.trim() ?? '';
    final reasoning = msg.reasoning?.trim() ?? '';
    if (content.isEmpty && reasoning.isEmpty) continue;
    count++;
  }
  return count;
}

/// Chat-specific extensions for [HermesGatewayProvider].
///
/// Manages Hermes session lifecycle, streaming, and interactive requests
/// (approval, clarify, sudo, secret) for the chat UI.
extension HermesChatProviderX on HermesGatewayProvider {
  // ── Hermes Chat Stream ─────────────────────────────────────────────────

  /// Subscribe to Hermes events and get a stream of chat chunks.
  HermesStreamAdapter subscribeToStream(String sessionId) {
    final adapter = HermesStreamAdapter(eventBus: eventBus);
    adapter.start(sessionId);
    streamAdapter = adapter;
    return adapter;
  }

  /// Stop the current stream subscription.
  void unsubscribeFromStream() {
    streamAdapter = null;
  }

  // ── Hermes Interactive Responses ────────────────────────────────────────

  /// Respond to an approval request.
  Future<void> respondApproval(
    String sessionId,
    bool approved, {
    String? reason,
  }) async {
    await gateway.approvalRespond(sessionId, approved, reason: reason);
    takePendingRequest(sessionId); // Remove from pending list
  }

  /// Respond to a clarify request.
  Future<void> respondClarify(
    String sessionId,
    Map<String, dynamic> response,
  ) async {
    await gateway.clarifyRespond(sessionId, response);
  }

  /// Respond to a sudo request.
  Future<void> respondSudo(
    String sessionId,
    bool approved, {
    String? reason,
  }) async {
    await gateway.sudoRespond(sessionId, approved, reason: reason);
  }

  /// Provide a secret (API key, token, etc.).
  Future<void> respondSecret(String sessionId, String secret) async {
    await gateway.secretRespond(sessionId, secret);
  }

  // ── Hermes Session History ───────────────────────────────────────────────

  /// Load message history from Hermes backend for a session.
  Future<List<HermesChatMessage>> loadSessionHistory(
    String sessionId, {
    int? limit,
    int? before,
  }) async {
    final raw = await gateway.sessionHistory(
      sessionId,
      limit: limit,
      before: before,
    );
    return raw.map((m) => HermesChatMessage.fromHermes(m)).toList();
  }

  /// Import Hermes session history into a local Kelivo conversation.
  Future<List<ChatMessage>> importSessionHistoryToConversation({
    required String sessionId,
    required String conversationId,
    required ChatService chatService,
    List<Map<String, dynamic>>? prefetchedMessages,
    String? storedSessionId,
  }) async {
    final raw =
        prefetchedMessages ??
        await gateway.sessionHistory(sessionId);
    return _importRawMessagesToConversation(
      raw: raw,
      sessionId: sessionId,
      conversationId: conversationId,
      chatService: chatService,
      storedSessionId: storedSessionId,
    );
  }

  /// Resume a stored Hermes session and import its history locally.
  Future<List<ChatMessage>> resumeAndImportSessionToConversation({
    required String storedSessionId,
    required String conversationId,
    required ChatService chatService,
  }) async {
    final resume = await gateway.sessionResumeDetailed(storedSessionId);
    setActiveSessionId(resume.liveSessionId);
    pinSession(resume.storedSessionId);

    var raw = resume.messages;
    if (raw.isEmpty && resume.liveSessionId.isNotEmpty) {
      raw = await gateway.sessionHistory(resume.liveSessionId);
    }

    return _importRawMessagesToConversation(
      raw: raw,
      sessionId: resume.liveSessionId,
      conversationId: conversationId,
      chatService: chatService,
      storedSessionId: resume.storedSessionId,
    );
  }

  Future<List<ChatMessage>> _importRawMessagesToConversation({
    required List<Map<String, dynamic>> raw,
    required String sessionId,
    required String conversationId,
    required ChatService chatService,
    String? storedSessionId,
  }) async {
    final history = raw.map((m) => HermesChatMessage.fromHermes(m)).toList();
    final existing = chatService.getMessages(conversationId);
    final existingKeys = <String>{
      for (final m in existing) '${m.role}:${m.content.trim()}',
    };
    final imported = <ChatMessage>[];
    for (final msg in history) {
      if (msg.role == 'tool' || msg.role == 'system') continue;
      final content = msg.content?.trim() ?? '';
      final reasoning = msg.reasoning?.trim() ?? '';
      if (content.isEmpty && reasoning.isEmpty) continue;
      final role = msg.role == 'assistant' ? 'assistant' : 'user';
      final key = '$role:$content';
      if (existingKeys.contains(key)) continue;
      existingKeys.add(key);
      final chatMsg = await chatService.addMessage(
        conversationId: conversationId,
        role: role,
        content: content,
        reasoningText: reasoning.isEmpty ? null : reasoning,
      );
      imported.add(chatMsg);
    }
    chatService.dropMessagesCache(conversationId);
    if (storedSessionId != null && storedSessionId.isNotEmpty) {
      linkConversationToHermesSession(conversationId, storedSessionId);
    }
    return imported;
  }

  /// Get session usage stats.
  Future<HermesSessionUsage?> getSessionUsage(String sessionId) async {
    final raw = await gateway.sessionUsage(sessionId);
    if (raw.isEmpty) return null;
    return HermesSessionUsage.fromJson(raw);
  }

  // ── File Attachments ────────────────────────────────────────────────────

  /// Attach a file to the current session.
  Future<String> attachFile(String path) async {
    final sessionId = activeSessionId;
    if (sessionId == null) throw StateError('No active session');
    return gateway.fileAttach(sessionId, path);
  }

  /// Attach an image URL to the current session.
  Future<String> attachImage(String url, {String? mimeType}) async {
    final sessionId = activeSessionId;
    if (sessionId == null) throw StateError('No active session');
    return gateway.imageAttach(sessionId, url, mimeType: mimeType);
  }

  /// Attach an image from base64 bytes.
  Future<String> attachImageBytes(
    String base64Bytes, {
    String? mimeType,
  }) async {
    final sessionId = activeSessionId;
    if (sessionId == null) throw StateError('No active session');
    return gateway.imageAttachBytes(sessionId, base64Bytes, mimeType: mimeType);
  }

  /// Paste clipboard content.
  Future<void> pasteClipboard(String content) async {
    final sessionId = activeSessionId;
    if (sessionId == null) return;
    await gateway.clipboardPaste(sessionId, content);
  }

  /// Report dropped files.
  Future<void> reportDroppedFiles(List<String> paths) async {
    final sessionId = activeSessionId;
    if (sessionId == null) return;
    await gateway.inputDetectDrop(sessionId, paths);
  }
}

// ── Hermes Session Data Models ──────────────────────────────────────────────

/// A chat message loaded from Hermes backend.
class HermesChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String? content;
  final String? reasoning;
  final DateTime? createdAt;
  final List<HermesToolEvent>? toolEvents;

  const HermesChatMessage({
    required this.id,
    required this.role,
    this.content,
    this.reasoning,
    this.createdAt,
    this.toolEvents,
  });

  factory HermesChatMessage.fromHermes(Map<String, dynamic> json) {
    return HermesChatMessage(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? json['text']?.toString(),
      reasoning:
          json['reasoning']?.toString() ??
          json['reasoning_content']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      toolEvents: (json['tool_events'] as List<dynamic>?)
          ?.map((e) => HermesToolEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A tool event in Hermes message history.
class HermesToolEvent {
  final String? id;
  final String name;
  final Map<String, dynamic>? arguments;
  final String? content;
  final bool isComplete;

  const HermesToolEvent({
    this.id,
    required this.name,
    this.arguments,
    this.content,
    this.isComplete = false,
  });

  factory HermesToolEvent.fromJson(Map<String, dynamic> json) {
    return HermesToolEvent(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      arguments: (json['arguments'] as Map?)?.cast<String, dynamic>(),
      content: json['content']?.toString(),
      isComplete: json['content'] != null,
    );
  }
}

/// Session usage data from Hermes.
class HermesSessionUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? cachedTokens;
  final String? modelId;

  const HermesSessionUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cachedTokens,
    this.modelId,
  });

  factory HermesSessionUsage.fromJson(Map<String, dynamic> json) {
    return HermesSessionUsage(
      promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      cachedTokens: (json['cached_tokens'] as num?)?.toInt(),
      modelId: json['model']?.toString(),
    );
  }
}
