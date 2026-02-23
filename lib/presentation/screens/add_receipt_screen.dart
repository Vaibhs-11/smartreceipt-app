import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receiptnest/core/constants/app_constants.dart';
import 'package:receiptnest/core/firebase/crashlytics_logger.dart';
import 'package:receiptnest/domain/entities/app_user.dart';
import 'package:receiptnest/domain/entities/subscription_entitlement.dart';
import 'package:receiptnest/domain/entities/receipt.dart'
    show Receipt, ReceiptItem;
import 'package:receiptnest/domain/exceptions/app_config_exception.dart';
import 'package:receiptnest/domain/policies/account_policies.dart';
import 'package:receiptnest/domain/entities/app_config.dart';
import 'package:receiptnest/presentation/providers/app_config_provider.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:receiptnest/domain/entities/ocr_result.dart' show OcrResult;
import 'package:receiptnest/data/services/image_processing/image_normalization.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:receiptnest/services/receipt_image_source_service.dart';
import 'package:receiptnest/presentation/screens/trial_ended_gate_screen.dart';
import 'package:receiptnest/presentation/screens/purchase_screen.dart';
import 'package:receiptnest/presentation/screens/home_screen.dart';
import 'package:receiptnest/presentation/utils/connectivity_guard.dart';
import 'package:receiptnest/presentation/utils/root_scaffold_messenger.dart';

class UploadedFile {
  final String downloadUrl;
  final String gcsUri;
  UploadedFile({required this.downloadUrl, required this.gcsUri});
}

class OcrNoTextException implements Exception {
  final String message;
  OcrNoTextException(this.message);
}

enum AddReceiptInitialAction { pickGallery, pickFiles }

enum _NonReceiptAction { camera, gallery, files, none }

class AddReceiptScreenArgs {
  final String? initialImagePath;
  final AddReceiptInitialAction? initialAction;

  const AddReceiptScreenArgs({this.initialImagePath, this.initialAction});
}

class AddReceiptScreen extends ConsumerStatefulWidget {
  final String? initialImagePath;
  final AddReceiptInitialAction? initialAction;
  final Receipt? existingReceipt;

  const AddReceiptScreen(
      {super.key,
      this.initialImagePath,
      this.initialAction,
      this.existingReceipt});

  @override
  ConsumerState<AddReceiptScreen> createState() => _AddReceiptScreenState();
}

