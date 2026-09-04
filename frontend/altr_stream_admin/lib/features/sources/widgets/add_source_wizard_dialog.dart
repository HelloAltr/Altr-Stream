import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/status_badge.dart';

class AddSourceWizardDialog extends StatefulWidget {
  final ApiClient apiClient;
  final Function(SourceModel newSource) onSourceCreated;

  const AddSourceWizardDialog({
    super.key,
    required this.apiClient,
    required this.onSourceCreated,
  });

  @override
  State<AddSourceWizardDialog> createState() => _AddSourceWizardDialogState();
}

class _AddSourceWizardDialogState extends State<AddSourceWizardDialog> {
  int _currentStep = 0; // 0: Choose Type, 1: Configure, 2: Test, 3: Register
  final _formKey = GlobalKey<FormState>();

  String _selectedType = 'POSTGRESQL';
  final _nameController = TextEditingController();
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '5432');
  final _databaseController = TextEditingController(text: 'altr_test_db');
  final _usernameController = TextEditingController(text: 'altr_user');
  final _passwordController = TextEditingController(text: 'altr_secure_pass');
  bool _obscurePassword = true;
  bool _showAdvanced = false;

  bool _isTesting = false;
  bool _isSaving = false;
  ConnectionTestResultModel? _testResult;
  String? _saveError;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _runConnectionTest() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _saveError = null;
    });

    try {
      final res = await widget.apiClient.testAdhocConnection(
        type: _selectedType,
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 5432,
        databaseName: _databaseController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        setState(() {
          _testResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = ConnectionTestResultModel(
            success: false,
            message: 'Unable to reach database server',
            errorDetails: e.toString(),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _registerSource() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final source = await widget.apiClient.createSource(
        name: _nameController.text.trim(),
        type: _selectedType,
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 5432,
        databaseName: _databaseController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        testConnectionFirst: false,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSourceCreated(source);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderColor),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Data Source',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getStepSubtitle(),
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Step Progress Indicator
              _buildStepIndicator(),
              const SizedBox(height: 24),

              // Step Content
              if (_currentStep == 0) _buildStep1ChooseType(),
              if (_currentStep == 1) _buildStep2Configure(),
              if (_currentStep == 2) _buildStep3Test(),
              if (_currentStep == 3) _buildStep4Review(),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepSubtitle() {
    switch (_currentStep) {
      case 0:
        return 'Step 1 of 4: Choose database connector';
      case 1:
        return 'Step 2 of 4: Configure connection parameters';
      case 2:
        return 'Step 3 of 4: Validate database reachability';
      case 3:
        return 'Step 4 of 4: Review and register source';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepPill(0, '1. Type'),
        _buildStepLine(0),
        _buildStepPill(1, '2. Configure'),
        _buildStepLine(1),
        _buildStepPill(2, '3. Test'),
        _buildStepLine(2),
        _buildStepPill(3, '4. Register'),
      ],
    );
  }

  Widget _buildStepPill(int stepIndex, String label) {
    final isDone = _currentStep > stepIndex;
    final isCurrent = _currentStep == stepIndex;

    Color bg = AppTheme.bgPrimary;
    Color fg = AppTheme.textMuted;
    BorderSide border = const BorderSide(color: AppTheme.borderColor);

    if (isCurrent) {
      bg = AppTheme.accentCyanSubtle;
      fg = AppTheme.accentCyan;
      border = const BorderSide(color: AppTheme.accentCyan);
    } else if (isDone) {
      bg = AppTheme.successBg;
      fg = AppTheme.success;
      border = const BorderSide(color: AppTheme.success);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.fromBorderSide(border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: isCurrent || isDone ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildStepLine(int afterStep) {
    final isPast = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 1,
        color: isPast ? AppTheme.success : AppTheme.borderColor,
      ),
    );
  }

  // --- STEP 1: CHOOSE TYPE ---
  Widget _buildStep1ChooseType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What type of database would you like to connect?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 16),
        _buildConnectorOption(
          type: 'POSTGRESQL',
          title: 'PostgreSQL',
          description: 'Supported connector with native introspection, SSL, and schema discovery.',
          icon: Icons.storage,
          isSupported: true,
        ),
        const SizedBox(height: 12),
        _buildConnectorOption(
          type: 'MYSQL',
          title: 'MySQL',
          description: 'Planned milestone connector for relational tables.',
          icon: Icons.storage_outlined,
          isSupported: false,
        ),
        const SizedBox(height: 12),
        _buildConnectorOption(
          type: 'MONGODB',
          title: 'MongoDB',
          description: 'Planned document connector for collection introspection.',
          icon: Icons.folder_open,
          isSupported: false,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isEmpty) {
                  _nameController.text = 'Production-Postgres';
                }
                setState(() => _currentStep = 1);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Continue'),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 14),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConnectorOption({
    required String type,
    required String title,
    required String description,
    required IconData icon,
    required bool isSupported,
  }) {
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: isSupported ? () => setState(() => _selectedType = type) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentCyanSubtle : AppTheme.bgPrimary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentCyan : AppTheme.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSupported ? (isSelected ? AppTheme.accentCyan : AppTheme.textPrimary) : AppTheme.textMuted,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSupported ? AppTheme.textPrimary : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isSupported)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.warningBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Future Milestone', style: TextStyle(fontSize: 10, color: AppTheme.warning)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSupported)
              Radio<String>(
                value: type,
                groupValue: _selectedType,
                activeColor: AppTheme.accentCyan,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedType = val);
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- STEP 2: CONFIGURE ---
  Widget _buildStep2Configure() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Source Name *',
              hintText: 'e.g. College ERP Database',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a source name' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Host / IP *',
                    hintText: 'e.g. localhost or postgres-test',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Host is required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(labelText: 'Port *'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null || int.tryParse(v.trim()) == null) ? 'Port required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _databaseController,
            decoration: const InputDecoration(
              labelText: 'Database Name *',
              hintText: 'e.g. college_erp',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Database name is required' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Username required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Password required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.accentCyan,
                ),
                const SizedBox(width: 4),
                Text(
                  _showAdvanced ? 'Hide Advanced Configuration' : 'Show Advanced Configuration',
                  style: const TextStyle(fontSize: 12, color: AppTheme.accentCyan, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgPrimary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: const Text(
                'SSL Mode: Prefer • Connection Pool: 5 • Connection Timeout: 10s\n(Defaults automatically managed by Altr Stream driver)',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('Back'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    setState(() => _currentStep = 2);
                    _runConnectionTest();
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Continue to Test'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- STEP 3: TEST ---
  Widget _buildStep3Test() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isTesting) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: const Column(
              children: [
                CircularProgressIndicator(color: AppTheme.accentCyan),
                SizedBox(height: 16),
                Text(
                  'Validating physical connection...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 4),
                Text(
                  'Pinging database host and verifying credentials',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ] else if (_testResult != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _testResult!.success ? AppTheme.successBg : AppTheme.errorBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testResult!.success ? AppTheme.success : AppTheme.error,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _testResult!.success ? Icons.check_circle : Icons.error,
                      color: _testResult!.success ? AppTheme.success : AppTheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _testResult!.success ? '✓ Successfully Connected' : 'Connection Failed',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _testResult!.success ? AppTheme.success : AppTheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _testResult!.message,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                ),
                if (_testResult!.serverVersion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Server Version: ${_testResult!.serverVersion}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                if (_testResult!.latencyMs != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Latency: ${_testResult!.latencyMs!.toStringAsFixed(1)} ms',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                if (_testResult!.errorDetails != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _testResult!.errorDetails!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 1),
              child: const Text('Edit Connection'),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _runConnectionTest,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Retry Test'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: (_testResult != null && _testResult!.success)
                      ? () => setState(() => _currentStep = 3)
                      : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Continue'),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- STEP 4: REVIEW & REGISTER ---
  Widget _buildStep4Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review Source Registration',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgPrimary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            children: [
              _buildReviewRow('Source Name', _nameController.text.trim()),
              const Divider(height: 16, color: AppTheme.borderColor),
              _buildReviewRow('Database Type', _selectedType),
              const Divider(height: 16, color: AppTheme.borderColor),
              _buildReviewRow('Connection Endpoint', '${_hostController.text.trim()}:${_portController.text.trim()}'),
              const Divider(height: 16, color: AppTheme.borderColor),
              _buildReviewRow('Database Name', _databaseController.text.trim()),
              const Divider(height: 16, color: AppTheme.borderColor),
              _buildReviewRow('Username', _usernameController.text.trim()),
            ],
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.error),
            ),
            child: Text(
              'Registration Error: $_saveError',
              style: const TextStyle(color: AppTheme.error, fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('Back'),
            ),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _registerSource,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(_isSaving ? 'Registering...' : 'Register Source'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
      ],
    );
  }
}
