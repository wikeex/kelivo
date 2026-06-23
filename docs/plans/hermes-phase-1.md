# Phase 1 — 聊天核心：详细实施计划

> Phase 1 of Kelivo → Hermes 迁移
> Branch: `feat/hermes-phase-0-foundation` (Phase 0 分支上继续)
> Status: **✅ complete (2026-06-23)**
> Date: 2026-06-23

---

## Phase 1 目标

实时聊天能完整跑通：创建/恢复会话、提交 prompt、收 streaming 事件、中断、approval/clarify/sudo/secret 弹窗。

---

## 交付物清单

| # | 文件 / 目录 | 说明 |
|---|---|---|
| 1 | `lib/shared/widgets/approval_sheet.dart` | approval.request 弹窗 |
| 2 | `lib/shared/widgets/clarify_sheet.dart` | clarify.request 弹窗 |
| 3 | `lib/shared/widgets/sudo_sheet.dart` | sudo.request 弹窗 |
| 4 | `lib/shared/widgets/secret_sheet.dart` | secret.request 弹窗 |
| 5 | `lib/hermes/hermes_session_provider.dart` | SessionProvider — 会话状态 + Hermes RPC 桥接 |
| 6 | `lib/features/home/controllers/stream_controller.dart` | 改造 — 接受 HermesStreamAdapter 的 chunk |
| 7 | `lib/features/home/controllers/chat_actions.dart` | 改造 — Hermes 路径的 send/regenerate/interrupt |
| 8 | `lib/features/home/services/message_generation_service.dart` | 改造 — Hermes mode 跳过本地注入 |
| 9 | `lib/l10n/app_en.arb` (+ 其他3个) | Phase 1 新增文本键 |
| 10 | `test/hermes/hermes_chat_adapter_test.dart` | 单元测试 |
| 11 | `test/hermes/hermes_rpc_test.dart` | 单元测试 |

---

## Step 1.1 — 审批/澄清弹窗 (0.5 天)

**1.1.1** `lib/shared/widgets/approval_sheet.dart`
- 监听 `HermesEventBus.approval.request` 事件
- Title: "Tool Approval Request"
- 显示工具名 + 参数预览
- 按钮: Approve / Deny + reason field
- 调用 `hermes_gateway.approvalRespond()`

**1.1.2** `lib/shared/widgets/clarify_sheet.dart`
- 监听 `clarify.request`
- 显示问题 + 输入框
- 调用 `clarifyRespond()`

**1.1.3** `lib/shared/widgets/sudo_sheet.dart`
- 监听 `sudo.request`
- 显示提权信息
- 调用 `sudoRespond()`

**1.1.4** `lib/shared/widgets/secret_sheet.dart`
- 监听 `secret.request`
- 显示 secret 输入框
- 调用 `secretRespond()`

All sheets use `IosCardPress`/`IosFormTextField` style.

**验收**: 在 connection_gate 之后的事件流中，收到对应事件即弹窗。

---

## Step 1.2 — SessionProvider (0.5 天)

**1.2.1** `lib/hermes/hermes_session_provider.dart`

```dart
class HermesSessionProvider extends ChangeNotifier {
  final HermesGateway gateway;
  final HermesEventBus eventBus;

  String? _activeSessionId;
  List<HermesSessionSummary> _sessions = [];
  List<ChatMessage> _messages = [];

  // 生命周期: create → resume → submit → stream → interrupt → close
  Future<String> createSession();
  Future<void> resumeSession(String sessionId);
  Future<void> submitPrompt(String text, {List<Map<String,dynamic>>? attachments});
  Future<void> interrupt();
  Future<List<ChatMessage>> loadHistory(String sessionId);
}
```

**1.2.2** Provider 注册到 `main.dart` 的 MultiProvider

---

## Step 1.3 — ChatActions Hermes 路径 (1 天)

**1.3.1** `lib/features/home/controllers/chat_actions.dart`

现有 `sendNewMessage()` 方法:
```
if (hermesProvider != null && hermesProvider.state == ready) {
  // Hermes 路径
  await _sendViaHermes(context, text, attachments);
} else {
  // 原 ChatApiService 路径 (fallback)
}
```

**1.3.2** Hermes send 流程:
1. `sessionProvider.createSession()` (若没有活跃 session)
2. `streamController.startStreaming(sessionId)` 监听 `HermesChatAdapter.chunkStream`
3. `gateway.promptSubmit(sessionId, text, attachments)`
4. 逐 chunk 回调 `_handleStreamChunk` (已有方法)
5. `MessageComplete` → 结束

---

## Step 1.4 — StreamController Hermes 适配 (0.5 天)

StreamController 的 `_handleStreamChunk` 方法是核心入口。HermesChatAdapter 已经发出 `ChatStreamChunk`，所以:

```dart
// 新增方法
void startHermesStream(HermesChatAdapter adapter) {
  adapter.chunkStream.listen((chunk) {
    _handleStreamChunk(chunk as ChatStreamChunk);
  });
}
```

这与原有的 `_startStreamSubscription(ChatApiService.apiStream(...))` 并行工作。

---

## Step 1.5 — MessageGenerationService Hermes 模式 (0.25 天)

在 Hermes 模式:
- 跳过 `prepareApiMessagesWithInjections()` (后端自己管理注入)
- 直接调用 `sessionProvider.submitPrompt(text)`
- `StreamController` 从 HermesAdapter 接收 chunk

新增 `isHermesMode` getter:
```dart
bool get isHermesMode => hermesProvider?.state == HermesConnectionState.ready;
```

---

## Step 1.6 — 国际化 (并行)

4 个 ARB 文件新增 `*_approval_*` / `*_clarify_*` / `*_sudo_*` / `*_secret_*` / `*_hermes_session_*` 键集

---

## Step 1.7 — 单元测试 (0.25 天)

- `test/hermes/hermes_chat_adapter_test.dart`: emit events → expect ChatStreamChunks
- `test/hermes/hermes_rpc_test.dart`: sessionCreate/sessionResume/promptSubmit 的 mock RPC

---

## 验收

- `flutter test` 全部通过
- `flutter analyze` 无 error
- 4 个 ARB 文件同步
- Hermes 模式下: 创建 session → submit prompt → 收 streaming → 按 interrupt → 正常中断
- Approval / Clarify / Sudo / Secret 弹窗正常显示和响应
