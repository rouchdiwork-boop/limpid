import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/export_repository.dart';
import 'package:limpid_app/src/features/export/export_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le delai entre deux lectures de l'etat du travail.
///
/// Le travail se fabrique sur le serveur : la fenetre le suit sans jamais
/// bloquer l'interface.
const Duration exportPollInterval = Duration(seconds: 1);

/// Ouvre la fenetre de l'export d'un livre.
///
/// La fenetre ne fabrique rien : elle demande le travail, le suit, et
/// donne le fichier quand il est pret.
Future<void> showExportDialog(
  BuildContext context, {
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => ExportDialog(projectId: projectId),
  );
}

/// La fenetre de l'export d'un livre.
///
/// La fenetre suit le travail : elle dit qu'il court, qu'il est pret, ou
/// qu'il a echoue. L'echec propose une relance, et le succes propose le
/// telechargement — en disant que le fichier expire.
class ExportDialog extends ConsumerStatefulWidget {
  /// Cree la fenetre.
  const ExportDialog({super.key, required this.projectId});

  /// Le livre exporte.
  final String projectId;

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  /// Le format demande.
  ExportFormat _format = ExportFormat.epub3;

  /// L'etat du travail, `null` avant la demande.
  ExportProgress? _progress;

  /// Le message d'un echec de l'application, distinct de l'echec du
  /// serveur.
  String? _failure;

  /// La demande est-elle en cours.
  bool _isStarting = false;

  /// Le telechargement est-il en cours.
  bool _isDownloading = false;

  /// La lecture de l'etat du travail.
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final ExportProgress? progress = _progress;

