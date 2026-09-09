// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models.dart';
import '../../../core/theme/app_theme.dart';

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
  final _filePathController = TextEditingController(text: '/app/data/manual_test.db');
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
    _filePathController.dispose();
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
      final ConnectionTestResultModel res;
      if (_selectedType == 'SQLITE') {
        res = await widget.apiClient.testAdhocConnection(
          type: _selectedType,
          filePath: _filePathController.text.trim(),
        );
      } else {
        res = await widget.apiClient.testAdhocConnection(
          type: _selectedType,
          host: _hostController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 5432,
          databaseName: _databaseController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
      }
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
      final SourceModel source;
      if (_selectedType == 'SQLITE') {
        source = await widget.apiClient.createSource(
          name: _nameController.text.trim(),
          type: _selectedType,
          filePath: _filePathController.text.trim(),
          testConnectionFirst: false,
        );
      } else {
        source = await widget.apiClient.createSource(
          name: _nameController.text.trim(),
          type: _selectedType,
          host: _hostController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 5432,
          databaseName: _databaseController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          testConnectionFirst: false,
        );
      }

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
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                      Text(
                        'Add Data Source',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getStepSubtitle(),
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Step Progress Indicator
              _buildStepIndicator(context),
              const SizedBox(height: 24),

              // Step Content
              if (_currentStep == 0) _buildStep1ChooseType(context),
              if (_currentStep == 1) _buildStep2Configure(context),
              if (_currentStep == 2) _buildStep3Test(context),
              if (_currentStep == 3) _buildStep4Review(context),
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

  Widget _buildStepIndicator(BuildContext context) {
    return Row(
      children: [
        _buildStepPill(context, 0, '1. Type'),
        _buildStepLine(context, 0),
        _buildStepPill(context, 1, '2. Configure'),
        _buildStepLine(context, 1),
        _buildStepPill(context, 2, '3. Test'),
        _buildStepLine(context, 2),
        _buildStepPill(context, 3, '4. Register'),
      ],
    );
  }

  Widget _buildStepPill(BuildContext context, int stepIndex, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);
    final isDone = _currentStep > stepIndex;
    final isCurrent = _currentStep == stepIndex;

    Color bg = colorScheme.surfaceContainer;
    Color fg = colorScheme.onSurfaceVariant;
    BorderSide border = BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5));

    if (isCurrent) {
      bg = colorScheme.primaryContainer;
      fg = colorScheme.onPrimaryContainer;
      border = BorderSide(color: colorScheme.primary);
    } else if (isDone) {
      bg = statusActiveColor.withValues(alpha: 0.15);
      fg = statusActiveColor;
      border = BorderSide(color: statusActiveColor);
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

  Widget _buildStepLine(BuildContext context, int afterStep) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);
    final isPast = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 1,
        color: isPast ? statusActiveColor : colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }

  // --- STEP 1: CHOOSE TYPE ---
  Widget _buildStep1ChooseType(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What type of database would you like to connect?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 16),
        _buildConnectorOption(
          context: context,
          type: 'POSTGRESQL',
          title: 'PostgreSQL',
          description: 'Supported connector with native introspection, SSL, and schema discovery.',
          icon: Icons.storage,
          isSupported: true,
        ),
        const SizedBox(height: 12),
        _buildConnectorOption(
          context: context,
          type: 'SQLITE',
          title: 'SQLite',
          description: 'Supported file-based database connector with direct file introspection.',
          icon: Icons.insert_drive_file_outlined,
          isSupported: true,
        ),
        const SizedBox(height: 12),
        _buildConnectorOption(
          context: context,
          type: 'MYSQL',
          title: 'MySQL',
          description: 'Planned milestone connector for relational tables.',
          icon: Icons.storage_outlined,
          isSupported: false,
        ),
        const SizedBox(height: 12),
        _buildConnectorOption(
          context: context,
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
                  _nameController.text = _selectedType == 'SQLITE' ? 'Manual SQLite Test' : 'Production-Postgres';
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
    required BuildContext context,
    required String type,
    required String title,
    required String description,
    required IconData icon,
    required bool isSupported,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: isSupported ? () => setState(() => _selectedType = type) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.5) : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSupported ? (isSelected ? colorScheme.primary : colorScheme.onSurface) : colorScheme.onSurfaceVariant,
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
                          color: isSupported ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isSupported)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.getStatusColor('DISCOVERING', context).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Future Milestone',
                            style: TextStyle(fontSize: 10, color: AppTheme.getStatusColor('DISCOVERING', context)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isSupported)
              Radio<String>(
                value: type,
                groupValue: _selectedType,
                activeColor: colorScheme.primary,
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
  Widget _buildStep2Configure(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Source Name *',
              hintText: _selectedType == 'SQLITE' ? 'e.g. Manual SQLite Test' : 'e.g. College ERP Database',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a source name' : null,
          ),
          const SizedBox(height: 16),
          if (_selectedType == 'SQLITE') ...[
            TextFormField(
              controller: _filePathController,
              decoration: const InputDecoration(
                labelText: 'Database File Path *',
                hintText: 'e.g. /app/data/manual_test.db',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Database file path is required' : null,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Provide the absolute path to the SQLite file accessible by the Altr Stream node.\nFor Docker environments, use container paths like /app/data/manual_test.db.',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
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
                          color: colorScheme.onSurfaceVariant,
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
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAdvanced ? 'Hide Advanced Configuration' : 'Show Advanced Configuration',
                    style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'SSL Mode: Prefer • Connection Pool: 5 • Connection Timeout: 10s\n(Defaults automatically managed by Altr Stream driver)',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
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
  Widget _buildStep3Test(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusActiveColor = AppTheme.getStatusColor('ACTIVE', context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isTesting) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Validating physical connection...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedType == 'SQLITE'
                      ? 'Verifying SQLite database file access and readability'
                      : 'Pinging database host and verifying credentials',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ] else if (_testResult != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _testResult!.success ? statusActiveColor.withValues(alpha: 0.12) : colorScheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testResult!.success ? statusActiveColor : colorScheme.error,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _testResult!.success ? Icons.check_circle : Icons.error,
                      color: _testResult!.success ? statusActiveColor : colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _testResult!.success ? '✓ Successfully Connected' : 'Connection Failed',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _testResult!.success ? statusActiveColor : colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _testResult!.message,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
                if (_testResult!.serverVersion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Server Version: ${_testResult!.serverVersion}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
                if (_testResult!.latencyMs != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Latency: ${_testResult!.latencyMs!.toStringAsFixed(1)} ms',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
                if (_testResult!.errorDetails != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _testResult!.errorDetails!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: colorScheme.error,
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
  Widget _buildStep4Review(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review Source Registration',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              _buildReviewRow(context, 'Source Name', _nameController.text.trim()),
              _buildReviewDivider(context),
              _buildReviewRow(context, 'Database Type', _selectedType),
              _buildReviewDivider(context),
              if (_selectedType == 'SQLITE') ...[
                _buildReviewRow(context, 'Database File Path', _filePathController.text.trim()),
              ] else ...[
                _buildReviewRow(context, 'Connection Endpoint', '${_hostController.text.trim()}:${_portController.text.trim()}'),
                _buildReviewDivider(context),
                _buildReviewRow(context, 'Database Name', _databaseController.text.trim()),
                _buildReviewDivider(context),
                _buildReviewRow(context, 'Username', _usernameController.text.trim()),
              ],
            ],
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.error),
            ),
            child: Text(
              'Registration Error: $_saveError',
              style: TextStyle(color: colorScheme.error, fontSize: 12),
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
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                    )
                  : const Icon(Icons.check, size: 16),
              label: Text(_isSaving ? 'Registering...' : 'Register Source'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildReviewDivider(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(height: 16, color: colorScheme.outlineVariant.withValues(alpha: 0.5));
  }
}
