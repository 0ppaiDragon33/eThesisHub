import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/personal_file_actions.dart';
import 'package:ethesishub/features/forms/editable/name_dialog.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';
import 'package:ethesishub/providers/my_files_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// One thing in My files: a form copy or an uploaded file.
sealed class _Item {
  const _Item();
  String get id;
  String get name;
  String? get folderId;
  DateTime? get when;
}

class _CopyItem extends _Item {
  const _CopyItem(this.copy);
  final FormCopy copy;
  @override
  String get id => copy.id;
  @override
  String get name => copy.name;
  @override
  String? get folderId => copy.folderId;
  @override
  DateTime? get when => copy.updatedAt;
}

class _FileItem extends _Item {
  const _FileItem(this.file);
  final PersonalFile file;
  @override
  String get id => file.id;
  @override
  String get name => file.name;
  @override
  String? get folderId => file.folderId;
  @override
  DateTime? get when => file.createdAt;
}

enum _Act { open, rename, move, delete }

/// The "top level" choice in Move to. Folder ids are never empty.
const _topLevel = '';

/// A person's own form copies and uploaded files, in one-level folders.
/// Nobody else can see them (spec E9).
///
/// [folderId] null is the top level; otherwise the open folder, reached by
/// pushing `/files?folder={id}` so the system back closes it.
class MyFilesScreen extends ConsumerStatefulWidget {
  const MyFilesScreen({super.key, this.folderId, this.pickDocument});

  final String? folderId;

  /// Replaces the platform file dialog in tests.
  final DocumentPicker? pickDocument;

