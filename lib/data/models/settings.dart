class Settings {
  final String firmName;
  final String phone;
  final String address;
  final String? gstin;
  final String state;
  final String stateCode;

  Settings({
    required this.firmName,
    required this.phone,
    required this.address,
    this.gstin,
    this.state = 'Telangana',
    this.stateCode = '36',
  });

  Settings copyWith({
    String? firmName,
    String? phone,
    String? address,
    String? gstin,
    String? state,
    String? stateCode,
  }) {
    return Settings(
      firmName: firmName ?? this.firmName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      gstin: gstin ?? this.gstin,
      state: state ?? this.state,
      stateCode: stateCode ?? this.stateCode,
    );
  }

  /// Parses a list of key-value maps from the SQLite settings table into a Settings object
  factory Settings.fromMapList(List<Map<String, dynamic>> maps) {
    String firmName = '';
    String phone = '';
    String address = '';
    String? gstin;
    String state = 'Telangana';
    String stateCode = '36';

    for (final row in maps) {
      final key = row['key'] as String;
      final val = row['value'] as String;
      switch (key) {
        case 'firm_name':
          firmName = val;
          break;
        case 'phone':
          phone = val;
          break;
        case 'address':
          address = val;
          break;
        case 'gstin':
          gstin = val.trim().isEmpty ? null : val;
          break;
        case 'state':
          state = val;
          break;
        case 'state_code':
          stateCode = val;
          break;
      }
    }

    return Settings(
      firmName: firmName,
      phone: phone,
      address: address,
      gstin: gstin,
      state: state,
      stateCode: stateCode,
    );
  }

  /// Converts Settings object to key-value maps for database persistence
  Map<String, String> toMap() {
    return {
      'firm_name': firmName,
      'phone': phone,
      'address': address,
      'gstin': gstin ?? '',
      'state': state,
      'state_code': stateCode,
    };
  }

  /// Checks if Settings are valid (firm name, phone, and address are mandatory)
  bool get isValid {
    return firmName.trim().isNotEmpty && phone.trim().isNotEmpty && address.trim().isNotEmpty;
  }
}
