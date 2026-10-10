class PasswordPolicy {
  const PasswordPolicy._();

  static String? validate(String? value) {
    if (value == null || value.isEmpty) return 'Enter a new password.';
    if (value.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Add at least one uppercase letter.';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      return 'Add at least one special character.';
    }
    return null;
  }
}
