class Passenger {
  const Passenger({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.idNumber,
    required this.phone,
    required this.balance,
    required this.mustChangePassword,
    this.userType = 'Passenger',
    this.email = '',
    this.emailVerified = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String idNumber;
  final String phone;
  final double balance;
  final bool mustChangePassword;
  final String userType;
  final String email;
  final bool emailVerified;

  String get fullName => '$firstName $lastName'.trim();

  factory Passenger.fromJson(Map<String, dynamic> json) => Passenger(
    id: '${json['id'] ?? ''}',
    firstName: '${json['firstName'] ?? ''}',
    lastName: '${json['lastName'] ?? ''}',
    idNumber: '${json['idNumber'] ?? ''}',
    phone: '${json['phone'] ?? json['contactNumber'] ?? ''}',
    balance:
        (json['balance'] as num?)?.toDouble() ??
        double.tryParse('${json['balance']}') ??
        0,
    mustChangePassword: json['mustChangePassword'] == true,
    userType: '${json['userType'] ?? 'Passenger'}',
    email: '${json['email'] ?? ''}'.trim(),
    emailVerified: json['emailVerified'] == true,
  );

  Passenger copyWith({
    bool? mustChangePassword,
    String? email,
    bool? emailVerified,
  }) => Passenger(
    id: id,
    firstName: firstName,
    lastName: lastName,
    idNumber: idNumber,
    phone: phone,
    balance: balance,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    userType: userType,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
  );
}
