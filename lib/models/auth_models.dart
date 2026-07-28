/// Mirrors backend_python/schemas/auth.py::TokenResponse exactly.
class TokenResponse {
  const TokenResponse({required this.accessToken, required this.refreshToken, required this.tokenType});

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
      );
}

/// Decoded from the access token's JWT payload (sub/role/organization_id)
/// so the UI can show "who's logged in" without a separate profile call.
class AuthenticatedUser {
  const AuthenticatedUser({required this.userId, required this.role, this.organizationId});

  final String userId;
  final String role;
  final String? organizationId;
}
