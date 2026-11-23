class AuthSession {
  AuthSession._();
  static final AuthSession instance = AuthSession._();
  Map<String, Object?>? _user;
  Map<String, Object?>? get user => _user == null ? null : Map.unmodifiable(_user!);
  int? get userId => _user?['id'] as int?;
  String? get role => _user?['role']?.toString();
  String? get displayName => _user?['display_name']?.toString();
  bool get isAdmin => role == 'admin';
  bool get isCashier => role == 'cashier';
  bool get isMechanic => role == 'mechanic';
  bool get isCashierOrAdmin => isCashier || isAdmin;
  void requireAdmin(String message) {
    if (!isAdmin) throw StateError(message);
  }
  void requireCashierOrAdmin(String message) {
    if (!isCashierOrAdmin) throw StateError(message);
  }
  void signIn(Map<String, Object?> user) { _user = Map<String, Object?>.from(user); }
  void signOut() { _user = null; }
}