class _AddReceiptScreenState extends ConsumerState<AddReceiptScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Basic controllers
  final TextEditingController _storeCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();

  // New-item controllers (kept only for the "add row")
  final TextEditingController _itemNameCtrl = TextEditingController();
  final TextEditingController _itemPriceCtrl = TextEditingController();

  final List<TextEditingController> _itemNameCtrls = [];
  final List<TextEditingController> _itemPriceCtrls = [];

  String? _currentReceiptId;
  List<ReceiptItem> _items = [];

  final List<String> _currencyOptions =
      List<String>.from(AppConstants.supportedCurrencies);
  String _currency = AppConstants.supportedCurrencies.first;
  DateTime _date = DateTime.now();
  String? _originalImagePath;
  String? _processedImagePath;
  String? _imageProcessingStatus;
  String? _extractedText;
  bool _isLoading = false;
  bool _receiptRejected = false;
  // Tracks "not a receipt" reason; currently unused in UI but kept for future UX.
  // ignore: unused_field
  String? _receiptRejectionReason;
  List<String> _searchKeywords = const [];
  String? _normalizedBrand;
  String? _category;
  bool _initialArgsHandled = false;
  bool _storeEdited = false;
  bool _totalEdited = false;
  bool _dateEdited = false;
  bool _currencyEdited = false;
  bool _isExitingAfterNoInternet = false;
  late final bool _isEditMode;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.existingReceipt != null;
    _dateCtrl.text = DateFormat.yMMMd().format(_date);
    if (_isEditMode) {
      _populateFromExistingReceipt(widget.existingReceipt!);
    }
    // 🔥 Warm critical providers early
    Future.microtask(() {
      ref.read(appConfigProvider.future);
    });
    if (!_isEditMode) {
      _handleInitialArgs();
    }
    _scheduleConnectivityCheck();
  }

  @override
  void didUpdateWidget(covariant AddReceiptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isEditMode) return;
    if (widget.initialImagePath != oldWidget.initialImagePath ||
        widget.initialAction != oldWidget.initialAction) {
      _initialArgsHandled = false;
      _handleInitialArgs();
    }
  }

  void _populateFromExistingReceipt(Receipt receipt) {
    _currentReceiptId = receipt.id;
    _storeCtrl.text = receipt.storeName;
    _totalCtrl.text = receipt.total.toStringAsFixed(2);
    _notesCtrl.text = receipt.notes ?? '';
    _date = receipt.date;
    _dateCtrl.text = DateFormat.yMMMd().format(_date);
    _currency = receipt.currency;
    if (!_currencyOptions.contains(_currency)) {
      _currencyOptions.add(_currency);
    }
    _items = List<ReceiptItem>.from(receipt.items);
    _resetItemControllers(_items);
    _originalImagePath = receipt.originalImagePath ?? receipt.imagePath;
    _processedImagePath = receipt.processedImagePath;
    _imageProcessingStatus = receipt.imageProcessingStatus;
    _extractedText = receipt.extractedText;
    _searchKeywords = List<String>.from(receipt.searchKeywords);
    _normalizedBrand = receipt.normalizedBrand;
    _category = receipt.metadata?['category'] as String?;
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    _dateCtrl.dispose();
    _itemNameCtrl.dispose();
    _itemPriceCtrl.dispose();
    for (final controller in _itemNameCtrls) {
      controller.dispose();
    }
    for (final controller in _itemPriceCtrls) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleConnectivityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final connectivity = ref.read(connectivityServiceProvider);
      final ok = await ensureInternetConnection(context, connectivity);
      if (!mounted) return;
      if (!ok) {
        await _exitAfterNoInternet();
      }
    });
  }

  Future<void> _exitAfterNoInternet() async {
    if (!mounted || _isExitingAfterNoInternet) return;
    _isExitingAfterNoInternet = true;

    final navigator = Navigator.of(context);

    try {
      final popped = await navigator.maybePop();
      if (!popped && mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } finally {
      // Reset only after navigation frame completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isExitingAfterNoInternet = false;
      });
    }
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                // Name field
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _itemNameCtrls[index],
                    decoration: const InputDecoration(labelText: 'Item name'),
                    onEditingComplete: () => _commitItemEdit(index),
                  ),
                ),
                const SizedBox(width: 8),
                // Price field
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _itemPriceCtrls[index],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Price',
                      hintText: item.price == null ? '-' : null,
                      hintStyle: item.price == null
                          ? const TextStyle(color: Colors.red)
                          : null,
                      helperText: item.price == null ? 'Price missing' : null,
                      helperStyle: item.price == null
                          ? const TextStyle(color: Colors.red)
                          : null,
                      enabledBorder: item.price == null
                          ? const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.red),
                            )
                          : null,
                      focusedBorder: item.price == null
                          ? const OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: Colors.red, width: 2),
                            )
                          : null,
                    ),
                    style: TextStyle(
                      color: item.price == null ? Colors.red : null,
                    ),
                    onEditingComplete: () => _commitItemEdit(index),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              value: item.taxClaimable,
              onChanged: (val) {
                _commitItemEdit(
                  index,
                  taxClaimable: val ?? false,
                  commitText: false,
                );
              },
              title: const Text('Mark as tax claimable'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  void _resetItemControllers(List<ReceiptItem> items) {
    for (final controller in _itemNameCtrls) {
      controller.dispose();
    }
    for (final controller in _itemPriceCtrls) {
      controller.dispose();
    }
    _itemNameCtrls.clear();
    _itemPriceCtrls.clear();
    for (final item in items) {
      _itemNameCtrls.add(TextEditingController(text: item.name));
      _itemPriceCtrls.add(
        TextEditingController(
          text: item.price?.toStringAsFixed(2) ?? '',
        ),
      );
    }
  }

  void _commitItemEdit(
    int index, {
    bool? taxClaimable,
    bool commitText = true,
  }) {
    if (index < 0 ||
        index >= _items.length ||
        index >= _itemNameCtrls.length ||
        index >= _itemPriceCtrls.length) {
      return;
    }
    setState(() {
      final current = _items[index];
      final name =
          commitText ? _itemNameCtrls[index].text.trim() : current.name;
      final rawPrice = commitText ? _itemPriceCtrls[index].text.trim() : null;
      final parsedPrice = rawPrice == null || rawPrice.isEmpty
          ? null
          : double.tryParse(rawPrice);
      _items[index] = current.copyWith(
        name: name,
        price: commitText ? parsedPrice : current.price,
        taxClaimable: taxClaimable ?? current.taxClaimable,
      );
    });
  }

  void _syncItemsFromControllers() {
    final count = math.min(
      _items.length,
      math.min(_itemNameCtrls.length, _itemPriceCtrls.length),
    );
    for (int i = 0; i < count; i++) {
      _commitItemEdit(i);
    }
  }

  Map<String, Object?>? _buildMetadata() {
    final category = _category?.trim();
    if (category == null || category.isEmpty) return null;
    return {'category': category};
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;

    final String formatted = DateFormat.yMMMd().format(picked);
    setState(() {
      controller.text = formatted;
      _date = picked;
      _dateEdited = true;
    });
  }

  void _handleInitialArgs() {
    if (_initialArgsHandled) return;

    final path = widget.initialImagePath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (!file.existsSync()) {
        debugPrint('Initial image path does not exist: $path');
      } else {
        _initialArgsHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _startReceiptProcessing(file);
        });
        return;
      }
    }

    final action = widget.initialAction;
    if (action != null) {
      _initialArgsHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        switch (action) {
          case AddReceiptInitialAction.pickGallery:
            await _pickFromGallery();
            break;
          case AddReceiptInitialAction.pickFiles:
            await _pickFileFromPicker();
            break;
        }
      });
    }
  }

  Future<bool> _ensurePreconditions() async {
    final connectivity = ref.read(connectivityServiceProvider);
    if (!await ensureInternetConnection(context, connectivity)) {
      await _exitAfterNoInternet();
      return false;
    }
    if (!await _ensureCanAddReceipt()) return false;
    return true;
  }

  Future<bool> _ensureCanAddReceipt() async {
    final userRepo = ref.read(userRepositoryProvider);
    final receiptRepo = ref.read(receiptRepositoryProviderOverride);
    final now = DateTime.now().toUtc();
    try {
      final appConfig = await ref.read(appConfigProvider.future);
      final profile = await userRepo.getCurrentUserProfile();
      if (profile == null) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
        return false;
      }
      final receiptCount = await receiptRepo.getReceiptCount();

      final allowed =
          AccountPolicies.canAddReceipt(profile, receiptCount, now, appConfig);
      if (allowed) return true;

      if (AccountPolicies.isExpired(profile, now) &&
          receiptCount <= appConfig.freeReceiptLimit) {
        await userRepo.clearDowngradeRequired();
        final refreshed = await userRepo.getCurrentUserProfile();
        if (refreshed == null) {
          if (mounted) {
            Navigator.of(context).maybePop();
          }
          return false;
        }
        if (AccountPolicies.canAddReceipt(
          refreshed,
          receiptCount,
          now,
          appConfig,
        )) {
          return true;
        }
      }

      final needsGate = AccountPolicies.downgradeRequired(
        profile,
        receiptCount,
        now,
        appConfig,
      );

      if (needsGate && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TrialEndedGateScreen(
              isSubscriptionEnded:
                  profile.subscriptionStatus == SubscriptionStatus.expired,
              receiptCount: receiptCount,
            ),
          ),
          (_) => false,
        );
        return false;
      }

      if (mounted) {
        await _showLimitDialog(
          profile,
          receiptCount,
          appConfig,
          AccountPolicies.isSubscriptionExpired(profile),
        );
      }
      return false;
    } on AppConfigUnavailableException {
      return _handleAppConfigUnavailable();
    } catch (e, s) {
      if (isNetworkException(e)) {
        await CrashlyticsLogger.recordNonFatal(
          reason: 'NETWORK_UNAVAILABLE',
          error: e,
          stackTrace: s,
        );
        if (mounted) {
          await showNoInternetDialog(context);
          await _exitAfterNoInternet();
        }
        return false;
      }

      // Any other config-related failure → fail closed
      await CrashlyticsLogger.recordNonFatal(
        reason: 'APP_CONFIG_LOAD_FAILED',
        error: e,
        stackTrace: s,
      );
      return _handleAppConfigUnavailable();
    }
  }

  Future<void> _showLimitDialog(
    AppUserProfile profile,
    int receiptCount,
    AppConfig appConfig,
    bool subscriptionExpired,
  ) async {
    final isTrialActive =
        AccountPolicies.isTrialActive(profile, DateTime.now().toUtc());
    final bool showExpiredMessage =
        subscriptionExpired && receiptCount > appConfig.freeReceiptLimit;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          showExpiredMessage
              ? 'Subscription expired'
              : 'Free plan limit reached',
        ),
        content: Text(
          showExpiredMessage
              ? 'Your subscription has expired. Please delete receipts '
                  'to continue or upgrade.'
              : 'You have $receiptCount receipts. Free plan allows up to '
                  '${appConfig.freeReceiptLimit}. '
                  '${isTrialActive ? 'Upgrade to keep adding more.' : 'Start a free 7-day trial or upgrade to keep adding more.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (!showExpiredMessage &&
              !isTrialActive &&
              profile.trialUsed != true)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _startTrial();
              },
              child: const Text('Start trial'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PurchaseScreen()),
              );
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrial() async {
    final userRepo = ref.read(userRepositoryProvider);
    final connectivity = ref.read(connectivityServiceProvider);
    if (!await ensureInternetConnection(context, connectivity)) {
      await _exitAfterNoInternet();
      return;
    }
    try {
      await userRepo.startTrial();
    } catch (e) {
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
          await _exitAfterNoInternet();
        }
        return;
      }
      if (mounted) {
        showRootSnackBar(
          SnackBar(content: Text('Could not start trial: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    showRootSnackBar(
      const SnackBar(content: Text('Trial started. You can now add receipts.')),
    );
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final addReceipt =
        _isEditMode ? null : ref.read(addReceiptUseCaseProviderOverride);
    final imageProcessor =
        _isEditMode ? null : ref.read(receiptImageProcessingServiceProvider);
    final navigator = Navigator.of(context);

    if (mounted) {
      setState(() => _isLoading = true);
    } else {
      _isLoading = true;
    }

    try {
      if (!_isEditMode && !await _ensurePreconditions()) return;
      if (_receiptRejected) return;
      if (!(_formKey.currentState?.validate() ?? false)) return;

      _syncItemsFromControllers();

      final double total = double.tryParse(_totalCtrl.text.trim()) ?? 0;

      final receipt = Receipt(
        id: _ensureReceiptIdForSave(),
        storeName: _storeCtrl.text.trim(),
        date: _date,
        total: total,
        currency: _currency,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        imagePath: _originalImagePath,
        originalImagePath: _originalImagePath,
        processedImagePath: _processedImagePath,
        imageProcessingStatus: _imageProcessingStatus,
        extractedText: _extractedText,
        items: _items,
        searchKeywords: _searchKeywords,
        normalizedBrand: _normalizedBrand,
        metadata: _buildMetadata(),
      );

      try {
        if (_isEditMode) {
          final repo = ref.read(receiptRepositoryProviderOverride);
          await repo.updateReceipt(receipt);
        } else {
          await addReceipt!(receipt);
        }
      } catch (e) {
        if (e is AppConfigUnavailableException) {
          await _handleAppConfigUnavailable();
          return;
        }
        if (isNetworkException(e)) {
          if (mounted) {
            await showNoInternetDialog(context);
            await _exitAfterNoInternet();
          }
          return;
        }
        if (!mounted) return;
        showRootSnackBar(
          const SnackBar(
            content: Text('Could not save receipt. Please try again.'),
          ),
        );
        return;
      }
      if (!_isEditMode &&
          _originalImagePath != null &&
          _originalImagePath!.isNotEmpty) {
        unawaited(imageProcessor!.enqueueEnhancement(
          receiptId: _activeReceiptId,
          originalImagePath: _originalImagePath!,
        ));
      }

      if (mounted) {
        navigator.pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  Future<UploadedFile?> _uploadFileToStorage(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Cannot upload file, user not logged in.");
      return null;
    }
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("receipts")
          .child(user.uid)
          .child(_activeReceiptId)
          .child(file.path.split('/').last);

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();
      final gcsUri = 'gs://${storageRef.bucket}/${storageRef.fullPath}';
      return UploadedFile(downloadUrl: downloadUrl, gcsUri: gcsUri);
    } catch (e) {
      if (isNetworkException(e)) {
        rethrow;
      }
      debugPrint("Upload failed: $e");
      return null;
    }
  }

  Future<UploadedFile?> _uploadBytesToStorage(
    Uint8List bytes, {
    required String fileName,
    required String contentType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Cannot upload file, user not logged in.");
      return null;
    }
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("receipts")
          .child(user.uid)
          .child(_activeReceiptId)
          .child(fileName);

      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final downloadUrl = await storageRef.getDownloadURL();
      final gcsUri = 'gs://${storageRef.bucket}/${storageRef.fullPath}';
      return UploadedFile(downloadUrl: downloadUrl, gcsUri: gcsUri);
    } catch (e) {
      if (isNetworkException(e)) {
        rethrow;
      }
      debugPrint("Upload failed: $e");
      return null;
    }
  }

  void _handleOcrResult(OcrResult result, {String? uploadedUrl}) {
    if (!mounted) return;
    setState(() {
      _receiptRejected = false;
      _receiptRejectionReason = null;
      if (uploadedUrl != null) {
        _originalImagePath = uploadedUrl;
        _processedImagePath = null;
        _imageProcessingStatus = 'pending';
      }
      if (!_storeEdited) {
        _storeCtrl.text = result.storeName;
      }
      if (!_totalEdited) {
        _totalCtrl.text = result.total.toStringAsFixed(2);
      }
      if (!_dateEdited) {
        _date = result.date;
        _dateCtrl.text = DateFormat.yMMMd().format(_date);
      }

      final String? parsedCurrency = result.currency?.trim().toUpperCase();
      if (parsedCurrency != null && parsedCurrency.isNotEmpty) {
        if (!_currencyOptions.contains(parsedCurrency)) {
          _currencyOptions.add(parsedCurrency);
        }
        if (!_currencyEdited) {
          _currency = parsedCurrency;
        }
      }

      _searchKeywords = List<String>.from(result.searchKeywords);
      _normalizedBrand = result.normalizedBrand;
      _category = result.category;
      _items = result.toReceiptItems();
      _resetItemControllers(_items);

      _extractedText = 'Store: ${result.storeName}\n'
          'Date: ${DateFormat.yMMMd().format(result.date)}\n'
          'Total: ${result.total.toStringAsFixed(2)}\n\n'
          'Raw Text:\n${result.rawText}';
    });
  }

  Future<bool> _handleAppConfigUnavailable() async {
    if (!mounted) return false;
    final retry = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('App settings unavailable'),
        content: const Text('Unable to load receipt limits. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (retry == true) {
      ref.refresh(appConfigProvider);
      return _ensureCanAddReceipt();
    }
    return false;
  }

  Future<_NonReceiptAction?> _handleNonReceipt(OcrResult result) async {
    if (!mounted) return null;
    setState(() {
      _receiptRejected = true;
      _receiptRejectionReason = result.receiptRejectionReason;
    });
    return _showNotReceiptDialog(result.receiptRejectionReason);
  }

  Future<bool> _maybeAcceptReceiptResult(
    OcrResult result, {
    String? uploadedUrl,
  }) async {
    if (!result.isReceipt) {
      final nextAction = await _handleNonReceipt(result);
      if (nextAction != null &&
          nextAction != _NonReceiptAction.none &&
          mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          switch (nextAction) {
            case _NonReceiptAction.camera:
              _handleCameraCapture();
              break;
            case _NonReceiptAction.gallery:
              _handleGalleryPick();
              break;
            case _NonReceiptAction.files:
              _pickFile();
              break;
            case _NonReceiptAction.none:
              break;
          }
        });
      }
      return false;
    }

    _handleOcrResult(result, uploadedUrl: uploadedUrl);
    return true;
  }

  Future<_NonReceiptAction?> _showNotReceiptDialog(String? reason) {
    if (!mounted) return Future.value(_NonReceiptAction.none);
    return showDialog<_NonReceiptAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Not a receipt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sorry — we couldn’t confidently identify this image as a receipt, so we’re unable to store it. Please try uploading a clearer photo of a receipt.',
              ),
              if (reason != null && reason.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Details: $reason',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.none),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.files),
              child: const Text('Pick from Files'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.gallery),
              child: const Text('Pick from Gallery'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.camera),
              child: const Text('Retry with Camera'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startReceiptProcessing(File file) async {
    if (_isLoading) return;
    if (!await _ensurePreconditions()) return;
    _currentReceiptId = const Uuid().v4();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _receiptRejected = false;
        _receiptRejectionReason = null;
      });
    } else {
      _isLoading = true;
      _receiptRejected = false;
      _receiptRejectionReason = null;
    }
    try {
      await _processAndUploadFile(file);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

  String _ensureReceiptIdForSave() {
    final existing = _currentReceiptId;
    if (existing != null) return existing;
    final created = const Uuid().v4();
    _currentReceiptId = created;
    return created;
  }

  String get _activeReceiptId {
    final id = _currentReceiptId;
    if (id == null) {
      throw StateError('Receipt ID not initialized');
    }
    return id;
  }

  Future<void> _processAndUploadFile(File file) async {
    String? fileExtension;
    int? normalizedWidth;
    int? normalizedHeight;

    try {
      final String lowerPath = file.path.toLowerCase();
      fileExtension =
          lowerPath.contains('.') ? lowerPath.split('.').last : null;
      final bool isPdf = lowerPath.endsWith('.pdf');
      final cloudOcr = ref.read(cloudOcrServiceProvider);
      final chatGpt = ref.read(chatGptOcrServiceProvider);

      if (!isPdf) {
        // Vision OCR is sensitive to orientation/DPI; normalization keeps results consistent across platforms.
        final normalizationResult = await normalizeReceiptImage(file);
        UploadedFile? uploadResult;
        if (normalizationResult.normalized) {
          normalizedWidth = normalizationResult.width;
          normalizedHeight = normalizationResult.height;
          final normalizedBytes = await normalizationResult.file.readAsBytes();
          uploadResult = await _uploadBytesToStorage(
            normalizedBytes,
            fileName: '${_activeReceiptId}_normalized.jpg',
            contentType: 'image/jpeg',
          );
        } else {
          uploadResult = await _uploadFileToStorage(normalizationResult.file);
        }
        if (uploadResult == null) throw Exception('File upload failed.');

        final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
        // Image OCR must always happen before GPT parsing; GPT is not an OCR engine.
        final visionResult = await cloudOcr.parseImage(gcsPath);
        final rawText = visionResult.rawText;
        if (rawText.trim().isEmpty) {
          throw OcrNoTextException("No text detected in image");
        }
        final result = await chatGpt.parseRawText(rawText);
        await _maybeAcceptReceiptResult(
          result,
          uploadedUrl: uploadResult.downloadUrl,
        );
        return;
      }

      // Try extracting selectable text from PDF
      String extractedText = '';
      try {
        final Uint8List bytes = await file.readAsBytes();
        final sfpdf.PdfDocument document = sfpdf.PdfDocument(inputBytes: bytes);
        final sfpdf.PdfTextExtractor extractor =
            sfpdf.PdfTextExtractor(document);

        final buffer = StringBuffer();
        for (int i = 0; i < document.pages.count; i++) {
          final pageText = extractor.extractText(
            startPageIndex: i,
            endPageIndex: i,
          );
          if (pageText != null && pageText.trim().isNotEmpty) {
            buffer.writeln(pageText);
          }
        }

        extractedText = buffer.toString();
        document.dispose();
      } catch (e) {
        debugPrint('PDF text extraction failed locally: $e');
      }

      if (extractedText.trim().isNotEmpty) {
        final uploadResult = await _uploadFileToStorage(file);
        if (uploadResult == null) throw Exception('File upload failed.');

        final parsed = await chatGpt.parseRawText(extractedText);
        await _maybeAcceptReceiptResult(
          parsed,
          uploadedUrl: uploadResult.downloadUrl,
        );
        return;
      }

      // If PDF has no selectable text → render to image
      File? tempImageFile;
      try {
        final pdfx.PdfDocument pdf = await pdfx.PdfDocument.openFile(file.path);
        final pdfx.PdfPage page = await pdf.getPage(1);

        final pdfx.PdfPageImage? pageImage = await page.render(
          width: page.width,
          height: page.height,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );

        if (pageImage == null || pageImage.bytes.isEmpty) {
          await page.close();
          await pdf.close();
          throw Exception('Failed to render PDF page to image');
        }

        final Uint8List jpgBytes = pageImage.bytes;
        await page.close();
        await pdf.close();

        final jpgPath = file.path
            .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '_p1.jpg');

        tempImageFile = File(jpgPath);
        await tempImageFile.writeAsBytes(jpgBytes, flush: true);
      } catch (e) {
        debugPrint('Failed to render PDF to image: $e');
      }

      if (tempImageFile == null || !(await tempImageFile.exists())) {
        throw Exception('Failed to convert PDF to image for OCR');
      }

      final uploadResult = await _uploadFileToStorage(tempImageFile);
      if (uploadResult == null) throw Exception('File upload failed.');

      final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
      // Image OCR must always happen before GPT parsing; GPT is not an OCR engine.
      final visionResult = await cloudOcr.parseImage(gcsPath);
      final rawText = visionResult.rawText;
      if (rawText.trim().isEmpty) {
        throw OcrNoTextException("No text detected in image");
      }
      final result = await chatGpt.parseRawText(rawText);
      await _maybeAcceptReceiptResult(
        result,
        uploadedUrl: uploadResult.downloadUrl,
      );
    } catch (e, s) {
      if (isNetworkException(e)) {
        if (mounted) {
          await showNoInternetDialog(context);
          await _exitAfterNoInternet();
        }
        return;
      }
      if (e is OcrNoTextException) {
        FirebaseCrashlytics.instance.setCustomKey(
          'platform',
          Platform.operatingSystem,
        );
        if (fileExtension != null && fileExtension.isNotEmpty) {
          FirebaseCrashlytics.instance.setCustomKey(
            'fileExtension',
            fileExtension,
          );
        }
        if (normalizedWidth != null) {
          FirebaseCrashlytics.instance.setCustomKey(
            'imageWidth',
            normalizedWidth,
          );
        }
        if (normalizedHeight != null) {
          FirebaseCrashlytics.instance.setCustomKey(
            'imageHeight',
            normalizedHeight,
          );
        }
        FirebaseCrashlytics.instance.recordError(
          e,
          s,
          fatal: false,
          reason: "OCR_NO_TEXT",
        );
        if (mounted) {
          showRootSnackBar(
            const SnackBar(
              content: Text(
                'We couldn’t read any text from this image. '
                'Please try a clearer photo of the receipt with good lighting.',
              ),
            ),
          );
        }
        return;
      }
      debugPrint('Error processing file: $e\n$s');
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        fatal: false,
        reason: 'PROCESS_FILE_ERROR',
      );
      if (mounted) {
        showRootSnackBar(
          const SnackBar(
            content: Text(
              'We couldn’t process this file. Please try again with a different '
              'image or a clearer photo of your receipt.',
            ),
          ),
        );
      }
    } finally {}
  }

  Future<void> _handleCameraCapture() async {
    await _pickFromCamera();
  }

  Future<void> _pickFromCamera() async {
    final service = ref.read(receiptImageSourceServiceProvider);
    final result = await service.pickFromCamera();
    await _handleImageSourceResult(result, fromCamera: true);
  }

  Future<void> _handleGalleryPick() async {
    await _pickFromGallery();
  }

  Future<void> _pickFromGallery() async {
    final service = ref.read(receiptImageSourceServiceProvider);
    final result = await service.pickFromGallery();
    await _handleImageSourceResult(result);
  }

  Future<void> _handleImageSourceResult(
    ReceiptImagePickResult result, {
    bool fromCamera = false,
  }) async {
    final imageService = ref.read(receiptImageSourceServiceProvider);

    if (result.file != null) {
      await _startReceiptProcessing(result.file!);
      return;
    }

    final failure = result.failure;
    if (failure == null || !mounted) return;

    if (fromCamera) {
      if (failure.code == ReceiptImageSourceError.permissionDenied) {
        _showImageSourceError(failure);
        return;
      }

      final selection = await imageService.showCameraFallbackDialog(context);
      if (!mounted || selection == null) return;
      switch (selection) {
        case CameraFallbackSelection.gallery:
          await _handleGalleryPick();
          break;
        case CameraFallbackSelection.files:
          await _pickFile();
          break;
      }
      return;
    }

    _showImageSourceError(failure);
  }

  void _showImageSourceError(ReceiptImageSourceFailure failure) {
    if (!mounted) return;
    showRootSnackBar(
      SnackBar(content: Text(failure.message)),
    );
  }

  Future<void> _pickFile() async {
    await _pickFileFromPicker();
  }

  Future<void> _pickFileFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    await _startReceiptProcessing(file);
  }

  Future<void> _showUploadOptions() async {
    if (!await _ensurePreconditions()) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pick from Gallery'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Pick from Files'),
                onTap: () => Navigator.of(context).pop('files'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    if (result == 'gallery') {
      await _handleGalleryPick();
    } else if (result == 'files') {
      await _pickFile();
    }
  }

  void _addNewItemFromInputs() {
    final name = _itemNameCtrl.text.trim();
    final price = double.tryParse(_itemPriceCtrl.text.trim());
    if (name.isNotEmpty && price != null) {
      setState(() {
        _items.add(ReceiptItem(name: name, price: price, taxClaimable: false));
        _itemNameCtrls.add(TextEditingController(text: name));
        _itemPriceCtrls
            .add(TextEditingController(text: price.toStringAsFixed(2)));
        _itemNameCtrl.clear();
        _itemPriceCtrl.clear();
      });

      // After a new item is added, scroll to bottom so user can see it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 150,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // bottom padding to lift Save button above keyboard when open
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final double bottomPadding = math.max(bottomInset, 12);

    final profileAsync = ref.watch(userProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (isNetworkException(e)) {
            await showNoInternetDialog(context);
            await _exitAfterNoInternet();
          }
        });
        return const Scaffold(
          body: Center(child: Text('Unable to load profile.')),
        );
      },
      data: (profile) {
        if (profile == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).maybePop();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar:
              AppBar(title: Text(_isEditMode ? 'Edit Receipt' : 'Add Receipt')),
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              SafeArea(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_originalImagePath != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Selected image: $_originalImagePath',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        TextFormField(
                          controller: _storeCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Store name'),
                          onChanged: (_) => _storeEdited = true,
                          validator: (String? v) =>
                              v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _dateCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(labelText: 'Date'),
                          onTap: () => _pickDate(_dateCtrl),
                        ),
                        if (!_isEditMode) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () => _handleCameraCapture(),
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  label: const Text('Capture'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _isLoading ? null : _showUploadOptions,
                                  icon: const Icon(Icons.upload),
                                  label: const Text('Upload'),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextFormField(
                                controller: _totalCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Total amount'),
                                onChanged: (_) => _totalEdited = true,
                                validator: (String? v) =>
                                    (double.tryParse(v ?? '') == null)
                                        ? 'Enter valid number'
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: _currency,
                              onChanged: (String? v) => setState(() {
                                _currencyEdited = true;
                                _currency = v ?? _currency;
                              }),
                              items: _currencyOptions
                                  .map((String c) => DropdownMenuItem<String>(
                                      value: c, child: Text(c)))
                                  .toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Notes (optional)'),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 20),
                        const Text('Items',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Review items carefully. Edit names/prices if needed.\n'
                            'Tick the checkbox for tax claimable purchases.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Build item cards
                        ..._items.asMap().entries.map((entry) {
                          final index = entry.key;
                          return _buildItemCard(index);
                        }).toList(),

                        const SizedBox(height: 12),
                        // Add new item row
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _itemNameCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Item name'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _itemPriceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration:
                                    const InputDecoration(labelText: 'Price'),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle,
                                  color: Colors.green),
                              onPressed: _addNewItemFromInputs,
                            ),
                          ],
                        ),
                        const SizedBox(
                            height: 100), // spacer so last row not hidden
                      ],
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black.withOpacity(0.45),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || _receiptRejected ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_isLoading
                      ? 'Saving…'
                      : (_isEditMode ? 'Update' : 'Save')),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
