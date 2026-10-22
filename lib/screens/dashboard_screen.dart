import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/attendance_events.dart';
import 'attendance_features.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.role,
    required this.userName,
    required this.employeeId,
    required this.onSignOut,
  });
  final String role;
  final String userName;
  final int? employeeId;
  final Future<void> Function() onSignOut;

  bool get isAdmin => role.toLowerCase() == 'admin';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Dasani Attendance',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async => notifyAttendanceChanged(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          _WelcomeCard(
            name: userName,
            role: isAdmin ? 'Quản trị viên' : 'Nhân viên',
          ),
          const SizedBox(height: 18),
          if (isAdmin) ...[
            Text(
              'QUẢN TRỊ',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Colors.black54, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.badge_outlined,
              color: const Color(0xFF176B5B),
              title: 'Nhân viên và tài khoản',
              subtitle: 'Thêm, xem, sửa, xóa hồ sơ',
              onTap: () => _open(context, const EmployeesScreen()),
            ),
            _ActionTile(
              icon: Icons.fact_check_outlined,
              color: const Color(0xFF3659A5),
              title: 'Lịch sử chấm công',
              subtitle: 'Tra cứu và hiệu chỉnh bản ghi',
              onTap: () =>
                  _open(context, const AttendanceHistoryScreen(isAdmin: true)),
            ),
            _ActionTile(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFB46A12),
              title: 'Cảnh báo bất thường',
              subtitle: 'QR, vị trí hoặc sai trình tự',
              onTap: () => _open(context, const AlertsScreen()),
            ),
          ] else ...[
            _TodayAttendanceCard(employeeId: employeeId),
            const SizedBox(height: 18),
            Text(
              'CHẤM CÔNG',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Colors.black54, letterSpacing: 1.1),
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.location_on_outlined,
              color: const Color(0xFF176B5B),
              title: 'Chấm công bằng GPS',
              subtitle: 'Ghi nhận giờ vào/ra và vị trí hiện tại',
              onTap: () => _open(context, const PunchScreen()),
            ),
            _ActionTile(
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFF3659A5),
              title: 'Đo tiếng ồn',
              subtitle: 'Đọc mức âm thanh từ micro thiết bị',
              onTap: () => _open(context, const NoiseMeterScreen()),
            ),
            _ActionTile(
              icon: Icons.history_rounded,
              color: const Color(0xFFB46A12),
              title: 'Lịch sử của tôi',
              subtitle: 'Xem các lần chấm công',
              onTap: () =>
                  _open(context, const AttendanceHistoryScreen(isAdmin: false)),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Vai trò: $role',
            style: const TextStyle(color: Colors.black45),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  static Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.name, required this.role});
  final String name;
  final String role;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0B705D), Color(0xFF174F45)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0B705D).withValues(alpha: .16),
          blurRadius: 20,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 29,
          backgroundColor: Colors.white24,
          child: Icon(Icons.person_rounded, color: Colors.white, size: 31),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xin chào, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(role, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const Icon(Icons.waving_hand_rounded, color: Color(0xFFFFD273)),
      ],
    ),
  );
}

class _TodayAttendanceCard extends StatefulWidget {
  const _TodayAttendanceCard({required this.employeeId});
  final int? employeeId;
  @override
  State<_TodayAttendanceCard> createState() => _TodayAttendanceCardState();
}

