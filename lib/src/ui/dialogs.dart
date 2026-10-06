import 'package:flutter/material.dart';

import '../accounts.dart';
import '../login_item.dart';
import '../monitor.dart';
import 'theme.dart';

class _DialogTitle extends StatelessWidget {
  const _DialogTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 12, height: 1.35, color: context.palette.muted),
      );
}

Future<({String label, String? email})?> showAddAccountDialog(BuildContext context) {
  final label = TextEditingController();
  final email = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<({String label, String? email})>(
    context: context,
    builder: (context) {
      void submit() {
        if (!formKey.currentState!.validate()) return;
        final typedEmail = email.text.trim();
        Navigator.pop(context, (label: label.text.trim(), email: typedEmail.isEmpty ? null : typedEmail));
      }

      return AlertDialog(
        title: const _DialogTitle('Add account'),
        scrollable: true,
        content: SizedBox(
          width: 320,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: label,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'Work, Personal…'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
                  onFieldSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  onFieldSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                const _Hint(
                  'Terminal opens and runs "claude auth login" for a new profile in '
                  '~/.claude-accounts. Sign in with this account in the browser. '
                  'Your current Claude Code login stays as it is.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Add and sign in')),
        ],
      );
    },
  );
}

Future<String?> showRenameDialog(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final value = controller.text.trim();
        if (value.isNotEmpty) Navigator.pop(context, value);
      }

      return AlertDialog(
        title: const _DialogTitle('Rename'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Save')),
        ],
      );
    },
  );
}

Future<bool> showRemoveDialog(BuildContext context, Account account) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: _DialogTitle('Remove ${account.label}?'),
      content: SizedBox(
        width: 320,
        child: _Hint(
          account.isManagedProfile
              ? 'This signs the profile out and deletes ${account.shortConfigDir}. '
                  'The Claude account itself is not affected.'
              : 'This stops monitoring ${account.shortConfigDir}. Nothing is deleted.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.palette.critical),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showSettingsDialog(BuildContext context, Monitor monitor, {required VoidCallback onQuit}) async {
  var settings = monitor.settings;
  var openAtLogin = monitor.loginItemStatus == LoginItemStatus.enabled;
  final loginItemSupported = monitor.loginItemStatus != LoginItemStatus.unsupported;
  final binary = TextEditingController(text: settings.claudeBinary ?? '');
  final detected = await monitor.cli.detect();
  if (!context.mounted) return;

  final saved = await showDialog<MonitorSettings>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const _DialogTitle('Settings'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Refresh every', style: TextStyle(fontSize: 13))),
                  DropdownButton<int>(
                    value: settings.refreshMinutes,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in const [1, 2, 5, 10, 15, 30])
                        DropdownMenuItem(value: m, child: Text('$m min', style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (m) => setState(() => settings = settings.copyWith(refreshMinutes: m)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (loginItemSupported)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Open at login', style: TextStyle(fontSize: 13)),
                  subtitle: monitor.loginItemStatus == LoginItemStatus.requiresApproval
                      ? const _Hint('Allow it in System Settings → General → Login Items.')
                      : null,
                  value: openAtLogin,
                  onChanged: (v) => setState(() => openAtLogin = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Same settings and memory for every account', style: TextStyle(fontSize: 13)),
                subtitle: const _Hint('Links settings, skills, memory and chat history from ~/.claude into each account.'),
                value: settings.shareWithMain,
                onChanged: (v) => setState(() => settings = settings.copyWith(shareWithMain: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Show main login', style: TextStyle(fontSize: 13)),
                subtitle: const _Hint('Shown only when it is not one of your accounts below.'),
                value: settings.showCurrentLogin,
                onChanged: (v) => setState(() => settings = settings.copyWith(showCurrentLogin: v)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: binary,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Claude Code binary',
                  hintText: 'Detected automatically',
                  helperText: detected == null ? 'Not found automatically' : 'Found: $detected',
                  helperMaxLines: 3,
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: onQuit,
            style: TextButton.styleFrom(foregroundColor: context.palette.critical),
            child: const Text('Quit app'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () {
                  final path = binary.text.trim();
                  Navigator.pop(context, settings.copyWith(claudeBinary: () => path.isEmpty ? null : path));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (saved == null) return;
  await monitor.updateSettings(saved);
  final wasOpenAtLogin = monitor.loginItemStatus == LoginItemStatus.enabled;
  if (loginItemSupported && openAtLogin != wasOpenAtLogin) {
    await monitor.setOpenAtLogin(openAtLogin);
  }
}
