import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounts.dart';
import '../monitor.dart';
import '../tray_panel.dart';
import '../usage.dart';
import 'dialogs.dart';
import 'format.dart';
import 'theme.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.monitor, required this.tray, required this.account});

  final Monitor monitor;
  final TrayPanel tray;
  final Account account;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = monitor.usageOf(account);
    final error = monitor.errorOf(account);
    final inEditor = monitor.isInEditor(account);

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inEditor ? palette.accent.withValues(alpha: 0.55) : palette.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(monitor: monitor, tray: tray, account: account, usage: usage),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Body(monitor: monitor, account: account, usage: usage, error: error),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.monitor, required this.tray, required this.account, required this.usage});

  final Monitor monitor;
  final TrayPanel tray;
  final Account account;
  final AccountUsage? usage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final subtitle = usage?.email ?? account.email ?? account.shortConfigDir;
    final plan = usage?.plan;
    final editor = monitor.editor;

    return Row(
      children: [
        _Avatar(account: account, colorIndex: monitor.profiles.indexWhere((p) => p.id == account.id)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      account.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text),
                    ),
                  ),
                  if (plan != null) ...[
                    const SizedBox(width: 6),
                    _PlanBadge(plan: plan),
                  ],
                  if (editor != null && monitor.isInEditor(account)) ...[
                    const SizedBox(width: 6),
                    _InUseChip(editorName: editor.name),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
            ],
          ),
        ),
        if (editor != null && monitor.canSwitch(account)) ...[
          const SizedBox(width: 8),
          _SwitchButton(monitor: monitor, account: account, editorName: editor.name),
        ],
        _CardMenu(monitor: monitor, tray: tray, account: account, usage: usage),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.monitor,
    required this.account,
    required this.usage,
    required this.error,
  });

  final Monitor monitor;
  final Account account;
  final AccountUsage? usage;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usage = this.usage;

    if (usage == null) {
      if (error != null) {
        return _Notice(
          icon: Icons.error_outline_rounded,
          color: palette.critical,
          text: error!,
          action: TextButton(onPressed: () => monitor.refresh(account), child: const Text('Retry')),
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Column(children: [_MeterPlaceholder(), SizedBox(height: 12), _MeterPlaceholder()]),
      );
    }

    switch (usage.loginState) {
      case LoginState.signedOut:
        final waiting = monitor.isWaitingForSignIn(account);
        return _Notice(
          icon: waiting ? Icons.hourglass_top_rounded : Icons.login_rounded,
          color: palette.muted,
          text: account.isCurrentLogin
              ? 'Claude Code is signed out right now.'
              : waiting
                  ? 'Finish signing in in your browser. This card updates by itself.'
                  : 'Not signed in yet.',
          action: account.isCurrentLogin
              ? null
              : FilledButton.tonal(
                  onPressed: () => monitor.signIn(account),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  child: Text(waiting ? 'Open again' : 'Sign in'),
                ),
        );
      case LoginState.noPlanLimits:
        return _Notice(
          icon: Icons.info_outline_rounded,
          color: palette.muted,
          text: 'This login has no plan limits to show (API key or Console account).',
        );
      case LoginState.signedIn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final window in usage.windows) ...[
              const SizedBox(height: 12),
              UsageMeter(window: window),
            ],
            if (usage.windows.isEmpty)
              _Notice(
                icon: Icons.info_outline_rounded,
                color: palette.muted,
                text: 'No usage windows reported yet.',
              ),
            if (monitor.ownCopiesOf(account).isNotEmpty) ...[
              const SizedBox(height: 10),
              Tooltip(
                message: 'This account has its own ${monitor.ownCopiesOf(account).join(', ')}, '
                    'so it is not linked to ~/.claude. Remove it from ${account.shortConfigDir} to share it.',
                child: Row(
                  children: [
                    Icon(Icons.link_off_rounded, size: 13, color: palette.muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Not shared: ${monitor.ownCopiesOf(account).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Tooltip(
                message: error!,
                child: Row(
                  children: [
                    Icon(Icons.sync_problem_rounded, size: 13, color: palette.warn),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        "Couldn't refresh. Showing data from ${clockTime(usage.fetchedAt)}.",
                        style: TextStyle(fontSize: 11.5, color: palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }
}

class UsageMeter extends StatelessWidget {
  const UsageMeter({super.key, required this.window});

  final UsageWindow window;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = window.currentPercent;
    final color = palette.meterColor(percent);
    const figures = [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              window.label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: palette.text),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                resetLabel(window.resetsAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: palette.muted, fontFeatures: figures),
              ),
            ),
            Text(
              '${percent.round()}%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: percent >= 75 ? color : palette.text,
                fontFeatures: figures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: palette.track),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (percent / 100).clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MeterPlaceholder extends StatelessWidget {
  const _MeterPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 120,
          height: 9,
          decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 8),
        Container(
          height: 6,
          decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(3)),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text, this.action});

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: context.palette.muted, height: 1.3),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account, required this.colorIndex});

  final Account account;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = account.isCurrentLogin
        ? palette.meter
        : Palette.avatarColors[colorIndex % Palette.avatarColors.length];
    final initial = account.label.trim().isEmpty ? '?' : account.label.trim()[0].toUpperCase();
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: account.isCurrentLogin
          ? Icon(Icons.terminal_rounded, size: 16, color: palette.card)
          : Text(
              initial,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.monitor, required this.account, required this.editorName});

  final Monitor monitor;
  final Account account;
  final String editorName;

  Future<void> _switch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await monitor.switchEditorTo(account);
      messenger.showSnackBar(SnackBar(
        content: Text('$editorName now uses ${account.label}. Start a new Claude chat there to use it.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't switch $editorName: $error"),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: 'Use this account in Claude Code for $editorName',
      child: OutlinedButton(
        onPressed: () => _switch(context),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: palette.accent,
          side: BorderSide(color: palette.border),
          textStyle: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: const Text('Switch'),
      ),
    );
  }
}

class _InUseChip extends StatelessWidget {
  const _InUseChip({required this.editorName});

  final String editorName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: 'Claude Code in $editorName uses this account',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: palette.accentSoft, borderRadius: BorderRadius.circular(5)),
        child: Text(
          'In $editorName',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.accent),
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.plan});

  final String plan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        plan.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: palette.muted,
        ),
      ),
    );
  }
}

