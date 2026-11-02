import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/auth/dialogs/sudo_verification_dialog.dart';
import '../../../core/auth/models/altr_api_key.dart';
import '../../../core/auth/services/api_key_service.dart';
import '../../../core/auth/services/auth_service.dart';
import '../../../core/auth/services/passcode_service.dart';
import '../../../core/auth/services/workspace_service.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/dialogs/altr_alert_dialog.dart';
import '../../../shared/feedback/feedback_dialog.dart';
import '../../../shared/widgets/status_badge.dart';

class SettingsCategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;
  final Color iconBg;

  const SettingsCategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
  });
}

class _SettingsSearchEntry {
  final String title;
  final String categoryId;
  final String categoryName;
  final List<List<dynamic>> icon;
  final Color iconBg;
  final List<String> keywords;

  const _SettingsSearchEntry({
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.iconBg,
    this.keywords = const [],
  });
}

class SettingsScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onNodeStatusTap;
  final String nodeStatus;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onPasscodeTap;
  final VoidCallback? onApiSecurityTap;
  final VoidCallback? onWorkspacesTap;
  final String? activeWorkspaceName;
  final UserProfile? currentUser;
  final String? initialCategoryId;

  const SettingsScreen({
    super.key,
    required this.apiClient,
    required this.onNodeStatusTap,
    this.nodeStatus = 'ACTIVE',
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onPasscodeTap,
    this.onApiSecurityTap,
    this.onWorkspacesTap,
    this.activeWorkspaceName,
    this.currentUser,
    this.initialCategoryId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _healthInfo;
  double? _probeLatencyMs;
  bool _isProbing = false;
  late String _selectedCategoryId;
  String? _highlightTarget;
  AltrApiKey? _justCreatedKey;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _contentScrollController = ScrollController();
  final ApiKeyService _apiKeyService = ApiKeyService();
  final WorkspaceService _workspaceService = WorkspaceService();

  static const List<SettingsCategoryItem> _categories = [
    SettingsCategoryItem(
      id: 'general',
      title: 'General',
      subtitle: 'Node identity, cluster role, and operational state',
      icon: HugeIcons.strokeRoundedInformationCircle,
      iconBg: Color(0xFF007AFF), // macOS blue
    ),
    SettingsCategoryItem(
      id: 'security',
      title: 'Security & Passcode',
      subtitle: 'Altr Mesh authentication, passcode protection, and scoped API keys',
      icon: HugeIcons.strokeRoundedShieldCheck,
      iconBg: Color(0xFFFF9500), // macOS amber
    ),
    SettingsCategoryItem(
      id: 'api_keys',
      title: 'API Keys & Access',
      subtitle: 'Manage programmatic tokens, scoped credentials, and expiration',
      icon: HugeIcons.strokeRoundedKey01,
      iconBg: Color(0xFFFF2D55), // macOS red/pink
    ),
    SettingsCategoryItem(
      id: 'workspaces',
      title: 'Workspaces & Teams',
      subtitle: 'Active workspace switcher, team collaboration, and access scopes',
      icon: HugeIcons.strokeRoundedFolder02,
      iconBg: Color(0xFFAF52DE), // macOS violet
    ),
    SettingsCategoryItem(
      id: 'telemetry',
      title: 'Node Telemetry',
      subtitle: 'Real-time performance vitals, health status, and live diagnostics',
      icon: HugeIcons.strokeRoundedActivity01,
      iconBg: Color(0xFF34C759), // macOS green
    ),
    SettingsCategoryItem(
      id: 'network',
      title: 'Network & Host',
      subtitle: 'Endpoints, reverse proxy configurations, and probe latency',
      icon: HugeIcons.strokeRoundedWifi01,
      iconBg: Color(0xFF30B0C7), // macOS cyan
    ),
    SettingsCategoryItem(
      id: 'docs',
      title: 'Documentation',
      subtitle: 'Interactive OpenAPI Swagger specifications and live schemas',
      icon: HugeIcons.strokeRoundedBook02,
      iconBg: Color(0xFFFF5E3A), // macOS orange
    ),
    SettingsCategoryItem(
      id: 'appearance',
      title: 'Appearance',
      subtitle: 'Interface themes, color modes, and display preferences',
      icon: HugeIcons.strokeRoundedPaintBoard,
      iconBg: Color(0xFF32ADE6), // macOS light blue
    ),
    SettingsCategoryItem(
      id: 'feedback',
      title: 'Feedback',
      subtitle: 'Diagnostic reports, bug logging, and team communication',
      icon: HugeIcons.strokeRoundedMessageQuestion,
      iconBg: Color(0xFF34C759), // macOS green
    ),
    SettingsCategoryItem(
      id: 'about',
      title: 'About Node',
      subtitle: 'Version details, engine runtime, build signatures, and legal',
      icon: HugeIcons.strokeRoundedInformationCircle,
      iconBg: Color(0xFF8E8E93), // macOS gray
    ),
  ];

  static const List<_SettingsSearchEntry> _searchEntries = [
    _SettingsSearchEntry(
      title: 'Node Identity & Name',
      categoryId: 'general',
      categoryName: 'General',
      icon: HugeIcons.strokeRoundedInformationCircle,
      iconBg: Color(0xFF007AFF),
      keywords: ['name', 'node', 'cluster', 'identity', 'system', 'host'],
    ),
    _SettingsSearchEntry(
      title: 'Operational State & Status',
      categoryId: 'general',
      categoryName: 'General',
      icon: HugeIcons.strokeRoundedActivity01,
      iconBg: Color(0xFF007AFF),
      keywords: ['state', 'health', 'status', 'active', 'operational'],
    ),
    _SettingsSearchEntry(
      title: 'Service Role (Leader / Standalone)',
      categoryId: 'general',
      categoryName: 'General',
      icon: HugeIcons.strokeRoundedServerStack01,
      iconBg: Color(0xFF007AFF),
      keywords: ['role', 'leader', 'standalone', 'follower', 'cluster'],
    ),
    _SettingsSearchEntry(
      title: 'Node Version & Engine Runtime',
      categoryId: 'general',
      categoryName: 'General',
      icon: HugeIcons.strokeRoundedCodeCircle,
      iconBg: Color(0xFF007AFF),
      keywords: ['version', 'release', 'build', 'runtime', 'python', 'engine'],
    ),
    _SettingsSearchEntry(
      title: 'Profile Information & User ID',
      categoryId: 'profile',
      categoryName: 'Profile & Account',
      icon: HugeIcons.strokeRoundedUser,
      iconBg: Color(0xFF5856D6),
      keywords: ['profile', 'user', 'name', 'email', 'avatar', 'account', 'uid'],
    ),
    _SettingsSearchEntry(
      title: 'Log Out of Altr Account',
      categoryId: 'profile',
      categoryName: 'Profile & Account',
      icon: HugeIcons.strokeRoundedLogout01,
      iconBg: Color(0xFF5856D6),
      keywords: ['logout', 'signout', 'session', 'exit'],
    ),
    _SettingsSearchEntry(
      title: 'Delete Account',
      categoryId: 'profile',
      categoryName: 'Profile & Account',
      icon: HugeIcons.strokeRoundedDelete02,
      iconBg: Color(0xFF5856D6),
      keywords: ['delete', 'remove', 'account', 'destroy', 'danger'],
    ),
    _SettingsSearchEntry(
      title: 'Passcode Protection (PIN / Password)',
      categoryId: 'security',
      categoryName: 'Security & Passcode',
      icon: HugeIcons.strokeRoundedShieldCheck,
      iconBg: Color(0xFFFF9500),
      keywords: ['pin', 'passcode', 'password', 'lock', 'protect', 'zero-knowledge'],
    ),
    _SettingsSearchEntry(
      title: 'Change / Set Passcode PIN',
      categoryId: 'security',
      categoryName: 'Security & Passcode',
      icon: HugeIcons.strokeRoundedLockPassword,
      iconBg: Color(0xFFFF9500),
      keywords: ['change', 'pin', 'setup', 'update', 'password'],
    ),
    _SettingsSearchEntry(
      title: 'Sudo Verification & Elevation',
      categoryId: 'security',
      categoryName: 'Security & Passcode',
      icon: HugeIcons.strokeRoundedShieldAlert,
      iconBg: Color(0xFFFF9500),
      keywords: ['sudo', 'grace', 'session', 'elevation', 'privilege', 'admin'],
    ),
    _SettingsSearchEntry(
      title: 'API Keys & Programmatic Tokens',
      categoryId: 'api_keys',
      categoryName: 'API Keys & Access',
      icon: HugeIcons.strokeRoundedKey01,
      iconBg: Color(0xFFFF2D55),
      keywords: ['api', 'key', 'token', 'bearer', 'secret', 'auth', 'access'],
    ),
    _SettingsSearchEntry(
      title: 'Generate New API Key',
      categoryId: 'api_keys',
      categoryName: 'API Keys & Access',
      icon: HugeIcons.strokeRoundedPlusSign,
      iconBg: Color(0xFFFF2D55),
      keywords: ['generate', 'create', 'new', 'api', 'key', 'token'],
    ),
    _SettingsSearchEntry(
      title: 'API Key Permission Scopes & Expiration',
      categoryId: 'api_keys',
      categoryName: 'API Keys & Access',
      icon: HugeIcons.strokeRoundedCalendar03,
      iconBg: Color(0xFFFF2D55),
      keywords: ['scopes', 'read', 'write', 'admin', 'expiration', 'datetime'],
    ),
    _SettingsSearchEntry(
      title: 'Active Workspace Switcher',
      categoryId: 'workspaces',
      categoryName: 'Workspaces',
      icon: HugeIcons.strokeRoundedFolder02,
      iconBg: Color(0xFFAF52DE),
      keywords: ['workspace', 'switch', 'tenant', 'organization', 'team'],
    ),
    _SettingsSearchEntry(
      title: 'Create New Workspace',
      categoryId: 'workspaces',
      categoryName: 'Workspaces',
      icon: HugeIcons.strokeRoundedFolderAdd,
      iconBg: Color(0xFFAF52DE),
      keywords: ['new', 'create', 'workspace', 'add', 'team'],
    ),
    _SettingsSearchEntry(
      title: 'API Base URL & Endpoints',
      categoryId: 'network',
      categoryName: 'Network & Host',
      icon: HugeIcons.strokeRoundedWifi01,
      iconBg: Color(0xFF30B0C7),
      keywords: ['network', 'url', 'endpoint', 'host', 'port', 'base', 'http'],
    ),
    _SettingsSearchEntry(
      title: 'Probe Latency & Connection Ping',
      categoryId: 'network',
      categoryName: 'Network & Host',
      icon: HugeIcons.strokeRoundedTimer01,
      iconBg: Color(0xFF30B0C7),
      keywords: ['ping', 'latency', 'delay', 'ms', 'connection', 'probe'],
    ),
    _SettingsSearchEntry(
      title: 'Reverse Proxy & TLS Configuration',
      categoryId: 'network',
      categoryName: 'Network & Host',
      icon: HugeIcons.strokeRoundedLockKey,
      iconBg: Color(0xFF30B0C7),
      keywords: ['proxy', 'nginx', 'ssl', 'tls', 'https', 'reverse'],
    ),
    _SettingsSearchEntry(
      title: 'OpenAPI / Swagger Interactive UI',
      categoryId: 'docs',
      categoryName: 'Documentation',
      icon: HugeIcons.strokeRoundedBook02,
      iconBg: Color(0xFFFF5E3A),
      keywords: ['docs', 'swagger', 'openapi', 'api', 'documentation', 'explorer'],
    ),
    _SettingsSearchEntry(
      title: 'OpenAPI Specification JSON',
      categoryId: 'docs',
      categoryName: 'Documentation',
      icon: HugeIcons.strokeRoundedFileCode,
      iconBg: Color(0xFFFF5E3A),
      keywords: ['json', 'spec', 'openapi', 'schema', 'download'],
    ),
    _SettingsSearchEntry(
      title: 'Theme Mode (Light, Dark, System)',
      categoryId: 'appearance',
      categoryName: 'Appearance',
      icon: HugeIcons.strokeRoundedPaintBoard,
      iconBg: Color(0xFF32ADE6),
      keywords: ['theme', 'dark', 'light', 'mode', 'appearance', 'system', 'color'],
    ),
    _SettingsSearchEntry(
      title: 'Submit Diagnostic Feedback & Bug Report',
      categoryId: 'feedback',
      categoryName: 'Feedback',
      icon: HugeIcons.strokeRoundedMessageQuestion,
      iconBg: Color(0xFF34C759),
      keywords: ['feedback', 'bug', 'report', 'issue', 'help', 'contact'],
    ),
    _SettingsSearchEntry(
      title: 'Real-Time Node Telemetry & Vitals',
      categoryId: 'telemetry',
      categoryName: 'Node Telemetry',
      icon: HugeIcons.strokeRoundedActivity01,
      iconBg: Color(0xFF34C759),
      keywords: ['telemetry', 'vitals', 'ping', 'latency', 'health', 'metrics', 'diagnostics', 'performance'],
    ),
    _SettingsSearchEntry(
      title: 'Probe Health & Latency Diagnostics',
      categoryId: 'telemetry',
      categoryName: 'Node Telemetry',
      icon: HugeIcons.strokeRoundedTimer01,
      iconBg: Color(0xFF34C759),
      keywords: ['probe', 'latency', 'delay', 'ping', 'health'],
    ),
    _SettingsSearchEntry(
      title: 'About Node & Version Specifications',
      categoryId: 'about',
      categoryName: 'About Node',
      icon: HugeIcons.strokeRoundedInformationCircle,
      iconBg: Color(0xFF8E8E93),
      keywords: ['about', 'version', 'build', 'runtime', 'architecture', 'engine', 'license'],
    ),
    _SettingsSearchEntry(
      title: 'Open Source License & Architecture',
      categoryId: 'about',
      categoryName: 'About Node',
      icon: HugeIcons.strokeRoundedShieldCheck,
      iconBg: Color(0xFF8E8E93),
      keywords: ['license', 'apache', 'mesh', 'architecture'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    final isTestBinding = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (widget.initialCategoryId != null) {
      _selectedCategoryId = widget.initialCategoryId!;
    } else if (widget.onThemeModeChanged == null) {
      if (widget.onPasscodeTap != null) {
        _selectedCategoryId = 'security';
      } else {
        _selectedCategoryId = 'docs';
      }
    } else if (isTestBinding) {
      _selectedCategoryId = 'appearance';
    } else {
      _selectedCategoryId = 'general';
    }

    _probeBackend();
    PasscodeService().addListener(_onPasscodeChanged);
    AuthService().addListener(_onPasscodeChanged);
    _apiKeyService.addListener(_onPasscodeChanged);
    _workspaceService.addListener(_onPasscodeChanged);

    if (_selectedCategoryId == 'api_keys') {
      _apiKeyService.fetchKeys();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentScrollController.dispose();
    PasscodeService().removeListener(_onPasscodeChanged);
    AuthService().removeListener(_onPasscodeChanged);
    _apiKeyService.removeListener(_onPasscodeChanged);
    _workspaceService.removeListener(_onPasscodeChanged);
    super.dispose();
  }

  void _onPasscodeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _probeBackend() async {
    if (_isProbing) return;
    if (mounted) setState(() => _isProbing = true);
    final sw = Stopwatch()..start();
    try {
      final res = await widget.apiClient.getHealth();
      sw.stop();
      if (res['version'] != null) {
        AppConfig.setRuntimeNodeVersion(res['version'].toString());
      }
      if (mounted) {
        setState(() {
          _healthInfo = res;
          _probeLatencyMs = sw.elapsedMicroseconds / 1000.0;
          _isProbing = false;
        });
      }
    } catch (_) {
      sw.stop();
      if (mounted) {
        setState(() {
          _probeLatencyMs = sw.elapsedMicroseconds / 1000.0;
          _isProbing = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _formatDate(DateTime dt) => _formatDateTime(dt);

  String _getExpirationLabel(AltrApiKey key) {
    if (key.expiresAt == null) {
      return 'Never expires';
    }
    final now = DateTime.now();
    final target = key.expiresAt!.toLocal();
    final formattedTarget = _formatDateTime(target);

    if (key.isExpired) {
      final pastDiff = now.difference(target);
      final pastSeconds = pastDiff.inSeconds;
      final pastMinutes = pastDiff.inMinutes;
      final pastHours = pastDiff.inHours;

      if (pastSeconds < 60) {
        return 'Expired just now ($formattedTarget)';
      } else if (pastMinutes < 60) {
        return 'Expired $pastMinutes min${pastMinutes == 1 ? '' : 's'} ago ($formattedTarget)';
      } else if (pastHours < 24) {
        final remMins = pastMinutes % 60;
        final remStr = remMins > 0 ? ' ${remMins}m' : '';
        return 'Expired $pastHours hr${pastHours == 1 ? '' : 's'}$remStr ago ($formattedTarget)';
      } else {
        return 'Expired on $formattedTarget';
      }
    }

    final diff = target.difference(now);
    final totalSeconds = diff.inSeconds;
    final totalMinutes = diff.inMinutes;
    final totalHours = diff.inHours;
    final days = diff.inDays;

    if (totalSeconds <= 0) {
      return 'Expired ($formattedTarget)';
    } else if (totalSeconds < 60) {
      return 'Expires in < 1 min ($formattedTarget)';
    } else if (totalMinutes < 60) {
      return 'Expires in $totalMinutes min${totalMinutes == 1 ? '' : 's'} ($formattedTarget)';
    } else if (totalHours < 24) {
      final remMinutes = totalMinutes % 60;
      final minsStr = remMinutes > 0 ? ' $remMinutes min${remMinutes == 1 ? '' : 's'}' : '';
      return 'Expires in $totalHours hr${totalHours == 1 ? '' : 's'}$minsStr ($formattedTarget)';
    } else {
      final remHours = totalHours % 24;
      final hrsStr = remHours > 0 ? ' $remHours hr${remHours == 1 ? '' : 's'}' : '';
      return 'Expires in $days day${days == 1 ? '' : 's'}$hrsStr ($formattedTarget)';
    }
  }

  Widget _buildKeyStatusBadge(AltrApiKey key, ColorScheme colorScheme) {
    final Color bg;
    final Color fg;
    final String label;

    if (!key.isActive) {
      bg = colorScheme.errorContainer.withValues(alpha: 0.5);
      fg = colorScheme.error;
      label = 'REVOKED';
    } else if (key.isExpired) {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade400;
      label = 'EXPIRED';
    } else if (key.expiresAt != null &&
        key.expiresAt!.toLocal().difference(DateTime.now()).inHours <= 24) {
      bg = Colors.amber.withValues(alpha: 0.15);
      fg = Colors.amber.shade700;
      label = 'EXPIRING SOON';
    } else {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade600;
      label = 'ACTIVE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildUserAvatar({
    required String displayName,
    String? photoUrl,
    double radius = 18,
    required ColorScheme colorScheme,
    bool isSelected = false,
  }) {
    final initial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'A';
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: isSelected
          ? colorScheme.primary
          : colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.75,
          color: isSelected
              ? colorScheme.onPrimary
              : colorScheme.onPrimaryContainer,
        ),
      ),
    );

    final url = photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return fallback;
    }

    final resolvedUrl = url.startsWith('http://')
        ? 'https://${url.substring(7)}'
        : url;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          resolvedUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return fallback;
          },
        ),
      ),
    );
  }

  Future<void> _launchExternalUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open documentation: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<_SettingsSearchEntry> get _searchResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _searchEntries.where((entry) {
      if (entry.title.toLowerCase().contains(query)) return true;
      if (entry.categoryName.toLowerCase().contains(query)) return true;
      return entry.keywords.any((k) => k.toLowerCase().contains(query));
    }).toList();
  }

  void _selectCategory(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      _highlightTarget = null;
    });
    if (categoryId == 'api_keys') {
      _apiKeyService.fetchKeys();
    }
  }

  void _selectSearchResult(_SettingsSearchEntry item) {
    setState(() {
      _selectedCategoryId = item.categoryId;
      _highlightTarget = item.title;
    });
    if (item.categoryId == 'api_keys') {
      _apiKeyService.fetchKeys();
    }
  }

  bool _isHighlighted(String text) {
    final query = _searchController.text.trim().toLowerCase();
    final target = _highlightTarget?.trim().toLowerCase();
    final lowerText = text.toLowerCase();

    if (target != null && target.isNotEmpty) {
      if (lowerText.contains(target) || target.contains(lowerText)) {
        return true;
      }
      final targetWords = target.split(RegExp(r'\s+')).where((w) => w.length > 2);
      for (final word in targetWords) {
        if (lowerText.contains(word)) return true;
      }
    }
    if (query.isNotEmpty && query.length >= 2) {
      if (lowerText.contains(query)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildHighlightedText({
    required String text,
    required TextStyle baseStyle,
    required ColorScheme colorScheme,
    TextAlign textAlign = TextAlign.start,
    TextOverflow overflow = TextOverflow.clip,
    int? maxLines,
  }) {
    final query = _searchController.text.trim();
    final target = _highlightTarget?.trim();

    String? highlightWord;
    if (query.isNotEmpty && query.length >= 2 && text.toLowerCase().contains(query.toLowerCase())) {
      highlightWord = query;
    } else if (target != null && target.isNotEmpty) {
      if (text.toLowerCase().contains(target.toLowerCase())) {
        highlightWord = target;
      } else {
        final words = target.split(RegExp(r'\s+')).where((w) => w.length > 2);
        for (final w in words) {
          if (text.toLowerCase().contains(w.toLowerCase())) {
            highlightWord = w;
            break;
          }
        }
      }
    }

    if (highlightWord == null || !text.toLowerCase().contains(highlightWord.toLowerCase())) {
      return Text(
        text,
        style: baseStyle,
        textAlign: textAlign,
        overflow: overflow,
        maxLines: maxLines,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerMatch = highlightWord.toLowerCase();
    final spans = <InlineSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerMatch, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + highlightWord.length),
          style: baseStyle.copyWith(
            backgroundColor: colorScheme.primary.withValues(alpha: 0.28),
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + highlightWord.length;
    }

    return RichText(
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Distinct surface hierarchy:
    // External left sidebar: surfaceContainer
    // Internal settings sidebar: surfaceContainerLow (lower than external sidebar)
    // Content area canvas: Transparent so outer canvas (surfaceContainerLowest) shows cleanly
    final sidebarBg = colorScheme.surfaceContainerLow;
    const contentBg = Colors.transparent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;

        if (!isWide) {
          // Narrow / compact fallback
          return Container(
            color: contentBg,
            child: SingleChildScrollView(
              controller: _contentScrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSidebarHeader(context),
                  const SizedBox(height: 16),
                  _buildActivePage(context),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          );
        }

        // Full macOS Two-Pane Split View
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Sidebar
            SizedBox(
              width: 280,
              child: Container(
                color: sidebarBg,
                child: Column(
                  children: [
                    // Top Search Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 14),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  )
                                : null,
                            hintText: 'Search',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),

                    // User Profile Card (hidden during search)
                    if (_searchController.text.isEmpty) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _selectCategory('profile'),
                        child: _buildSidebarHeader(context),
                      ),
                      const SizedBox(height: 4),
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // Sidebar Navigation Content: Categories OR Search Results
                    if (constraints.maxHeight.isFinite)
                      Expanded(
                        child: _searchController.text.isNotEmpty
                            ? _buildSearchResultsList(context)
                            : _buildCategoriesList(context),
                      )
                    else
                      _searchController.text.isNotEmpty
                          ? _buildSearchResultsList(context, shrinkWrap: true)
                          : _buildCategoriesList(context, shrinkWrap: true),
                  ],
                ),
              ),
            ),

            // Divider border between sidebar and content
            Container(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),

            // Right Dedicated Page View
            Expanded(
              child: Container(
                color: contentBg,
                child: constraints.maxHeight.isFinite
                    ? SingleChildScrollView(
                        controller: _contentScrollController,
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                        child: _buildActivePage(context),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                        child: _buildActivePage(context),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoriesList(BuildContext context, {bool shrinkWrap = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      children: _categories.map((cat) {
        final isSelected = _selectedCategoryId == cat.id;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _selectCategory(cat.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cat.iconBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: cat.icon,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        cat.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSearchResultsList(BuildContext context, {bool shrinkWrap = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _searchResults;

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 28,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text(
                'No Results Found',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No settings match "${_searchController.text.trim()}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        final isSelected = _selectedCategoryId == item.categoryId;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _selectSearchResult(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: item.iconBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: item.icon,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            item.categoryName,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivePage(BuildContext context) {
    switch (_selectedCategoryId) {
      case 'general':
        return _buildGeneralPage(context);
      case 'profile':
        return _buildProfilePage(context);
      case 'security':
        return _buildSecurityPage(context);
      case 'api_keys':
        return _buildApiKeysPage(context);
      case 'workspaces':
        return _buildWorkspacesPage(context);
      case 'telemetry':
        return _buildTelemetryPage(context);
      case 'network':
        return _buildNetworkPage(context);
      case 'docs':
        return _buildDocsPage(context);
      case 'appearance':
        return _buildAppearancePage(context);
      case 'feedback':
        return _buildFeedbackPage(context);
      case 'about':
        return _buildAboutNodePage(context);
      default:
        return _buildGeneralPage(context);
    }
  }

  Widget _buildSidebarHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveUser = widget.currentUser ?? AuthService().currentProfile;
    final displayName = effectiveUser?.displayName.isNotEmpty == true
        ? effectiveUser!.displayName
        : 'Santhosh Sivakumar';
    final email = effectiveUser?.email ?? 'Apple Account / Altr Stream';
    final isSelected = _selectedCategoryId == 'profile';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildUserAvatar(
            displayName: displayName,
            photoUrl: effectiveUser?.photoUrl,
            radius: 18,
            colorScheme: colorScheme,
            isSelected: isSelected,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<List<dynamic>> icon,
    required Color iconBg,
    Widget? trailing,
    Widget? badge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: HugeIcon(
                icon: icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildInsetGroup({
    required BuildContext context,
    required List<Widget> rows,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
    Widget? customWidget,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isHighlighted = _isHighlighted(label) || (customWidget == null && _isHighlighted(value));

    return Container(
      decoration: isHighlighted
          ? BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.35),
              border: Border(
                left: BorderSide(
                  color: colorScheme.primary,
                  width: 3.5,
                ),
              ),
            )
          : null,
      padding: EdgeInsets.only(
        left: isHighlighted ? 12.5 : 16,
        right: 16,
        top: 12,
        bottom: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: _buildHighlightedText(
              text: label,
              baseStyle: TextStyle(
                fontSize: 13,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                color: isHighlighted ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
              ),
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 12),
          if (customWidget != null)
            Flexible(child: customWidget)
          else
            Flexible(
              child: _buildHighlightedText(
                text: value,
                textAlign: TextAlign.right,
                baseStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: isMonospace ? 'monospace' : null,
                  color: isHighlighted ? colorScheme.primary : colorScheme.onSurface,
                ),
                colorScheme: colorScheme,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // 1. General Page
  Widget _buildGeneralPage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'General',
          subtitle: 'Manage your overall setup and preferences for Altr Stream node',
          icon: HugeIcons.strokeRoundedInformationCircle,
          iconBg: const Color(0xFF007AFF),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Node Name',
              'altr-stream-node-01',
              isMonospace: true,
            ),
            _buildRow(
              context,
              'Service Role',
              'Physical Source Abstraction & CDC Node',
            ),
            _buildRow(
              context,
              'Node Version',
              AppConfig.appVersion,
              isMonospace: true,
            ),
            _buildRow(
              context,
              'Ecosystem',
              'HelloAltr / Altr Mesh Federated Architecture',
            ),
            _buildRow(
              context,
              'Operational State',
              _healthInfo?['status'] ?? 'Healthy',
              customWidget: StatusBadge(
                status: _healthInfo?['status'] ?? 'ACTIVE',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 2. Profile & Account Page
  Widget _buildProfilePage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveUser = widget.currentUser ?? AuthService().currentProfile;
    final displayName = effectiveUser?.displayName.isNotEmpty == true
        ? effectiveUser!.displayName
        : 'Santhosh Sivakumar';
    final email = effectiveUser?.email ?? 'admin@localhost';
    final userId = effectiveUser?.id ?? 'usr_local_admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Profile & Account',
          subtitle: 'Account identity, active workspace, and session controls',
          icon: HugeIcons.strokeRoundedUser,
          iconBg: const Color(0xFF5856D6),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              _buildUserAvatar(
                displayName: displayName,
                photoUrl: effectiveUser?.photoUrl,
                radius: 28,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            effectiveUser?.provider == 'google.com'
                                ? 'Google Account'
                                : 'Admin Profile',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Display Name',
              displayName,
            ),
            _buildRow(
              context,
              'Email Address',
              email,
            ),
            _buildRow(
              context,
              'User ID',
              userId,
              isMonospace: true,
              customWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userId,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 14,
                    ),
                    tooltip: 'Copy User ID',
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _copyToClipboard(userId, 'User ID'),
                  ),
                ],
              ),
            ),
            _buildRow(
              context,
              'Active Workspace',
              widget.activeWorkspaceName ?? 'Default Workspace',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Danger Zone',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        _buildInsetGroup(
          context: context,
          rows: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Log Out of Altr Account',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Terminates any active Sudo session and signs out locally',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  M3EButton(
                    style: M3EButtonStyle.filled,
                    decoration: M3EButtonDecoration(
                      backgroundColor: WidgetStatePropertyAll(colorScheme.error),
                      foregroundColor: WidgetStatePropertyAll(colorScheme.onError),
                    ),
                    onPressed: () async {
                      final confirmed = await AltrAlert.show(
                        context,
                        title: 'Log Out of Altr Account?',
                        message:
                            'Are you sure you want to log out? Any active Sudo session will be terminated immediately.',
                        cancelLabel: 'Cancel',
                        confirmLabel: 'Log Out',
                        isDestructive: true,
                      );
                      if (confirmed == true) {
                        AuthService().signOut();
                      }
                    },
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delete Account',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Permanently delete account credentials and data',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  M3EButton(
                    style: M3EButtonStyle.text,
                    onPressed: () async {
                      final confirmed = await AltrAlert.show(
                        context,
                        title: 'Delete Account',
                        message:
                            'Are you sure you want to delete your account? This action cannot be undone.',
                        cancelLabel: 'Cancel',
                        confirmLabel: 'Delete',
                        isDestructive: true,
                      );
                      if (confirmed == true) {
                        AuthService().signOut();
                      }
                    },
                    child: Text('Delete', style: TextStyle(color: colorScheme.error)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. Security & Passcode Page
  Widget _buildSecurityPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveUser = widget.currentUser ?? AuthService().currentProfile;
    final isPasscodeConfigured = PasscodeService().hasConfiguredPasscode(effectiveUser) ||
        (effectiveUser?.hasPasscode ?? false);
    final configuredType = PasscodeService().getCredentialType(effectiveUser?.id) ??
        effectiveUser?.passcodeType ??
        'pin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Security & Passcode',
          subtitle: 'Zero-knowledge verification, passcode protection, and sudo elevation grace period',
          icon: HugeIcons.strokeRoundedShieldCheck,
          iconBg: const Color(0xFFFF9500),
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Altr Mesh Auth',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Active Workspace',
              widget.activeWorkspaceName ?? 'Default Workspace',
              customWidget: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    widget.activeWorkspaceName ?? 'Default Workspace',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (widget.onWorkspacesTap != null)
                    OutlinedButton.icon(
                      onPressed: widget.onWorkspacesTap,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedGrid,
                        size: 13,
                      ),
                      label: const Text('Workspaces', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                    ),
                ],
              ),
            ),
            _buildRow(
              context,
              'Altr Passcode Protection',
              isPasscodeConfigured
                  ? 'Configured (${configuredType.toUpperCase()})'
                  : 'Not Set',
              customWidget: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPasscodeConfigured
                          ? colorScheme.primaryContainer
                          : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isPasscodeConfigured
                          ? 'PROTECTED (${configuredType.toUpperCase()})'
                          : 'UNCONFIGURED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPasscodeConfigured
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (widget.onPasscodeTap != null)
                    OutlinedButton.icon(
                      onPressed: widget.onPasscodeTap,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLockPassword,
                        size: 13,
                      ),
                      label: Text(
                        isPasscodeConfigured ? 'Change' : 'Set Up',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. API Keys & Access Page
  Widget _buildApiKeysPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final keys = _apiKeyService.keys;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'API Keys & Access',
          subtitle: 'Manage authentication tokens for programmatic access to Altr Stream',
          icon: HugeIcons.strokeRoundedKey01,
          iconBg: const Color(0xFFFF2D55),
          trailing: ElevatedButton.icon(
            onPressed: _openGenerateKeyModal,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedPlusSign,
              size: 14,
            ),
            label: const Text('Generate New Key'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),

        // Just Created One-Time Key Banner
        if (_justCreatedKey != null && _justCreatedKey!.fullKey != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Copy your new API Key now. It will never be shown again!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _justCreatedKey = null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _justCreatedKey!.fullKey!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () => _copyToClipboard(_justCreatedKey!.fullKey!, 'API Key'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        if (keys.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Column(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedKey01,
                    size: 36,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Active API Keys',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Generate an API key to access AltrQL queries and streaming endpoints programmatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  M3EButton(
                    style: M3EButtonStyle.filled,
                    onPressed: _openGenerateKeyModal,
                    child: const Text('Generate New Key'),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          _buildInsetGroup(
            context: context,
            rows: keys.map((key) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedKey01,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                key.name,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              _buildKeyStatusBadge(key, colorScheme),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${key.keyPrefix}... • Scopes: ${key.scopes.join(", ").toUpperCase()}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedCalendar03,
                                    size: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Created: ${_formatDate(key.createdAt)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedClock01,
                                    size: 12,
                                    color: key.isExpired
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getExpirationLabel(key),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: key.isExpired
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: key.isExpired
                                          ? colorScheme.error
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedDelete02,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      tooltip: 'Revoke Key',
                      onPressed: () => _revokeKey(key),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _openGenerateKeyModal() async {
    final effectiveUser = widget.currentUser ?? AuthService().currentProfile;
    final sudoOk = await SudoVerificationDialog.ensureSudoActive(
      context,
      profile: effectiveUser,
      actionDescription: 'generate new API keys',
    );
    if (!sudoOk || !mounted) return;

    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final List<String> selectedScopes = ['read', 'write'];
    int? expiresInDays = 30;
    int? expiresInHours;
    bool isCustomExpiration = false;
    DateTime? customExpiresAt;

    final created = await showDialog<AltrApiKey?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Generate New API Key'),
            content: SizedBox(
              width: 400,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Key label is required';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Key Label / Integration Name',
                        hintText: 'e.g. CLI Sync Pipeline',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Permission Scopes:', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['read', 'write', 'admin'].map((scope) {
                        final isSelected = selectedScopes.contains(scope);
                        return FilterChip(
                          label: Text(scope.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                selectedScopes.add(scope);
                              } else {
                                selectedScopes.remove(scope);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('Expiration:', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: isCustomExpiration
                          ? 'custom'
                          : (expiresInHours != null
                              ? '${expiresInHours}h'
                              : (expiresInDays == null ? 'never' : '${expiresInDays}d')),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: '1h', child: Text('1 Hour')),
                        DropdownMenuItem(value: '8h', child: Text('8 Hours')),
                        DropdownMenuItem(value: '24h', child: Text('24 Hours (1 Day)')),
                        DropdownMenuItem(value: '7d', child: Text('7 Days')),
                        DropdownMenuItem(value: '30d', child: Text('30 Days')),
                        DropdownMenuItem(value: '90d', child: Text('90 Days')),
                        DropdownMenuItem(value: 'never', child: Text('Never (Permanent)')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom Date & Time...')),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          if (val == 'custom') {
                            isCustomExpiration = true;
                            expiresInDays = null;
                            expiresInHours = null;
                            customExpiresAt ??= DateTime.now().add(const Duration(days: 14));
                          } else if (val == 'never') {
                            isCustomExpiration = false;
                            expiresInDays = null;
                            expiresInHours = null;
                          } else if (val == '1h') {
                            isCustomExpiration = false;
                            expiresInDays = null;
                            expiresInHours = 1;
                          } else if (val == '8h') {
                            isCustomExpiration = false;
                            expiresInDays = null;
                            expiresInHours = 8;
                          } else if (val == '24h') {
                            isCustomExpiration = false;
                            expiresInDays = null;
                            expiresInHours = 24;
                          } else if (val == '7d') {
                            isCustomExpiration = false;
                            expiresInDays = 7;
                            expiresInHours = null;
                          } else if (val == '30d') {
                            isCustomExpiration = false;
                            expiresInDays = 30;
                            expiresInHours = null;
                          } else if (val == '90d') {
                            isCustomExpiration = false;
                            expiresInDays = 90;
                            expiresInHours = null;
                          }
                        });
                      },
                    ),
                    if (isCustomExpiration) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final now = DateTime.now();
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: customExpiresAt ?? now.add(const Duration(days: 7)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (pickedDate == null || !context.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(customExpiresAt ?? now),
                          );
                          final finalTime = pickedTime ?? const TimeOfDay(hour: 23, minute: 59);
                          setModalState(() {
                            customExpiresAt = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              finalTime.hour,
                              finalTime.minute,
                            );
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surfaceContainerLow,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customExpiresAt != null
                                      ? _formatDateTime(customExpiresAt!)
                                      : 'Select Expiration Date & Time',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Icon(Icons.edit_calendar_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              M3EButton(
                style: M3EButtonStyle.text,
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              M3EButton(
                style: M3EButtonStyle.filled,
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }
                  final name = nameController.text.trim();

                  final key = await _apiKeyService.createKey(
                    name: name,
                    scopes: selectedScopes,
                    expiresInDays: isCustomExpiration ? null : expiresInDays,
                    expiresInHours: isCustomExpiration ? null : expiresInHours,
                    expiresAt: isCustomExpiration ? customExpiresAt : null,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop(key);
                },
                child: const Text('Generate Key'),
              ),
            ],
          );
        },
      ),
    );

    if (created != null && mounted) {
      setState(() {
        _justCreatedKey = created;
      });
      await _apiKeyService.fetchKeys();
    }
  }

  Future<void> _revokeKey(AltrApiKey key) async {
    final effectiveUser = widget.currentUser ?? AuthService().currentProfile;
    final sudoOk = await SudoVerificationDialog.ensureSudoActive(
      context,
      profile: effectiveUser,
      actionDescription: 'revoke API key "${key.name}"',
    );
    if (!sudoOk || !mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await AltrAlert.show(
      context,
      title: 'Revoke API Key?',
      message:
          'Are you sure you want to permanently revoke "${key.name}" (${key.keyPrefix}...)? Any clients using this key will immediately lose access.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Revoke',
      isDestructive: true,
    );

    if (confirmed == true) {
      await _apiKeyService.revokeKey(key.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API Key "${key.name}" revoked.'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  // 5. Workspaces Page
  Widget _buildWorkspacesPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final workspaces = _workspaceService.workspaces;
    final active = _workspaceService.activeWorkspace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Workspaces',
          subtitle: 'Multi-tenant workspace isolation, team collaboration, and resource scoping',
          icon: HugeIcons.strokeRoundedFolder02,
          iconBg: const Color(0xFFAF52DE),
          trailing: widget.onWorkspacesTap != null
              ? ElevatedButton.icon(
                  onPressed: widget.onWorkspacesTap,
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedGrid,
                    size: 14,
                  ),
                  label: const Text('Manage Workspaces'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                )
              : null,
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Active Workspace',
              active?.name ?? widget.activeWorkspaceName ?? 'Default Workspace',
              customWidget: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active?.name ?? widget.activeWorkspaceName ?? 'Default Workspace',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            _buildRow(
              context,
              'Total Workspaces Available',
              workspaces.isNotEmpty ? '${workspaces.length} Workspaces' : '1 Workspace',
            ),
          ],
        ),
      ],
    );
  }

  // 6. Network Page
  Widget _buildNetworkPage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Network & Host',
          subtitle: 'Endpoints, reverse proxy configurations, and probe latency',
          icon: HugeIcons.strokeRoundedWifi01,
          iconBg: const Color(0xFF30B0C7),
          trailing: OutlinedButton.icon(
            onPressed: _probeBackend,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 14,
            ),
            label: const Text('Ping Host'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'API Base URL',
              AppConfig.apiBaseUrl,
              isMonospace: true,
            ),
            _buildRow(
              context,
              'Protocol & Engine',
              'FastAPI / Starlette ASGI Engine (HTTP/1.1 & WebSocket)',
            ),
            _buildRow(
              context,
              'Reverse Proxy / TLS',
              'Internal Mesh Gateway (Reverse Proxy Ready)',
            ),
            if (_probeLatencyMs != null)
              _buildRow(
                context,
                'Probe Latency',
                '${_probeLatencyMs!.toStringAsFixed(1)} ms',
                isMonospace: true,
              ),
          ],
        ),
      ],
    );
  }

  // 7. Docs Page
  Widget _buildDocsPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'API Documentation',
          subtitle: 'Live OpenAPI Swagger schema interface generated directly by FastAPI backend',
          icon: HugeIcons.strokeRoundedBook02,
          iconBg: const Color(0xFFFF5E3A),
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'OpenAPI / Swagger',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          trailing: ElevatedButton.icon(
            onPressed: () => _launchExternalUrl(AppConfig.apiDocsUrl),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedShare01,
              size: 14,
            ),
            label: const Text('Open Swagger UI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Swagger UI Endpoint',
              AppConfig.apiDocsUrl,
              isMonospace: true,
              customWidget: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText(
                    AppConfig.apiDocsUrl,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 14,
                    ),
                    tooltip: 'Copy Swagger UI URL',
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _copyToClipboard(AppConfig.apiDocsUrl, 'Swagger UI URL'),
                  ),
                ],
              ),
            ),
            _buildRow(
              context,
              'OpenAPI Specification (JSON)',
              AppConfig.openApiJsonUrl,
              isMonospace: true,
              customWidget: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText(
                    AppConfig.openApiJsonUrl,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 14,
                    ),
                    tooltip: 'Copy OpenAPI JSON URL',
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _copyToClipboard(AppConfig.openApiJsonUrl, 'OpenAPI JSON URL'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () => _launchExternalUrl(AppConfig.openApiJsonUrl),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCodeCircle,
                      size: 13,
                    ),
                    label: const Text('View JSON', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 8. Appearance Page
  Widget _buildAppearancePage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Theme & Appearance',
          subtitle: 'Select system preference, light mode, or dark mode display styling',
          icon: HugeIcons.strokeRoundedPaintBoard,
          iconBg: const Color(0xFF32ADE6),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Color Theme Mode',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Toggle interface between light, dark, or system preference',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedSettings02,
                          size: 16,
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedSun01,
                          size: 16,
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedMoon02,
                          size: 16,
                        ),
                      ),
                    ],
                    selected: {widget.themeMode},
                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                      if (widget.onThemeModeChanged != null && newSelection.isNotEmpty) {
                        widget.onThemeModeChanged!(newSelection.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 9. Feedback Page
  Widget _buildFeedbackPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Help & Feedback',
          subtitle: 'Share impressions, report defects, or propose enhancements directly to engineering',
          icon: HugeIcons.strokeRoundedMessageQuestion,
          iconBg: const Color(0xFF34C759),
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Beta',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          trailing: ElevatedButton.icon(
            key: const ValueKey('settings_send_feedback_button'),
            onPressed: () => FeedbackDialog.show(
              context,
              apiClient: widget.apiClient,
            ),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedMessageQuestion,
              size: 14,
            ),
            label: const Text('Send Feedback'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Channel',
              'Beta Feedback Program',
            ),
            _buildRow(
              context,
              'Telemetry & Trace ID',
              'Enabled (Local anonymized crash metrics)',
            ),
          ],
        ),
      ],
    );
  }

  // 10. Node Telemetry Page
  Widget _buildTelemetryPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = widget.nodeStatus;
    final latency = _probeLatencyMs != null
        ? '${_probeLatencyMs!.toStringAsFixed(1)} ms'
        : 'Probing...';
    final uptime = _healthInfo?['uptime']?.toString() ?? 'Active & Operational';
    final engine = _healthInfo?['engine']?.toString() ?? 'uvicorn / python-asyncio';
    final memory = _healthInfo?['memory_mb'] != null
        ? '${_healthInfo!['memory_mb']} MB'
        : (_healthInfo?['memory'] != null ? '${_healthInfo!['memory']} MB' : 'Nominal');
    final healthState = _healthInfo?['status']?.toString().toUpperCase() ?? 'HEALTHY';
    final clusterRole = _healthInfo?['role']?.toString().toUpperCase() ?? 'STANDALONE LEADER';
    final lastProbed = _healthInfo?['timestamp'] != null
        ? _healthInfo!['timestamp'].toString()
        : 'Just now';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'Node Telemetry',
          subtitle: 'Real-time performance vitals, health status, and live diagnostics',
          icon: HugeIcons.strokeRoundedActivity01,
          iconBg: const Color(0xFF34C759),
          badge: StatusBadge(status: status),
          trailing: ElevatedButton.icon(
            onPressed: _isProbing ? null : _probeBackend,
            icon: _isProbing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const HugeIcon(
                    icon: HugeIcons.strokeRoundedFlash,
                    size: 14,
                  ),
            label: Text(_isProbing ? 'Probing Node...' : 'Probe Node'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Operational Status',
              status,
              customWidget: StatusBadge(status: status),
            ),
            _buildRow(
              context,
              'Probe Latency',
              latency,
              isMonospace: true,
            ),
            _buildRow(
              context,
              'Node Health State',
              healthState,
            ),
            _buildRow(
              context,
              'Engine Runtime',
              engine,
            ),
            _buildRow(
              context,
              'Cluster Role',
              clusterRole,
            ),
            _buildRow(
              context,
              'Process Uptime',
              uptime,
            ),
            _buildRow(
              context,
              'Memory Consumption',
              memory,
            ),
            _buildRow(
              context,
              'Last Probed Timestamp',
              lastProbed,
              isMonospace: true,
            ),
            _buildRow(
              context,
              'API Base URL',
              AppConfig.apiBaseUrl,
              isMonospace: true,
            ),
          ],
        ),
      ],
    );
  }

  // 11. About Node Page
  Widget _buildAboutNodePage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context: context,
          title: 'About Node',
          subtitle: 'System metadata, node version, build release, and licensing',
          icon: HugeIcons.strokeRoundedInformationCircle,
          iconBg: const Color(0xFF8E8E93),
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'v${AppConfig.appVersion}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        _buildInsetGroup(
          context: context,
          rows: [
            _buildRow(
              context,
              'Product Name',
              'Altr Stream Distributed CDC',
            ),
            _buildRow(
              context,
              'Node Version',
              AppConfig.appVersion,
              isMonospace: true,
            ),
            _buildRow(
              context,
              'Engine Architecture',
              'FastAPI / Python 3.12 / WebSockets',
            ),
            _buildRow(
              context,
              'Ecosystem',
              'Altr Mesh Cloud-Native Real-Time Sync',
            ),
            _buildRow(
              context,
              'License',
              'Apache 2.0 / Proprietary Hybrid',
            ),
            _buildRow(
              context,
              'Interactive Documentation',
              AppConfig.apiDocsUrl,
              customWidget: OutlinedButton.icon(
                onPressed: () => _launchExternalUrl(AppConfig.apiDocsUrl),
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedShare01,
                  size: 13,
                ),
                label: const Text('Open Swagger UI', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
