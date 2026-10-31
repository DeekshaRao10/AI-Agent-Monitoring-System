import '../services/auth_service.dart';

class AuthProvider {
  final AuthService _service = AuthService();//creates instance of auth service class to access its methods

  Future<void> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _service.signUp(
      name: name,
      email: email,
      phone: phone,
      password: password,
    );
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _service.login(
      email: email,
      password: password,
    );
  }
}