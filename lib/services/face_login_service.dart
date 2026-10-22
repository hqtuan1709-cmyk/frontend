import 'package:face_verification/face_verification.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FaceLoginService {
  FaceLoginService._();

  static final FaceLoginService instance = FaceLoginService._();
  static const _imageId = 'primary';
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await FaceVerification.instance.init(numThreads: 2);
    _initialized = true;
  }

  Future<bool> isEnrolled(String userName) async {
    final userId = _userId(userName);
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool(_enrollmentKey(userId)) ?? false)) return false;
    await _ensureInitialized();
    final enrolled = await FaceVerification.instance.isFaceRegistered(userId);
    if (!enrolled) await preferences.remove(_enrollmentKey(userId));
    return enrolled;
  }

  Future<void> enroll(String userName, String imagePath) async {
    final userId = _userId(userName);
    await _ensureInitialized();
    await FaceVerification.instance.registerFromImagePath(
      id: userId,
      imagePath: imagePath,
      imageId: _imageId,
      replace: true,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enrollmentKey(userId), true);
  }

  Future<bool> verify(String userName, String imagePath) async {
    await _ensureInitialized();
    final match = await FaceVerification.instance.verifyFromImagePath(
      imagePath: imagePath,
      threshold: 0.70,
      staffId: _userId(userName),
    );
    return match == _userId(userName);
  }

  Future<void> remove(String userName) async {
    await _ensureInitialized();
    final userId = _userId(userName);
    await FaceVerification.instance.deleteUserFaces(userId);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_enrollmentKey(userId));
  }

  String _userId(String userName) => userName.trim().toLowerCase();
  String _enrollmentKey(String userId) => 'face_enrolled_$userId';
}
