import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La préparation d'un dossier de publication.
///
/// La fonction reçoit les métadonnées validées et l'identifiant du livre
/// qui part : elle prépare le dossier et rend compte de ce qu'elle a fait.
typedef KdpPrepareCallback =
    Future<void> Function(KdpMetadata metadata, String projectId);

/// Le formulaire des métadonnées d'une fiche produit Amazon.
///
/// Le formulaire **valide avant d'envoyer** : un ISBN manquant ou mal
/// formé arrête la préparation ici, et le champ fautif est nommé. Le
/// formulaire ne part pas avec des métadonnées que le serveur refusera.
///
/// Les mots-clés et les catégories se saisissent en une ligne, séparés par
/// des virgules : c'est la forme qu'Amazon attend — sept mots-clés, trois
/// catégories.
class KdpMetadataForm extends ConsumerStatefulWidget {
  /// Crée le formulaire.
  const KdpMetadataForm({
    super.key,
    this.initial,
    this.submitLabel,
    this.onSubmit,
    this.onCompleted,
  });

  /// Le dépôt que le formulaire reprend, quand l'auteur corrige un refus.
  ///
  /// Le serveur ne garde qu'un titre : le sous-titre y est joint, et le
  /// formulaire le retrouve dans le titre.
  final KdpSubmission? initial;

  /// Le libellé du bouton qui prépare le dossier.
  final String? submitLabel;

  /// La préparation du dossier.
  final KdpPrepareCallback? onSubmit;

  /// Appelée quand le dossier est préparé.
  final VoidCallback? onCompleted;

  @override
  ConsumerState<KdpMetadataForm> createState() => _KdpMetadataFormState();
}