class _TodayAttendanceCardState extends State<_TodayAttendanceCard> {
  Map<String, dynamic>? _record;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    attendanceRefreshSignal.addListener(_onAttendanceChanged);
    _load();
  }

  @override
  void dispose() {
    attendanceRefreshSignal.removeListener(_onAttendanceChanged);
    super.dispose();
  }

  void _onAttendanceChanged() => _load();

  Future<void> _load() async {
    try {
      final result = await AttendanceApi.get('attendance/my') as List<dynamic>;
      final today = DateTime.now();
      final record = result
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) {
            final date = _recordDate(e);
            return date != null &&
                date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
          })
          .firstOrNull;
      if (mounted) {
        setState(() {
          _record = record;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  DateTime? _recordDate(Map<String, dynamic> record) =>
      DateTime.tryParse(record['checkInAt']?.toString() ?? '')?.toLocal();

  @override
  Widget build(BuildContext context) {
    final checkIn = _record?['checkInAt']?.toString();
    final checkOut = _record?['checkOutAt']?.toString();
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.today_outlined, color: Color(0xFF146B5B)),
                const SizedBox(width: 8),
                Text(
                  'Chấm công hôm nay',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Tải lại',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              Row(
                children: [
                  Expanded(child: _timeInfo('Vào ca', checkIn)),
                  Expanded(child: _timeInfo('Ra ca', checkOut)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _timeInfo(String label, String? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 4),
      Text(
        value == null ? 'Chưa ghi nhận' : _formatTime(value),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );
  String _formatTime(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    return parsed == null
        ? value
        : '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE8EEEA)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .11),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await AttendanceApi.get('employees') as List;
      if (mounted) {
        setState(
          () => _items = value
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _form([Map<String, dynamic>? employee]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EmployeeForm(employee: employee),
    );
    if (result == null) return;
    try {
      if (employee == null) {
        await AttendanceApi.post('employees', result);
      } else {
        await AttendanceApi.put('employees/${employee['id']}', result);
      }
      await _load();
      if (mounted) {
        _message(
          employee == null ? 'Đã tạo nhân viên.' : 'Đã cập nhật nhân viên.',
        );
      }
    } catch (e) {
      if (mounted) _message(e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> employee) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa nhân viên?'),
        content: Text('Xóa ${employee['fullName']} và tài khoản liên kết?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await AttendanceApi.delete('employees/${employee['id']}');
      await _load();
    } catch (e) {
      if (mounted) _message(e.toString());
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhân viên / tài khoản')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _form(),
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Thêm'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = _items[i];
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        (e['fullName']?.toString().isNotEmpty ?? false)
                            ? e['fullName'].toString()[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(e['fullName']?.toString() ?? ''),
                    subtitle: Text(
                      '${e['employeeCode'] ?? ''} · ${e['email'] ?? ''}\n${e['department'] ?? 'Chưa có phòng ban'} · ${(e['isActive'] == true) ? 'Đang hoạt động' : 'Tạm khóa'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _form(e) : _delete(e),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xóa')),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({this.employee});
  final Map<String, dynamic>? employee;
  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.employee?['fullName']?.toString(),
  );
  late final _email = TextEditingController(
    text: widget.employee?['email']?.toString(),
  );
  late final _department = TextEditingController(
    text: widget.employee?['department']?.toString(),
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _active = true;
  @override
  void initState() {
    super.initState();
    _active = widget.employee?['isActive'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _department.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.employee == null ? 'Tạo tài khoản nhân viên' : 'Sửa hồ sơ',
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 380,
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Họ và tên'),
              _field(_email, 'Email', keyboard: TextInputType.emailAddress),
              _field(_department, 'Phòng ban'),
              if (widget.employee == null) ...[
                _field(_username, 'Tên đăng nhập'),
                _field(
                  _password,
                  'Mật khẩu tạm (tối thiểu 8 ký tự)',
                  obscure: true,
                ),
              ],
              if (widget.employee != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Tài khoản hoạt động'),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final data = widget.employee == null
              ? {
                  'fullName': _name.text.trim(),
                  'email': _email.text.trim(),
                  'department': _department.text.trim(),
                  'username': _username.text.trim(),
                  'temporaryPassword': _password.text,
                  'position': 'Nhân viên',
                }
              : {
                  'fullName': _name.text.trim(),
                  'email': _email.text.trim(),
                  'department': _department.text.trim(),
                  'isActive': _active,
                };
          Navigator.pop(context, data);
        },
        child: const Text('Lưu'),
      ),
    ],
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      validator: (v) => (v ?? '').trim().isEmpty ? 'Không được để trống' : null,
    ),
  );
}

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key, required this.isAdmin});
  final bool isAdmin;
  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await AttendanceApi.get(
        widget.isAdmin ? 'attendance' : 'attendance/my',
      ) as List;
      if (mounted) {
        setState(
          () => _records = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final inController = TextEditingController(
      text: _localInput(r['checkInAt']),
    );
    final outController = TextEditingController(
      text: _localInput(r['checkOutAt']),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hiệu chỉnh bản ghi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: inController,
              decoration: const InputDecoration(
                labelText: 'Giờ vào (ISO 8601 hoặc để trống)',
              ),
            ),
            TextField(
              controller: outController,
              decoration: const InputDecoration(
                labelText: 'Giờ ra (ISO 8601 hoặc để trống)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (result != true) return;
    try {
      await AttendanceApi.put('attendance/${r['id']}', {
        'checkInAt': inController.text.trim().isEmpty
            ? null
            : inController.text.trim(),
        'checkOutAt': outController.text.trim().isEmpty
            ? null
            : outController.text.trim(),
        'status': 'Corrected',
        'anomalyNote': r['anomalyNote'],
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    inController.dispose();
    outController.dispose();
  }

  String? _localInput(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    return d?.toLocal().toIso8601String();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bản ghi?'),
        content: const Text('Thao tác này xóa lịch sử chấm công đã chọn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await AttendanceApi.delete('attendance/${r['id']}');
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isAdmin ? 'Lịch sử toàn hệ thống' : 'Lịch sử của tôi'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _busy && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _records.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = _records[i];
                final employee = r['employee'] as Map?;
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: r['status'] == 'Flagged'
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                      child: Icon(
                        r['status'] == 'Flagged'
                            ? Icons.warning_amber
                            : Icons.event_available,
                        color: r['status'] == 'Flagged'
                            ? Colors.orange.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                    title: Text(
                      widget.isAdmin
                          ? (employee?['fullName']?.toString() ?? 'Nhân viên')
                          : _date(r['checkInAt']),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${_date(r['checkInAt'])} · Vào ${_time(r['checkInAt'])} · Ra ${_time(r['checkOutAt'])}\n${r['status'] ?? ''}${(r['note'] ?? '').toString().isEmpty ? '' : ' · ${r['note']}'}${_locationText(r).isEmpty ? '' : '\n${_locationText(r)}'}',
                    ),
                    isThreeLine: true,
                    trailing: widget.isAdmin
                        ? PopupMenuButton<String>(
                            onSelected: (v) =>
                                v == 'edit' ? _edit(r) : _delete(r),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Xóa'),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
    ),
  );
  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    final d = parsed?.toLocal();
    return d == null
        ? (value?.toString() ?? '—')
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _time(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return d == null
        ? '—'
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _locationText(Map<String, dynamic> record) {
    final latitude = record['latitude'];
    final longitude = record['longitude'];
    if (latitude is! num || longitude is! num) return '';
    return 'GPS: ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  Future<void> _load() async {
    try {
      final data = await AttendanceApi.get(
        'attendance/alerts',
        query: const {'unresolvedOnly': 'false'},
      ) as List;
      if (mounted) {
        setState(() {
          _items = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _resolve(int id) async {
    try {
      await AttendanceApi.put('attendance/alerts/$id/resolve');
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cảnh báo chấm công')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _error != null
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final alert = _items[i];
                final employee = alert['employee'] as Map?;
                final resolved = alert['isResolved'] == true;
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(
                      resolved
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      color: resolved ? Colors.green : Colors.deepOrange,
                    ),
                    title: Text(
                      '${alert['type'] ?? 'Bất thường'} · ${employee?['fullName'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${alert['details'] ?? ''}\n${alert['createdAtUtc'] ?? ''}',
                    ),
                    isThreeLine: true,
                    trailing: resolved
                        ? const Text('Đã xử lý')
                        : IconButton(
                            tooltip: 'Đánh dấu đã xử lý',
                            onPressed: () =>
                                _resolve((alert['id'] as num).toInt()),
                            icon: const Icon(Icons.done),
                          ),
                  ),
                );
              },
            ),
    ),
  );
}