enum _CardAction { refresh, copyCommand, rename, signIn, signOut, hide, remove }

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.monitor, required this.tray, required this.account, required this.usage});

  final Monitor monitor;
  final TrayPanel tray;
  final Account account;
  final AccountUsage? usage;

  @override
  Widget build(BuildContext context) {
    final signedIn = usage != null && usage!.loginState != LoginState.signedOut;
    return PopupMenuButton<_CardAction>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: context.palette.muted),
      iconSize: 18,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (action) => _handle(context, action),
      itemBuilder: (_) => [
        _item(_CardAction.refresh, Icons.refresh_rounded, 'Refresh'),
        _item(_CardAction.copyCommand, Icons.content_copy_rounded, 'Copy terminal command'),
        if (!account.isCurrentLogin) ...[
          _item(_CardAction.rename, Icons.edit_outlined, 'Rename'),
          signedIn
              ? _item(_CardAction.signOut, Icons.logout_rounded, 'Sign out')
              : _item(_CardAction.signIn, Icons.login_rounded, 'Sign in'),
          const PopupMenuDivider(),
          _item(_CardAction.remove, Icons.delete_outline_rounded, 'Remove'),
        ] else
          _item(_CardAction.hide, Icons.visibility_off_outlined, 'Hide this card'),
      ],
    );
  }

  PopupMenuItem<_CardAction> _item(_CardAction value, IconData icon, String label) => PopupMenuItem(
        value: value,
        height: 34,
        child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(label)]),
      );

  Future<void> _handle(BuildContext context, _CardAction action) async {
    switch (action) {
      case _CardAction.refresh:
        await monitor.refresh(account);
      case _CardAction.copyCommand:
        final command = monitor.cli.terminalCommand(account);
        await Clipboard.setData(ClipboardData(text: command));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Copied: $command'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ));
        }
      case _CardAction.rename:
        final label = await tray.withRoomForDialog(() => showRenameDialog(context, account.label), height: 300);
        if (label != null) await monitor.rename(account, label);
      case _CardAction.signIn:
        await monitor.signIn(account);
      case _CardAction.signOut:
        await monitor.signOut(account);
      case _CardAction.hide:
        await monitor.updateSettings(monitor.settings.copyWith(showCurrentLogin: false));
      case _CardAction.remove:
        final confirmed = await tray.withRoomForDialog(() => showRemoveDialog(context, account), height: 300);
        if (confirmed) await monitor.remove(account);
    }
  }
}
