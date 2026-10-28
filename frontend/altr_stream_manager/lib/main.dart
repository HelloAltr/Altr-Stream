import 'package:flutter/material.dart';

import 'screens/manager_screen.dart';
import 'themes/theme.dart';
import 'themes/util.dart';

// Re-export modular components, dialogs, widgets, and services for backward compatibility
export 'config/constants.dart' show kDialogStandardWidth;
export 'dialogs/diagnose_and_fix_dialog.dart';
export 'dialogs/technical_logs_dialog.dart';
export 'screens/manager_screen.dart';
export 'services/backend_init.dart';
export 'widgets/altr_button.dart';
export 'widgets/middle_truncated_path_text.dart';
export 'widgets/table_row.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AltrStreamManagerApp());
}

/// Root application shell providing the dark theme foundation.
class AltrStreamManagerApp extends StatelessWidget {
  const AltrStreamManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    TextTheme textTheme = createTextTheme(context, "Nunito Sans", "Nunito");
    MaterialTheme theme = MaterialTheme(textTheme);

    return MaterialApp(
      title: 'Altr Stream Manager',
      debugShowCheckedModeBanner: false,
      theme: theme.light(),
      darkTheme: theme.dark(),
      home: const AltrStreamManagerPlaceholder(),
    );
  }
}
