// ============================================================================
// CONFIGURATION
// ============================================================================
const String _backendHost = '192.168.1.17:8000';
const String backendBaseUrl = 'http://$_backendHost';
const String backendWebSocketUrl = 'ws://$_backendHost/ws/dashboard';
const double literPerGallon = 3.78541;
const int maxNotifications = 50;

// Alert refresh interval (seconds) - for database-backed alerts
const int alertRefreshInterval = 30;

// ============================================================================
// COLOR PALETTE - Consistent Design System (Moved from main.dart)
// ============================================================================
const primaryColor = 0xFF00BCD4; // Teal/Cyan
const secondaryColor = 0xFF4CAF50; // Green
const accentColor = 0xFF2196F3; // Blue
const errorColor = 0xFFF44336; // Red
const warningColor = 0xFFFF9800; // Orange
const successColor = 0xFF4CAF50; // Green

// Gradient colors
const gradientStart = 0xFF00BCD4; // Primary
const gradientEnd = 0xFF2196F3; // Accent