  @override
  ConsumerState<MyFilesScreen> createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends ConsumerState<MyFilesScreen> {
  bool _uploading = false;

  String? get _uid => ref.read(signedInUidProvider);

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _sayError(String what, Object e) => _say(e is StorageFailure
      ? '${e.message} [${e.code}]'
      : 'Could not $what: $e');

  void _leaveFolder() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/files');
    }
  }

  Future<void> _newFolder() async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'New folder',
      initial: 'New folder',
      confirmLabel: 'Create',
      maxLength: kFolderNameMax,
    );
    if (name == null) return;
    try {
      await ref.read(myFilesRepositoryProvider).createFolder(uid: uid, name: name);
    } catch (e) {
      _sayError('create the folder', e);
    }
  }

  Future<void> _upload() async {
    final uid = _uid;
    if (uid == null || _uploading) return;
    final picked = await (widget.pickDocument ?? realPicker)(
      allowed: kPersonalFileTypes,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await uploadPersonalFile(
        storage: ref.read(storageServiceProvider),
        remover: ref.read(personalFileRemoverProvider),
        repo: ref.read(myFilesRepositoryProvider),
        uid: uid,
        file: picked,
        folderId: widget.folderId,
      );
      _say('Added ${picked.name}.');
    } on PersonalFileRejected catch (e) {
      _say(e.message);
    } catch (e) {
      _sayError('add the file', e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(_Item item) async {
    switch (item) {
      case _CopyItem(:final copy):
        context.push('/forms/${copy.formId}/copies/${copy.id}');
      case _FileItem(:final file):
        await openStoredDocument(context, ref, file.storagePath,
            label: file.name);
    }
  }

  Future<void> _rename(_Item item) async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename',
      initial: item.name,
      confirmLabel: 'Rename',
      maxLength: item is _FileItem ? kFileNameMax : kFormCopyNameMax,
    );
    if (name == null || name == item.name) return;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .rename(uid: uid, copyId: copy.id, name: name);
        case _FileItem(:final file):
          await ref
              .read(myFilesRepositoryProvider)
              .renameFile(uid: uid, fileId: file.id, name: name);
      }
    } catch (e) {
      _sayError('rename it', e);
    }
  }

  Future<void> _move(_Item item, List<PersonalFolder> folders) async {
    final uid = _uid;
    if (uid == null) return;
    final inAFolder = folders.any((f) => f.id == item.folderId);
    final targets = [for (final f in folders) if (f.id != item.folderId) f];
    if (!inAFolder && targets.isEmpty) {
      _say('Make a folder first with New folder.');
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move to'),
        children: [
          if (inAFolder)
            SimpleDialogOption(
              key: const Key('moveTo-top'),
              onPressed: () => Navigator.of(dialogContext).pop(_topLevel),
              child: const Text('Top level'),
            ),
          for (final f in targets)
            SimpleDialogOption(
              key: Key('moveTo-${f.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(f.id),
              child: Text(f.name),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final folderId = choice == _topLevel ? null : choice;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .moveToFolder(uid: uid, copyId: copy.id, folderId: folderId);
        case _FileItem(:final file):
          await ref
              .read(myFilesRepositoryProvider)
              .moveFile(uid: uid, fileId: file.id, folderId: folderId);
      }
    } catch (e) {
      _sayError('move it', e);
    }
  }

  Future<void> _delete(_Item item) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: item is _FileItem ? 'Delete this file?' : 'Delete this copy?',
      message: '"${item.name}" will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmKey: const Key('confirmDeleteItem'),
    );
    if (!confirmed) return;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .delete(uid: uid, copyId: copy.id);
        case _FileItem(:final file):
          await deletePersonalFile(
            remover: ref.read(personalFileRemoverProvider),
            repo: ref.read(myFilesRepositoryProvider),
            uid: uid,
            file: file,
          );
      }
    } catch (e) {
      _sayError('delete it', e);
    }
  }

  Future<void> _renameFolder(PersonalFolder folder) async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename folder',
      initial: folder.name,
      confirmLabel: 'Rename',
      maxLength: kFolderNameMax,
    );
    if (name == null || name == folder.name) return;
    try {
      await ref
          .read(myFilesRepositoryProvider)
          .renameFolder(uid: uid, folderId: folder.id, name: name);
    } catch (e) {
      _sayError('rename the folder', e);
    }
  }

  Future<void> _deleteFolder(PersonalFolder folder, int count) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete this folder?',
      message: switch (count) {
        0 => 'The folder is empty.',
        1 => 'The 1 item in it moves to the top level. Nothing in it is '
            'deleted.',
        _ => 'The $count items in it move to the top level. Nothing in it '
            'is deleted.',
      },
      confirmLabel: 'Delete folder',
      confirmKey: const Key('confirmDeleteFolder'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(myFilesRepositoryProvider)
          .deleteFolder(uid: uid, folderId: folder.id);
      if (mounted) _leaveFolder();
    } catch (e) {
      _sayError('delete the folder', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(myFoldersProvider);
    final filesAsync = ref.watch(myPersonalFilesProvider);
    final copiesAsync = ref.watch(myAllFormCopiesProvider);

    final error = foldersAsync.error ?? filesAsync.error ?? copiesAsync.error;
    if (error != null) {
      return _framed(PageShell(
        title: 'My files',
        children: [ErrorState(error: error, message: 'Could not load your files.')],
      ));
    }
    if (!foldersAsync.hasValue ||
        !filesAsync.hasValue ||
        !copiesAsync.hasValue) {
      return _framed(const PageShell(
        children: [LoadingState.page(label: 'Loading your files…')],
      ));
    }

    final folders = foldersAsync.value!;
    final files = filesAsync.value!;
    final copies = copiesAsync.value!;
    final folderIds = {for (final f in folders) f.id};

    PersonalFolder? open;
    for (final f in folders) {
      if (f.id == widget.folderId) open = f;
    }
    if (widget.folderId != null && open == null) {
      return _framed(PageShell(title: 'My files', children: [
        EmptyState(
          key: const Key('folderMissing'),
          icon: Icons.folder_off_outlined,
          title: 'This folder no longer exists',
          message: 'It may have been deleted. Its files are at the top level '
              'of My files.',
          action: TextButton(
            onPressed: _leaveFolder,
            child: const Text('All files'),
          ),
        ),
      ]));
    }

    // At the top level, anything whose folder is gone shows here too, so
    // nothing becomes unreachable.
    bool here(String? itemFolder) => widget.folderId == null
        ? (itemFolder == null || !folderIds.contains(itemFolder))
        : itemFolder == widget.folderId;
    final items = <_Item>[
      for (final c in copies)
        if (here(c.folderId)) _CopyItem(c),
      for (final f in files)
        if (here(f.folderId)) _FileItem(f),
    ]..sort(_newestFirst);

    int countIn(String folderId) =>
        copies.where((c) => c.folderId == folderId).length +
        files.where((f) => f.folderId == folderId).length;

    final atTop = open == null;
    final showFolders = atTop && folders.isNotEmpty;

    return _framed(PageShell(
      maxWidth: AppTokens.measureWide,
      kicker: atTop ? 'Resources' : 'My files',
      title: open?.name ?? 'My files',
      subtitle: atTop
          ? 'Your form copies and uploaded files. Only you can see them.'
          : null,
      actions: [
        if (atTop)
          OutlinedButton.icon(
            key: const Key('newFolder'),
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New folder'),
          ),
        FilledButton.icon(
          key: const Key('uploadFile'),
          onPressed: _uploading ? null : _upload,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: Text(_uploading ? 'Uploading…' : 'Upload file'),
        ),
      ],
      children: [
        if (!atTop) ...[
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              TextButton.icon(
                key: const Key('backToAllFiles'),
                onPressed: _leaveFolder,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('All files'),
              ),
              TextButton.icon(
                key: const Key('renameFolder'),
                onPressed: () => _renameFolder(open!),
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                label: const Text('Rename folder'),
              ),
              TextButton.icon(
                key: const Key('deleteFolder'),
                onPressed: () => _deleteFolder(open!, items.length),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete folder'),
              ),
            ],
          ),
          const Gap.md(),
        ],
        if (!showFolders && items.isEmpty)
          EmptyState(
            key: const Key('myFilesEmpty'),
            icon: Icons.folder_open_outlined,
            title: 'Nothing here yet',
            message: atTop
                ? 'Upload a file, or start a form copy from the Forms screen.'
                : 'Move files here, or upload one while this folder is open.',
          ),
        if (showFolders) ...[
          Panel(
            title: 'Folders',
            flush: true,
            child: Column(children: [
              for (final f in folders)
                RecordRow(
                  key: Key('folder-${f.id}'),
                  leading: Icon(Icons.folder_outlined,
                      color: Tone.neutral.color(context)),
                  title: f.name,
                  subtitle: _itemCount(countIn(f.id)),
                  onTap: () => context.push('/files?folder=${f.id}'),
                ),
            ]),
          ),
          const Gap.lg(),
        ],
        if (items.isNotEmpty)
          Panel(
            title: 'Files and copies',
            flush: true,
            child: Column(children: [
              for (final item in items)
                RecordRow(
                  key: Key('item-${item.id}'),
                  leading: Icon(_iconFor(item),
                      color: Tone.neutral.color(context)),
                  title: item.name,
                  subtitle: _subtitleFor(item),
                  onTap: () => _open(item),
                  trailing: PopupMenuButton<_Act>(
                    key: Key('itemMenu-${item.id}'),
                    tooltip: 'More',
                    onSelected: (act) => switch (act) {
                      _Act.open => _open(item),
                      _Act.rename => _rename(item),
                      _Act.move => _move(item, folders),
                      _Act.delete => _delete(item),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _Act.open, child: Text('Open')),
                      PopupMenuItem(value: _Act.rename, child: Text('Rename')),
                      PopupMenuItem(value: _Act.move, child: Text('Move to…')),
                      PopupMenuItem(value: _Act.delete, child: Text('Delete')),
                    ],
                  ),
                ),
            ]),
          ),
      ],
    ));
  }

  Widget _framed(Widget child) =>
      KeyedSubtree(key: const Key('myFiles'), child: child);

  static int _newestFirst(_Item a, _Item b) {
    final at = a.when;
    final bt = b.when;
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    return bt.compareTo(at);
  }

  static String _itemCount(int n) => n == 1 ? '1 item' : '$n items';

  static IconData _iconFor(_Item item) => switch (item) {
        _CopyItem() => Icons.edit_note_rounded,
        _FileItem(:final file) => switch (file.contentType) {
            'application/pdf' => Icons.picture_as_pdf_outlined,
            'image/png' || 'image/jpeg' => Icons.image_outlined,
            'application/vnd.ms-powerpoint' ||
            'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
              Icons.slideshow_outlined,
            _ => Icons.description_outlined,
          },
      };

  static String _subtitleFor(_Item item) {
    final when = item.when == null ? 'Just now' : Dates.relative(item.when!);
    return switch (item) {
      _CopyItem() => 'Form copy · Last edited: $when',
      _FileItem(:final file) => '${_size(file.sizeBytes)} · Added: $when',
    };
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
