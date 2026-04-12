import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/exceptions/collection_exception.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/collection_detail_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:uuid/uuid.dart';

class CreateCollectionScreen extends ConsumerStatefulWidget {
  const CreateCollectionScreen({
    super.key,
    this.collection,
  });

  final Collection? collection;

  @override
  ConsumerState<CreateCollectionScreen> createState() =>
      _CreateCollectionScreenState();
}

class _CreateCollectionScreenState
    extends ConsumerState<CreateCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _notesController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  late CollectionType _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEditMode => widget.collection != null;

  @override
  void initState() {
    super.initState();
    final collection = widget.collection;
    _selectedType = collection?.type ?? CollectionType.personal;
    _nameController.text = collection?.name ?? '';
    _notesController.text = collection?.notes ?? '';
    _startDate = collection?.startDate;
    _endDate = collection?.endDate;
    _syncDateControllers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _notesController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = ref.watch(premiumCollectionAccessProvider);
    final inputFillColor = Colors.grey.shade50;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        debugPrint('CreateCollectionScreen back pressed, didPop: $didPop');
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Trip or Event' : 'Create Trip or Event',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        body: SafeArea(
          child: !hasAccess
              ? const _CollectionAccessDenied()
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.folder_copy_outlined,
                              size: 30,
                              color: AppColors.primaryNavy,
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create Trip or Event',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Organise receipts for trips, events, or projects',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _FormSection(
                        title: 'Trip or Event Basics',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Trip or event name'),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              textCapitalization: TextCapitalization.words,
                              decoration: _inputDecoration(
                                hintText: 'Enter trip or event name',
                                fillColor: inputFillColor,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Trip or event name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            const _FieldLabel('Type'),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _TypeSelectionCard(
                                    title: 'Personal',
                                    icon: Icons.person_outline,
                                    selected: _selectedType ==
                                        CollectionType.personal,
                                    onTap: _saving
                                        ? null
                                        : () => setState(
                                              () => _selectedType =
                                                  CollectionType.personal,
                                            ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TypeSelectionCard(
                                    title: 'Work',
                                    icon: Icons.work_outline,
                                    selected:
                                        _selectedType == CollectionType.work,
                                    onTap: _saving
                                        ? null
                                        : () => setState(
                                              () => _selectedType =
                                                  CollectionType.work,
                                            ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _FormSection(
                        title: 'Dates',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Start date (optional)'),
                            const SizedBox(height: 12),
                            _DateField(
                              controller: _startDateController,
                              label: 'Optional',
                              onTap: _saving
                                  ? null
                                  : () => _pickDate(
                                        initialDate: _startDate,
                                        onSelected: (value) {
                                          setState(() => _startDate = value);
                                          _syncDateControllers();
                                        },
                                      ),
                              onClear: _saving || _startDate == null
                                  ? null
                                  : () {
                                      setState(() => _startDate = null);
                                      _syncDateControllers();
                                    },
                              fillColor: inputFillColor,
                            ),
                            const SizedBox(height: 16),
                            const _FieldLabel('End date (optional)'),
                            const SizedBox(height: 12),
                            _DateField(
                              controller: _endDateController,
                              label: 'Optional',
                              onTap: _saving
                                  ? null
                                  : () => _pickDate(
                                        initialDate: _endDate ?? _startDate,
                                        firstDate: _startDate,
                                        onSelected: (value) {
                                          setState(() => _endDate = value);
                                          _syncDateControllers();
                                        },
                                      ),
                              onClear: _saving || _endDate == null
                                  ? null
                                  : () {
                                      setState(() => _endDate = null);
                                      _syncDateControllers();
                                    },
                              fillColor: inputFillColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _FormSection(
                        title: 'Notes',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Notes'),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notesController,
                              minLines: 4,
                              maxLines: 6,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _inputDecoration(
                                hintText: 'Optional',
                                fillColor: inputFillColor,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving ? null : _saveCollection,
                          child: Text(
                            _isEditMode
                                ? 'Save Changes'
                                : 'Create Trip or Event',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _pickDate({
    DateTime? initialDate,
    DateTime? firstDate,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? firstDate ?? now,
      firstDate: firstDate ?? DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );

    if (picked == null) return;
    onSelected(picked);
  }

  Future<void> _saveCollection() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    if (_endDate != null &&
        _startDate != null &&
        _endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date.')),
      );
      return;
    }

    final connectivity = ref.read(connectivityServiceProvider);
    if (!await ensureInternetConnection(context, connectivity)) {
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final trimmedName = _nameController.text.trim();
      final trimmedNotes = _notesController.text.trim();

      if (_isEditMode) {
        final existingCollection = widget.collection!;
        final updatedCollection = existingCollection.copyWith(
          name: trimmedName,
          type: _selectedType,
          startDate: _startDate,
          endDate: _endDate,
          notes: trimmedNotes.isEmpty ? null : trimmedNotes,
          updatedAt: now,
        );
        final updateCollection = ref.read(updateCollectionUseCaseProvider);
        await updateCollection(userId, updatedCollection);
      } else {
        final collection = Collection(
          id: const Uuid().v4(),
          name: trimmedName,
          type: _selectedType,
          startDate: _startDate,
          endDate: _endDate,
          notes: trimmedNotes.isEmpty ? null : trimmedNotes,
          status: CollectionStatus.active,
          createdAt: now,
          updatedAt: now,
        );
        final createCollection = ref.read(createCollectionUseCaseProvider);
        await createCollection(userId, collection);
      }

      if (!mounted) return;
      Navigator.pop(context);
    } on DuplicateActiveCollectionException {
      if (!mounted) return;
      final conflictingCollection = await _findConflictingActiveCollection(
        userId,
        _nameController.text,
      );
      if (!mounted) return;

      final action = await showDialog<_DuplicateCollectionDialogAction>(
        context: context,
        builder: (dialogContext) => _DuplicateCollectionDialog(
          collectionName: _nameController.text.trim(),
          hasExistingCollection: conflictingCollection != null,
        ),
      );
      if (!mounted) return;

      switch (action) {
        case _DuplicateCollectionDialogAction.openExisting:
          if (conflictingCollection != null) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CollectionDetailScreen(
                  collectionId: conflictingCollection.id,
                ),
              ),
            );
          }
        case _DuplicateCollectionDialogAction.rename:
          _nameFocusNode.requestFocus();
          _nameController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _nameController.text.length,
          );
        case _DuplicateCollectionDialogAction.cancel:
          Navigator.of(context).pop();
        case null:
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _syncDateControllers() {
    final formatter = DateFormat.yMMMd();
    _startDateController.text =
        _startDate == null ? '' : formatter.format(_startDate!);
    _endDateController.text =
        _endDate == null ? '' : formatter.format(_endDate!);
  }

  Future<Collection?> _findConflictingActiveCollection(
    String userId,
    String rawName,
  ) async {
    final normalizedName = rawName.trim().toLowerCase();
    final getCollections = ref.read(getCollectionsUseCaseProvider);
    final collections = await getCollections(userId);
    for (final collection in collections) {
      if (collection.status == CollectionStatus.active &&
          collection.name.trim().toLowerCase() == normalizedName) {
        return collection;
      }
    }
    return null;
  }
}

InputDecoration _inputDecoration({
  required String hintText,
  required Color fillColor,
  bool alignLabelWithHint = false,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.grey.shade300),
  );

  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    alignLabelWithHint: alignLabelWithHint,
    suffixIcon: suffixIcon,
    enabledBorder: border,
    border: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(
        color: AppColors.primaryNavy,
        width: 1.4,
      ),
    ),
  );
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

enum _DuplicateCollectionDialogAction {
  openExisting,
  rename,
  cancel,
}

class _DuplicateCollectionDialog extends StatelessWidget {
  const _DuplicateCollectionDialog({
    required this.collectionName,
    required this.hasExistingCollection,
  });

  final String collectionName;
  final bool hasExistingCollection;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Trip or event already exists'),
      content: Text(
        'You already have an active trip or event named "$collectionName".',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_DuplicateCollectionDialogAction.cancel);
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_DuplicateCollectionDialogAction.rename);
          },
          child: const Text('Rename trip or event'),
        ),
        if (hasExistingCollection)
          FilledButton(
            onPressed: () {
              Navigator.of(context)
                  .pop(_DuplicateCollectionDialogAction.openExisting);
            },
            child: const Text('Open existing trip or event'),
          ),
      ],
    );
  }
}

class _TypeSelectionCard extends StatelessWidget {
  const _TypeSelectionCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primaryNavy : Colors.grey.shade300;
    final backgroundColor =
        selected ? AppColors.primaryNavy.withValues(alpha: 0.08) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color:
                    selected ? AppColors.primaryNavy : AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? AppColors.primaryNavy : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.onTap,
    required this.onClear,
    required this.fillColor,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: _inputDecoration(
        hintText: label,
        fillColor: fillColor,
        suffixIcon: onClear == null
            ? const Icon(Icons.calendar_today_outlined)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.calendar_today_outlined),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CollectionAccessDenied extends StatelessWidget {
  const _CollectionAccessDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Trips & Events are available on an active trial or subscription.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
    );
  }
}
