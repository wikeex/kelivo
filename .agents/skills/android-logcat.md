---
name: android-logcat
description: Android 真机日志抓取技巧——Flutter 调试模式下 print() 输出不在 logcat 中，必须用 `flutter logs` 实时连接
---

# Android 日志抓取（Flutter 调试模式）

## 核心原则

Flutter 的 `print()` / `debugPrint()` 输出在调试模式下**不会出现在 `adb logcat` 的 flutter tag 中**。必须使用 `flutter logs -d <device_id>` 实时连接 Dart VM 服务才能捕获。

## 设备标识

获取 Android 设备 ID：

```bash
flutter devices | grep android
```

示例输出：`23116PN5BC (mobile) • 42b6f694 • android-arm64 • Android 16 (API 36)`

## 常用命令

### 1. 实时捕获 Flutter 日志（推荐）

```bash
# 启动监听（后台写入文件，防止终端阻塞）
flutter logs -d <device_id> > /tmp/flutter_logs.txt &
# 用户操作后，检查日志
cat /tmp/flutter_logs.txt | grep "你的标记"
# 停止监听
kill %1
```

注意：`flutter logs` 启动后需要几秒建立连接，所以用户操作前应确保已启动。

### 2. 查看最近日志

```bash
# 按进程 ID 过滤（推荐，减少噪声）
adb logcat -t <行数> pid=<pid>
# 仅 Flutter 输出
adb logcat -t <行数> flutter:I '*:S'
```

### 3. 实时监听（后台任务）

```bash
adb logcat -c  # 清空缓冲区
adb logcat -v brief 2>&1 | grep '你的关键词' &
sleep <时间>
kill %1
```

### 4. 进程管理

```bash
# 获取 kelivo 进程 PID
adb shell 'ps -e | grep psyche' | awk '{print $2}'
# 强制停止 app
adb shell am force-stop com.psyche.kelivo
# 启动 app
adb shell am start -n com.psyche.kelivo/.MainActivity
```

## 建议的调试流程

1. 在 Dart 代码中用 `print('[TAG] 信息')` 标记（`debugPrint` 在 debug 模式也有效，但 `print` 更可靠）
2. 在用户操作前启动 `flutter logs -d <device_id> > /tmp/flutter_logs.txt &`
3. 让用户操作
4. 用 `grep '你的标记' /tmp/flutter_logs.txt` 过滤结果
5. 关键：不要用 `adb logcat -s flutter` 过滤，会漏掉 print 输出

## 抓取 WebSocket 二进制数据

要确认实际发送的网络数据（JSON-RPC payload），在 `sendRpc` 方法中添加：

```dart
print('[WS_RAW] ${jsonEncode(payload)}');
```

这比 `print(payload['params']['prompt'])` 更可靠，可以看到序列化后的完整 JSON。