/// L'état du formulaire des métadonnées.
final class _KdpMetadataFormState extends ConsumerState<KdpMetadataForm> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _author;
  late final TextEditingController _description;
  late final TextEditingController _keywords;
  late final TextEditingController _categories;
  late final TextEditingController _language;
  late final TextEditingController _isbn;

  String? _projectId;
  KdpFieldError? _error;
  Object? _failure;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    final KdpSubmission? initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _subtitle = TextEditingController();
    _author = TextEditingController(text: initial?.author ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _keywords = TextEditingController(
      text: (initial?.keywords ?? const <String>[]).join(', '),
    );
    _categories = TextEditingController(
      text: (initial?.categories ?? const <String>[]).join(', '),
    );
    _language = TextEditingController(text: initial?.language ?? '');
    _isbn = TextEditingController(text: initial?.isbn ?? '');
    _projectId = initial?.projectId;
    // Le nom de l'auteur vient de la session quand elle le porte : l'auteur
    // ne le retape pas à chaque dépôt.
    final String author = ref.read(kdpAuthorNameProvider);
    if (author.isNotEmpty && _author.text.isEmpty) {
      _author.text = author;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _author.dispose();
    _description.dispose();
    _keywords.dispose();
    _categories.dispose();
    _language.dispose();
    _isbn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<Project>> books = ref.watch(kdpBooksProvider);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _bookField(context, strings, books),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _title,
            label: strings.kdpTitleLabel,
            errorText: _errorText(strings, KdpFields.title),
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _subtitle,
            label: strings.kdpSubtitleLabel,
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _author,
            label: strings.fieldAuthorName,
            helperText: strings.fieldAuthorNameHint,
            errorText: _errorText(strings, KdpFields.author),
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextArea(
            controller: _description,
            label: strings.kdpDescription,
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _keywords,
            label: strings.kdpKeywords,
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _categories,
            label: strings.kdpBisac,
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _language,
            label: strings.kdpLanguage,
            onChanged: (_) => _clearError(),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _isbn,
            label: strings.kdpIsbn,
            errorText: _errorText(strings, KdpFields.isbn),
            onChanged: (_) => _clearError(),
          ),
          if (_failure != null) ...<Widget>[
            SizedBox(height: scope.spacing.space16),
            LimpidBanner(
              variant: LimpidStatusVariant.danger,
              title: strings.errorGeneric,
              message: _failureMessage(_failure!),
            ),
          ],
          SizedBox(height: scope.spacing.space24),
          _actions(context, strings),
        ],
      ),
    );
  }

  /// Le choix du livre qui part chez Amazon.
  Widget _bookField(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<Project>> books,
  ) {
    return books.when(
      data: (List<Project> projects) {
        if (projects.isEmpty) {
          // L'auteur n'a aucun livre : le formulaire ne peut rien préparer.
          return LimpidBanner(
            variant: LimpidStatusVariant.info,
            title: strings.dataEmptyMessage,
          );
        }
        final List<LimpidSelectItem<String>> items = <LimpidSelectItem<String>>[
          for (final Project project in projects)
            LimpidSelectItem<String>(
              value: project.id.value,
              label: project.title,
              icon: LimpidIcons.book,
            ),
        ];
        // Le livre repris peut ne plus exister : le champ montre alors
        // aucun choix plutôt qu'un choix impossible.
        final bool isKnown = items.any(
          (LimpidSelectItem<String> item) => item.value == _projectId,
        );
        return LimpidSelect<String>(
          items: items,
          value: isKnown ? _projectId : null,
          label: strings.libraryTitle,
          errorText: _errorText(strings, KdpFields.projectId),
          onChanged: (String? value) => setState(() => _projectId = value),
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: context.limpid.spacing.space8),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: LimpidSpinner(),
        ),
      ),
      error: (Object error, StackTrace stack) => LimpidBanner(
        variant: LimpidStatusVariant.danger,
        title: strings.errorGeneric,
      ),
    );
  }

  /// Les boutons du formulaire.
  Widget _actions(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final bool canSubmit = _projectId != null && !_isRunning;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
        ),
        SizedBox(width: scope.spacing.space8),
        LimpidButton(
          label: widget.submitLabel ?? strings.kdpPrepare,
          loading: _isRunning,
          onPressed: canSubmit ? _submit : null,
        ),
      ],
    );
  }

  /// Prépare le dossier avec les métadonnées saisies.
  Future<void> _submit() async {
    final KdpMetadata metadata = _metadata();
    final KdpFieldError? error = metadata.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final String? projectId = _projectId;
    if (projectId == null) return;
    // Le livre doit exister dans la bibliothèque de l'auteur : le serveur
    // refuse un livre inconnu, et l'auteur ne le verrait pas.
    final List<Project> books =
        ref.read(kdpBooksProvider).value ?? const <Project>[];
    final bool isKnown = books.any(
      (Project project) => project.id.value == projectId,
    );
    if (!isKnown) {
      setState(() {
        _error = const KdpFieldError(
          field: KdpFields.projectId,
          reason: KdpFieldErrorReason.empty,
        );
      });
      return;
    }

    setState(() {
      _error = null;
      _failure = null;
      _isRunning = true;
    });
    try {
      await widget.onSubmit?.call(metadata, projectId);
    } on KdpValidationException catch (error) {
      setState(() {
        _isRunning = false;
        _error = error.error;
      });
      return;
    } on Object catch (error) {
      setState(() {
        _isRunning = false;
        _failure = error;
      });
      return;
    }
    setState(() => _isRunning = false);
    widget.onCompleted?.call();
  }

  /// Les métadonnées saisies par l'auteur.
  KdpMetadata _metadata() {
    return KdpMetadata(
      title: _title.text.trim(),
      subtitle: _subtitle.text.trim(),
      author: _author.text.trim(),
      description: _description.text.trim(),
      keywords: _splitList(_keywords.text),
      categories: _splitList(_categories.text),
      language: _language.text.trim(),
      isbn: _isbn.text.trim(),
    );
  }

  /// La liste portée par une ligne de saisie.
  static List<String> _splitList(String raw) {
    return <String>[
      for (final String part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  /// Le message d'erreur du champ [field], `null` quand il est valide.
  String? _errorText(AppLocalizations strings, String field) {
    final KdpFieldError? error = _error;
    if (error == null || error.field != field) return null;
    return _fieldMessage(strings, error);
  }

  /// Le message d'un champ fautif.
  ///
  /// Les fichiers de traduction sont gelés : le message est le plus proche
  /// qui existe, et il nomme le champ fautif.
  String _fieldMessage(AppLocalizations strings, KdpFieldError error) {
    if (error.field == KdpFields.author) return strings.errorEmptyName;
    return '${_labelOf(strings, error.field)} : ${strings.errorGeneric}';
  }

  /// Le libellé d'un champ, dans la langue de l'interface.
  String _labelOf(AppLocalizations strings, String field) {
    return switch (field) {
      KdpFields.title => strings.kdpTitleLabel,
      KdpFields.subtitle => strings.kdpSubtitleLabel,
      KdpFields.author => strings.fieldAuthorName,
      KdpFields.description => strings.kdpDescription,
      KdpFields.keywords => strings.kdpKeywords,
      KdpFields.categories => strings.kdpBisac,
      KdpFields.language => strings.kdpLanguage,
      KdpFields.isbn => strings.kdpIsbn,
      KdpFields.projectId => strings.libraryTitle,
      _ => strings.kdpTitleLabel,
    };
  }

  /// Le message d'une erreur venue du serveur.
  String? _failureMessage(Object failure) {
    if (failure is KdpUnavailableException) return failure.reason;
    if (failure is ApiException) return failure.message;
    return null;
  }

  /// Efface l'erreur quand l'auteur corrige le champ.
  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }
}
