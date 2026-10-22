import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../services/face_login_service.dart';
import '../services/api_client.dart';
import 'face_capture_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSignedIn});
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_register) {
        final response = await AttendanceApi.post('auth/register', {
          'userName': _user.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'fullName': _name.text.trim(),
        });
        if (!mounted) return;
        setState(() {
          _register = false;
          _message =
              (response is Map ? response['message'] : null)?.toString() ??
              'Tạo tài khoản thành công. Hãy đăng nhập.';
        });
      } else {
        await _loginWithCredentials(
          _user.text.trim(),
          _password.text,
          faceWasVerified: false,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithFace() async {
    final username = _user.text.trim();
    if (username.isEmpty) {
      setState(() => _message = 'Nhập tên đăng nhập đã đăng ký khuôn mặt.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final enrolled = await FaceLoginService.instance.isEnrolled(username);
      if (!enrolled) {
        if (mounted) {
          setState(
            () => _message =
                'Tên đăng nhập này chưa đăng ký khuôn mặt trên thiết bị này.',
          );
        }
        return;
      }

      final photo = await _captureFace('Đăng nhập bằng khuôn mặt');
      if (photo == null) return;
      bool matched;
      try {
        matched = await FaceLoginService.instance.verify(username, photo.path);
      } finally {
        await _deleteCapture(photo);
      }
      if (!matched) {
        if (mounted) setState(() => _message = 'Khuôn mặt chưa khớp.');
        return;
      }

      // The current API still requires the account password before it sends
      // the Email OTP. Never store the password just to make face login work.
      final password = _password.text.isNotEmpty
          ? _password.text
          : await _askPassword();
      if (password == null || password.isEmpty || !mounted) return;
      await _loginWithCredentials(username, password, faceWasVerified: true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'Đăng nhập khuôn mặt thất bại: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nhập mật khẩu'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Mật khẩu tài khoản'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _loginWithCredentials(
    String username,
    String password, {
    required bool faceWasVerified,
  }) async {
    final response = await AttendanceApi.post('auth/login', {
      'userName': username,
      'password': password,
    }) as Map<String, dynamic>;
    if (!mounted) return;

    if (!faceWasVerified) {
      var faceReady = false;
      try {
        faceReady = await FaceLoginService.instance.isEnrolled(username);
      } catch (_) {
        // Face storage must not disable the existing password/OTP flow.
      }
      if (faceReady && mounted) {
        final wantsFaceCheck = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Xác minh khuôn mặt'),
            content: const Text(
              'Tài khoản này đã đăng ký khuôn mặt trên thiết bị. '
              'Bạn có thể quét để xác minh thêm hoặc tiếp tục bằng Email OTP.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Tiếp tục bằng OTP'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('Quét khuôn mặt'),
              ),
            ],
          ),
        );
        if (wantsFaceCheck == true) {
          final photo = await _captureFace('Xác minh khuôn mặt');
          if (photo != null) {
            try {
              final matched = await FaceLoginService.instance.verify(
                username,
                photo.path,
              );
              if (!matched && mounted) {
                setState(
                  () => _message =
                      'Khuôn mặt chưa khớp. Bạn vẫn có thể hoàn tất đăng nhập bằng Email OTP.',
                );
              }
            } finally {
              await _deleteCapture(photo);
            }
          }
        }
      }
    }

    final session = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpDialog(
        username: username,
        maskedEmail: response['maskedEmail']?.toString() ?? 'email đã đăng ký',
      ),
    );
    if (session == null || !mounted) return;

    var hasFace = true;
    try {
      hasFace = await FaceLoginService.instance.isEnrolled(username);
    } catch (_) {
      // Preserve sign-in if local face storage is unavailable.
    }
    if (!hasFace && mounted) {
      final enrollFace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bật xác minh khuôn mặt?'),
          content: const Text(
            'Bạn có muốn đăng ký khuôn mặt trên thiết bị này? '
            'Mẫu nhận diện được lưu cục bộ; ảnh không được gửi lên máy chủ. '
            'Mật khẩu và Email OTP vẫn được giữ nguyên.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Đăng ký khuôn mặt'),
            ),
          ],
        ),
      );
      if (enrollFace == true && mounted) {
        try {
          final photo = await _captureFace('Đăng ký khuôn mặt');
          if (photo != null) {
            try {
              await FaceLoginService.instance.enroll(username, photo.path);
            } finally {
              await _deleteCapture(photo);
            }
          }
        } catch (error) {
          if (mounted) {
            setState(
              () => _message =
                  'Đăng nhập thành công nhưng chưa lưu được khuôn mặt. ($error)',
            );
          }
        }
      }
    }
    await AttendanceApi.saveSession(session);
    widget.onSignedIn(session);
  }

  Future<XFile?> _captureFace(String title) => Navigator.of(context)
      .push<XFile>(
        MaterialPageRoute<XFile>(
          builder: (_) => FaceCaptureScreen(title: title),
        ),
      );

  Future<void> _deleteCapture(XFile photo) async {
    try {
      await File(photo.path).delete();
    } on FileSystemException {
      // The camera plugin may already have cleaned up its temporary image.
    }
  }

  Future<void> _removeFaceProfile() async {
    final userName = _user.text.trim();
    if (userName.isEmpty) {
      setState(
        () => _message = 'Nhập tên đăng nhập trước khi xóa mẫu khuôn mặt.',
      );
      return;
    }
    try {
      final enrolled = await FaceLoginService.instance.isEnrolled(userName);
      if (!enrolled) {
        if (mounted) {
          setState(
            () =>
                _message = 'Tài khoản này chưa có mẫu khuôn mặt trên thiết bị.',
          );
        }
        return;
      }
      await FaceLoginService.instance.remove(userName);
      if (mounted)
        setState(() => _message = 'Đã xóa mẫu khuôn mặt trên thiết bị này.');
    } catch (error) {
      if (mounted)
        setState(() => _message = 'Không xóa được mẫu khuôn mặt. ($error)');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B705D), Color(0xFF145448)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B705D).withValues(alpha: .18),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.access_time_filled_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _register ? 'Tạo tài khoản' : 'Dasani Attendance',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _register
                                  ? 'Đăng ký bằng email công ty'
                                  : 'Đăng nhập và xác minh bằng Email OTP',
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE7EEEA)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1D3D32).withValues(alpha: .04),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_register) ...[
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: _required,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => (v ?? '').contains('@')
                                ? null
                                : 'Nhập email hợp lệ',
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _user,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Tên đăng nhập',
                            prefixIcon: Icon(Icons.account_circle_outlined),
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => (v ?? '').length >= 8
                              ? null
                              : 'Mật khẩu tối thiểu 8 ký tự',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F3F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_message!),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_register ? 'Đăng ký' : 'Đăng nhập'),
                ),
                if (!_register) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _loginWithFace,
                    icon: const Icon(Icons.face_retouching_natural),
                    label: const Text('Đăng nhập bằng khuôn mặt'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Quét khuôn mặt đã đăng ký, sau đó xác minh bằng mật khẩu và Email OTP.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _register = !_register;
                          _message = null;
                        }),
                  child: Text(
                    _register
                        ? 'Đã có tài khoản? Đăng nhập'
                        : 'Chưa có tài khoản? Đăng ký',
                  ),
                ),
                if (!_register)
                  TextButton.icon(
                    onPressed: _busy ? null : _removeFaceProfile,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Xóa mẫu khuôn mặt trên thiết bị này'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'API: ${AttendanceApi.baseUrl}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Trường này không được để trống' : null;
}

class _OtpDialog extends StatefulWidget {
  const _OtpDialog({required this.username, required this.maskedEmail});
  final String username;
  final String maskedEmail;

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await AttendanceApi.post('auth/verify-otp', {
        'username': widget.username,
        'code': _code.text.trim(),
      });
      if (mounted) {
        final response = Map<String, dynamic>.from(result as Map);
        Navigator.of(context).pop({
          'accessToken': response['token'],
          'role': response['role'],
          'userName': response['fullName'] ?? widget.username,
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác minh Email OTP'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Nhập mã 6 số đã gửi tới ${widget.maskedEmail}.'),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Mã OTP'),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _busy || _code.text.length != 6 ? null : _verify,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Xác minh'),
      ),
    ],
  );
}
