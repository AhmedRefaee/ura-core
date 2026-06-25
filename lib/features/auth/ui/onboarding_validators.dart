// Shared validation used across the onboarding screens.

/// Returns an Arabic error message when [phone] is not a valid Saudi WhatsApp
/// number (10 digits starting with 05), or null when it is valid.
String? validateSaudiPhone(String phone) {
  if (phone.isEmpty) return 'رقم الواتساب مطلوب';
  if (!RegExp(r'^05\d{8}$').hasMatch(phone)) {
    return 'الرقم يجب أن يبدأ بـ 05 ويتكون من 10 أرقام';
  }
  return null;
}
