import 'package:flutter/material.dart';

/// The semantic icons of the Limpid design system.
///
/// Status information is never carried by a color alone: every status uses
/// one of these icons next to its label.
abstract final class LimpidIcons {
  /// The icon of the neutral status.
  static const IconData neutral = Icons.circle_outlined;

  /// The icon of the informational status.
  static const IconData info = Icons.info_outline;

  /// The icon of the success status.
  static const IconData success = Icons.check_circle_outline;

  /// The icon of the warning status.
  static const IconData warning = Icons.warning_amber_rounded;

  /// The icon of the danger status.
  static const IconData danger = Icons.error_outline;

  /// The search icon.
  static const IconData search = Icons.search;

  /// The close icon.
  static const IconData close = Icons.close;

  /// The chevron pointing down.
  static const IconData chevronDown = Icons.expand_more;

  /// The chevron pointing up.
  static const IconData chevronUp = Icons.expand_less;

  /// The chevron pointing left.
  static const IconData chevronLeft = Icons.chevron_left;

  /// The chevron pointing right.
  static const IconData chevronRight = Icons.chevron_right;

  /// The arrow pointing left, used by the pagination.
  static const IconData arrowLeft = Icons.arrow_back;

  /// The arrow pointing right, used by the pagination.
  static const IconData arrowRight = Icons.arrow_forward;

  /// The empty state icon.
  static const IconData empty = Icons.auto_stories_outlined;

  /// The drag handle of a reorderable list.
  static const IconData dragHandle = Icons.drag_indicator;

  /// The comment icon.
  static const IconData comment = Icons.chat_bubble_outline;

  /// The AI suggestion icon.
  static const IconData suggestion = Icons.auto_awesome_outlined;

  /// The synchronization icon.
  static const IconData sync = Icons.sync;

  /// The offline icon.
  static const IconData offline = Icons.cloud_off_outlined;

  /// The error icon.
  static const IconData error = Icons.error_outline;

  /// The check icon.
  static const IconData check = Icons.check;

  /// The add icon.
  static const IconData add = Icons.add;

  /// The edit icon.
  static const IconData edit = Icons.edit_outlined;

  /// The delete icon.
  static const IconData delete = Icons.delete_outline;

  /// The more actions icon.
  static const IconData more = Icons.more_horiz;

  // --- Navigation ---------------------------------------------------------

  /// The dashboard icon, used by the "Bureau" destination.
  static const IconData home = Icons.home_outlined;

  /// The library icon, used by the "Livres" destination.
  static const IconData library = Icons.local_library_outlined;

  /// The book icon.
  static const IconData book = Icons.menu_book_outlined;

  /// The pen icon, used by the "Écrire" destination.
  static const IconData pen = Icons.edit_outlined;

  /// The account icon, used by the "Compte" destination.
  static const IconData user = Icons.person_outline;

  /// The settings icon.
  static const IconData settings = Icons.settings_outlined;

  // --- Structure ----------------------------------------------------------

  /// The outline icon, showing the tree of a manuscript.
  static const IconData tree = Icons.account_tree_outlined;

  /// The story bible icon.
  static const IconData bible = Icons.auto_stories_outlined;

  /// The timeline icon.
  static const IconData timeline = Icons.timeline_outlined;

  /// The plot thread icon.
  static const IconData flag = Icons.flag_outlined;

  /// The folder icon, used by the collections.
  static const IconData folder = Icons.folder_outlined;

  // --- Publication --------------------------------------------------------

  /// The export icon.
  static const IconData export = Icons.file_download_outlined;

  /// The public page icon.
  static const IconData globe = Icons.public_outlined;

  /// The money icon, used by the plans and the sales.
  static const IconData money = Icons.payments_outlined;

  /// The cover icon.
  static const IconData cover = Icons.photo_size_select_actual_outlined;

  // --- Progression --------------------------------------------------------

  /// The statistics icon.
  static const IconData chart = Icons.bar_chart_outlined;

  /// The goal icon.
  static const IconData target = Icons.track_changes_outlined;

  /// The clock icon.
  static const IconData clock = Icons.schedule_outlined;

  /// The calendar icon.
  static const IconData calendar = Icons.calendar_today_outlined;

  // --- Writing ------------------------------------------------------------

  /// The sparkles icon, used by the artificial intelligence surfaces.
  static const IconData sparkles = Icons.auto_awesome_outlined;

  /// The list icon.
  static const IconData list = Icons.format_list_bulleted;

  /// The quote icon.
  static const IconData quote = Icons.format_quote;

  /// The image icon.
  static const IconData image = Icons.image_outlined;

  /// The code icon.
  static const IconData code = Icons.code;

  /// The undo icon.
  static const IconData undo = Icons.undo;

  /// The redo icon.
  static const IconData redo = Icons.redo;

  /// The external link icon.
  static const IconData externalLink = Icons.open_in_new;

  /// The download icon.
  static const IconData download = Icons.download_outlined;

  /// The upload icon.
  static const IconData upload = Icons.upload_outlined;
}