    return LimpidDialog(
      title: strings.exportTitle,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (progress == null) ..._choice(strings),
          if (progress is ExportQueued || progress is ExportRunning)
            ..._running(strings),
          if (progress is ExportReady) ..._ready(strings, progress),
          if (progress is ExportFailed) ..._failed(strings, progress),
          if (_failure != null) ..._failureOf(strings),
        ],
      ),
    );
  }

  /// Le choix du format et le bouton qui demande le travail.
  List<Widget> _choice(AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    return <Widget>[
      Wrap(
        spacing: scope.spacing.space8,
        runSpacing: scope.spacing.space8,
        children: <Widget>[
          _chip(strings.exportFormatEpub, ExportFormat.epub3),
          _chip(strings.exportFormatPdf, ExportFormat.pdfReflowable),
          _chip(strings.exportFormatDocx, ExportFormat.docx),
          _chip(strings.exportFormatHtml, ExportFormat.html),
          _chip(strings.exportFormatMarkdown, ExportFormat.markdown),
        ],
      ),
      SizedBox(height: scope.spacing.space16),
      LimpidButton(
        label: strings.exportStart,
        icon: LimpidIcons.export,
        loading: _isStarting,
        onPressed: _isStarting ? null : () => _start(),
      ),
    ];
  }

  /// La pastille d'un format.
  Widget _chip(String label, ExportFormat format) {
    return LimpidChip(
      label: label,
      isSelected: _format == format,
      onTap: () => setState(() => _format = format),
    );
  }

  /// Le travail court : l'interface ne bloque pas, elle suit.
  List<Widget> _running(AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    return <Widget>[
      Row(
        children: <Widget>[
          const LimpidSpinner(size: LimpidSpinnerSize.medium),
          SizedBox(width: scope.spacing.space8),
          Expanded(child: Text(strings.exportRunning)),
        ],
      ),
    ];
  }

  /// Le travail a abouti : le fichier est pret et il expire.
  List<Widget> _ready(AppLocalizations strings, ExportReady ready) {
    final LimpidThemeScope scope = context.limpid;
    final DateTime? expiresAt = ready.expiresAt;
    return <Widget>[
      Text(strings.exportReady, style: Theme.of(context).textTheme.titleMedium),
      if (expiresAt != null) ...<Widget>[
        SizedBox(height: scope.spacing.space4),
        Text(
          strings.exportExpiresAt(_dateOf(context, expiresAt)),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
      SizedBox(height: scope.spacing.space16),
      LimpidButton(
        label: strings.exportDownload,
        icon: LimpidIcons.download,
        loading: _isDownloading,
        onPressed: _isDownloading ? null : () => _download(ready),
      ),
    ];
  }

  /// Le travail a echoue : l'echec propose une relance.
  List<Widget> _failed(AppLocalizations strings, ExportFailed failed) {
    final LimpidThemeScope scope = context.limpid;
    return <Widget>[
      Text(
        strings.exportFailed,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: scope.colors.danger),
      ),
      SizedBox(height: scope.spacing.space4),
      Text(failed.message, style: Theme.of(context).textTheme.bodySmall),
      SizedBox(height: scope.spacing.space16),
      LimpidButton(
        label: strings.actionRetry,
        icon: LimpidIcons.sync,
        loading: _isStarting,
        onPressed: _isStarting ? null : () => _retry(failed.id),
      ),
    ];
  }

  /// L'echec de l'application : le serveur ne repond pas.
  List<Widget> _failureOf(AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    return <Widget>[
      SizedBox(height: scope.spacing.space8),
      Text(
        _failure!,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scope.colors.danger),
      ),
    ];
  }

  /// Demande le travail.
  Future<void> _start() async {
    setState(() {
      _isStarting = true;
      _failure = null;
    });
    try {
      final ExportJobRepository repository = ref.read(
        exportJobRepositoryProvider,
      );
      final ExportProgress progress = await repository.start(
        projectId: widget.projectId,
        format: _format,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _isStarting = false;
      });
      _follow(progress.id);
    } on Object {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _failure = AppLocalizations.of(context).exportFailed;
      });
    }
  }

  /// Relance le travail en echec : la relance cree un travail **neuf**.
  Future<void> _retry(String jobId) async {
    setState(() {
      _isStarting = true;
      _failure = null;
    });
    try {
      final ExportJobRepository repository = ref.read(
        exportJobRepositoryProvider,
      );
      final ExportProgress progress = await repository.retry(jobId);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _isStarting = false;
      });
      _follow(progress.id);
    } on Object {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _failure = AppLocalizations.of(context).exportFailed;
      });
    }
  }

  /// Suit le travail [jobId] jusqu'a ce qu'il aboutisse ou qu'il echoue.
  void _follow(String jobId) {
    _poll?.cancel();
    _poll = Timer.periodic(exportPollInterval, (Timer _) async {
      try {
        final ExportJobRepository repository = ref.read(
          exportJobRepositoryProvider,
        );
        final ExportProgress progress = await repository.read(jobId);
        if (!mounted) return;
        setState(() => _progress = progress);
        if (progress is ExportReady || progress is ExportFailed) {
          _poll?.cancel();
        }
      } on Object {
        if (!mounted) return;
        _poll?.cancel();
        setState(() => _failure = AppLocalizations.of(context).exportFailed);
      }
    });
  }

  /// Telecharge le fichier et l'ecrit sur le poste.
  Future<void> _download(ExportReady ready) async {
    setState(() => _isDownloading = true);
    try {
      final ExportJobRepository repository = ref.read(
        exportJobRepositoryProvider,
      );
      final ExportArtefact artefact = await repository.download(ready);
      final ExportFileWriter writer = ref.read(exportFileWriterProvider);
      await writer(artefact);
      if (!mounted) return;
      Navigator.of(context).pop();
      LimpidSnackbar.show(
        context,
        message: AppLocalizations.of(context).exportDownloaded,
        variant: LimpidStatusVariant.success,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _failure = AppLocalizations.of(context).exportFailed;
      });
    }
  }

  /// Ecrit une date dans la langue de l'interface.
  String _dateOf(BuildContext context, DateTime moment) {
    return MaterialLocalizations.of(context).formatMediumDate(moment);
  }
}
