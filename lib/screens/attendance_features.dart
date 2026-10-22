import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_client.dart';
import '../services/attendance_events.dart';

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});
  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
  bool _busy = false;
  String? _status;
  String? _error;
  String? _currentCoordinates;
  Map<String, dynamic>? _workplace;

  @override
  void initState() {
    super.initState();
    _loadWorkplace();
  }

  Future<void> _loadWorkplace() async {
    try {
      final result = await AttendanceApi.get('attendance/location');
      if (mounted && result is Map) {
        setState(() => _workplace = Map<String, dynamic>.from(result));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _punch(bool checkIn) async {
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiException('Cần cấp quyền vị trí để chấm công.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiException('Hãy bật dịch vụ vị trí trên thiết bị.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final request = <String, dynamic>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'qrCode': 'GPS',
      };
      if (mounted) {
        setState(() {
          _currentCoordinates =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
      if (checkIn) {
        final result = await AttendanceApi.post('attendance/check-in', request);
        notifyAttendanceChanged();
        if (mounted) {
          setState(
            () => _status =
                'Đã ghi nhận vào ca bằng GPS${result is Map && result['status'] == 'Flagged' ? ' · Có cảnh báo vị trí' : ''}',
          );
        }
      } else {
        final result = await AttendanceApi.post(
          'attendance/check-out',
          request,
        );
        notifyAttendanceChanged();
        if (mounted) {
          setState(
            () => _status =
                'Đã ghi nhận ra ca${result is Map && result['status'] == 'Flagged' ? ' · Có cảnh báo vị trí' : ''}',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chấm công bằng GPS')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F5F0), Color(0xFFDDF0E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD7EAE2)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 62,
                color: Color(0xFF146B5B),
              ),
              SizedBox(height: 12),
              const Text(
                'Ghi nhận giờ làm và vị trí hiện tại',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Khi chấm công vào ca, ứng dụng xin quyền vị trí và gửi tọa độ GPS cùng thời gian lên API.',
                textAlign: TextAlign.center,
              ),
              if (_workplace != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Khu vực cho phép: ${_workplace!['name'] ?? 'Địa điểm làm việc'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_workplace!['address'] ?? ''}\nBán kính: ${(_workplace!['radiusMeters'] as num?)?.toStringAsFixed(0) ?? '—'} m',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_currentCoordinates != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Vị trí GPS hiện tại: $_currentCoordinates',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : () => _punch(true),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Chấm công vào ca'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _punch(false),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Chấm công ra ca'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_status != null) _result(_status!, Colors.green),
        if (_error != null) _result(_error!, Colors.red),
      ],
    ),
  );
  Widget _result(String text, Color color) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: TextStyle(color: color)),
  );
}

class NoiseMeterScreen extends StatefulWidget {
  const NoiseMeterScreen({super.key});
  @override
  State<NoiseMeterScreen> createState() => _NoiseMeterScreenState();
}

class _NoiseMeterScreenState extends State<NoiseMeterScreen> {
  NoiseMeter? _meter;
  StreamSubscription<NoiseReading>? _subscription;
  double? _mean;
  double? _peak;
  String? _error;
  bool _running = false;
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_running) {
      await _subscription?.cancel();
      if (mounted) setState(() => _running = false);
      return;
    }
    try {
      var permission = await Permission.microphone.status;
      if (!permission.isGranted) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) {
        throw ApiException('Cần cấp quyền micro để đo tiếng ồn.');
      }
      _meter ??= NoiseMeter();
      _subscription = _meter!.noise.listen(
        (reading) {
          if (mounted) {
            setState(() {
              _mean = reading.meanDecibel;
              _peak = reading.maxDecibel;
            });
          }
        },
        onError: (Object e) {
          if (mounted) {
            setState(() {
              _error = e.toString();
              _running = false;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _running = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đo tiếng ồn')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _running ? Icons.graphic_eq : Icons.mic_none_rounded,
              color: const Color(0xFF146B5B),
              size: 78,
            ),
            const SizedBox(height: 18),
            Text(
              _running ? 'Micro đang ghi nhận' : 'Sẵn sàng đo',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 26),
            _meterValue('Mức trung bình', _mean),
            const SizedBox(height: 12),
            _meterValue('Mức đỉnh', _peak),
            const SizedBox(height: 10),
            const Text(
              'Giá trị dB mang tính tham khảo theo thiết bị, không phải thiết bị đo đã hiệu chuẩn.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(_running ? Icons.stop : Icons.mic),
              label: Text(_running ? 'Dừng đo' : 'Bắt đầu đo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _meterValue(String label, double? value) => Card(
    elevation: 0,
    color: Colors.white,
    child: ListTile(
      title: Text(label),
      trailing: Text(
        value == null ? '-- dB' : '${value.toStringAsFixed(1)} dB',
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: Color(0xFF146B5B),
        ),
      ),
    ),
  );
}
