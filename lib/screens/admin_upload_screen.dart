import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/book_search_index.dart';
import '../services/libation_import_helper.dart';
import '../widgets/absorb_page_header.dart';
import '../widgets/overlay_toast.dart';
import '../widgets/stackable_sheet.dart';

typedef UploadFilePicker = Future<List<MediaUploadFile>?> Function();
typedef UploadDirectoryPicker = Future<String?> Function();
typedef UploadExecutablePicker = Future<String?> Function();
typedef LibationDirectoryScanner =
    Future<List<LibationBookCandidate>> Function(String directoryPath);
typedef LibationExecutableLauncher =
    Future<bool> Function(String executablePath);
typedef UploadPathChecker =
    Future<UploadPathCheckResult> Function(String directory, String folderPath);
typedef MediaUploader =
    Future<MediaUploadResult> Function(
      MediaUploadRequest request, {
      void Function(int sentBytes, int totalBytes)? onProgress,
    });
typedef BookMetadataSearcher =
    Future<List<Map<String, dynamic>>> Function({
      required String title,
      String? author,
      required String provider,
    });
typedef LibrarySearcher =
    Future<Map<String, dynamic>?> Function(String libraryId, String query);

class AdminUploadScreen extends StatefulWidget {
  static const titleFieldKey = Key('adminUploadTitleField');
  static const authorFieldKey = Key('adminUploadAuthorField');
  static const seriesFieldKey = Key('adminUploadSeriesField');
  static const libraryFieldKey = Key('adminUploadLibraryField');
  static const folderFieldKey = Key('adminUploadFolderField');
  static const mediaTypeKey = Key('adminUploadMediaType');
  static const autoMetadataKey = Key('adminUploadAutoMetadata');
  static const metadataProviderKey = Key('adminUploadMetadataProvider');
  static const chooseFilesKey = Key('adminUploadChooseFiles');
  static const submitKey = Key('adminUploadSubmit');
  static const permissionBannerKey = Key('adminUploadPermissionBanner');
  static const libationGuideKey = Key('libationImportGuide');
  static const libationFilesKey = Key('libationImportFiles');
  static const libationFolderKey = Key('libationImportFolder');
  static const libationLaunchKey = Key('libationImportLaunch');
  static const libationSetAppKey = Key('libationImportSetApp');
  static const libationSetOutputFolderKey = Key(
    'libationImportSetOutputFolder',
  );
  static const libationScanProgressKey = Key('libationImportScanProgress');
  static const libationScanOutputFolderKey = Key(
    'libationImportScanOutputFolder',
  );
  static const libationReviewNewKey = Key('libationImportReviewNew');
  static const libationPickerSearchKey = Key('libationImportPickerSearch');
  static const libationDuplicateWarningKey = Key(
    'libationImportDuplicateWarning',
  );

  final List<dynamic> libraries;
  final String? initialLibraryId;
  final ApiService? apiService;
  final bool canUpload;
  final bool initialLibationExpanded;
  final VoidCallback? onUploadComplete;
  final UploadFilePicker? filePicker;
  final UploadDirectoryPicker? directoryPicker;
  final UploadExecutablePicker? executablePicker;
  final LibationDirectoryScanner? directoryScanner;
  final LibationExecutableLauncher? executableLauncher;
  final bool? showDesktopLibationControls;
  final UploadPathChecker? pathChecker;
  final MediaUploader? uploader;
  final BookMetadataSearcher? metadataSearcher;
  final LibrarySearcher? librarySearcher;
  final VoidCallback? onNavigationGuardChanged;

  /// Overrides "now" for new-download detection in tests.
  final DateTime Function()? clock;

  const AdminUploadScreen({
    super.key,
    required this.libraries,
    this.initialLibraryId,
    this.apiService,
    this.canUpload = true,
    this.initialLibationExpanded = false,
    this.onUploadComplete,
    this.filePicker,
    this.directoryPicker,
    this.executablePicker,
    this.directoryScanner,
    this.executableLauncher,
    this.showDesktopLibationControls,
    this.pathChecker,
    this.uploader,
    this.metadataSearcher,
    this.librarySearcher,
    this.onNavigationGuardChanged,
    this.clock,
  });

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  static const _audioExtensions = kLibationAudioExtensions;
  static const _ebookExtensions = <String>{
    'epub',
    'pdf',
    'mobi',
    'azw3',
    'cbr',
    'cbz',
  };
  static const _otherExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
    'nfo',
    'txt',
    'opf',
    'abs',
    'xml',
    'json',
  };
  static const _supportedExtensions = <String>{
    ..._audioExtensions,
    ..._ebookExtensions,
    ..._otherExtensions,
  };
  // Export handoff only: never select Libation account/configuration files.
  static const _libationExportExtensions = kLibationExportExtensions;

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _series = TextEditingController();

  List<Map<String, dynamic>> _libraries = [];
  bool _loadingLibraries = false;
  String? _selectedLibraryId;
  String? _selectedFolderId;
  List<MediaUploadFile> _files = [];
  bool _uploading = false;
  bool _autoFetchMetadata = false;
  bool _metadataSearching = false;
  bool _indexing = false;
  List<String> _metadataProviders = [];
  String _metadataProvider = 'audible';
  String? _lastMetadataQuery;
  int _metadataRequestId = 0;
  double? _progress;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  // A book already on the server whose folder the files should join. The
  // server only takes author, series and title, so they are filled from the
  // book's real folder path and the fields lock until it is cleared.
  _ExistingBook? _existingTarget;

  Future<void> _pickExistingBook() async {
    final api = widget.apiService;
    final libraryId = _selectedLibraryId;
    if (api == null || libraryId == null) return;
    final l = AppLocalizations.of(context)!;
    final picked = await showStackableSheet<Map<String, dynamic>>(
      context: context,
      showHandle: true,
      useSafeArea: true,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      builder: (_, __) => _ExistingBookPicker(api: api, libraryId: libraryId),
    );
    if (picked == null || !mounted) return;
    final id = picked['id'] as String? ?? '';
    final full = await api.getLibraryItem(id) ?? picked;
    if (!mounted) return;
    final relPath = (full['relPath'] as String? ?? picked['relPath'] as String? ?? '')
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    if (relPath.isEmpty) {
      _showError(l.adminUploadTargetNoFolder);
      return;
    }
    final metadata =
        (full['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? l.unknown;
    final folderId = full['folderId'] as String? ?? picked['folderId'] as String?;
    final parts = relPath.split('/');
    // The server joins author, series and title; a shallower folder means
    // the missing levels were empty, counted from the top.
    String author = '', series = '', bookFolder = parts.last;
    if (!_isPodcast) {
      if (parts.length >= 3) {
        author = parts[parts.length - 3];
        series = parts[parts.length - 2];
      } else if (parts.length == 2) {
        author = parts[0];
      }
    }
    setState(() {
      _existingTarget = _ExistingBook(id: id, title: title, relPath: relPath);
      _title.text = bookFolder;
      _author.text = author;
      _series.text = series;
      if (folderId != null && _folders.any((f) => f['id']?.toString() == folderId)) {
        _selectedFolderId = folderId;
      }
      _autoFetchMetadata = false;
      _lastMetadataQuery = null;
      if (_metadataSearching) {
        _metadataRequestId++;
        _metadataSearching = false;
      }
    });
  }

  void _clearExistingTarget() {
    setState(() => _existingTarget = null);
  }
  String? _libationExecutablePath;
  String? _libationOutputFolderPath;
  bool _scanning = false;
  // Author filled in from the last chosen export folder, so choosing another
  // book replaces it instead of keeping the previous book's author.
  String _candidateAuthor = '';
  LibationImportHistory _history = const LibationImportHistory(
    importedFolders: <String>{},
  );
  // Exports in the saved output folder not yet imported or seen in the picker.
  int _newExportCount = 0;
  // The export folder the current files came from, recorded once uploaded.
  LibationBookCandidate? _activeCandidate;
  // Title of a matching book already in the selected library, if any.
  String? _libraryDuplicateTitle;
  int _duplicateCheckId = 0;

  bool get _busy => _uploading || _scanning;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  bool get _desktopLibationEnabled =>
      widget.showDesktopLibationControls ??
      (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

  @override
  void initState() {
    super.initState();
    _applyInitialLibraries(widget.libraries);
    if (_libraries.isEmpty && widget.apiService != null) {
      _loadLibrariesFromApi();
    }
    _loadMetadataProviders();
    _loadLibationState();
  }

  Future<void> _loadLibationState() async {
    final history = await LibationImportHistory.load();
    if (!mounted) return;
    setState(() => _history = history);
    if (!_desktopLibationEnabled) return;
    await _loadLibationPrefs();
    if (!mounted) return;
    await _checkForNewExports();
  }

  /// Quietly scans the saved output folder (file names, sizes and dates only)
  /// to offer new Libation downloads. Never uploads anything.
  Future<void> _checkForNewExports() async {
    final folder = _libationOutputFolderPath;
    if (folder == null || folder.isEmpty) return;
    final scanner = widget.directoryScanner ?? scanLibationExportDirectory;
    try {
      final candidates = await scanner(folder);
      if (!mounted) return;
      final fresh = newLibationExports(
        candidates,
        importedFolders: _history.importedFolders,
        lastSeen: _history.lastSeen,
        now: _now(),
      );
      setState(() => _newExportCount = fresh.length);
    } catch (_) {}
  }

  void _applyInitialLibraries(List<dynamic> rawLibraries) {
    _libraries = rawLibraries
        .whereType<Map>()
        .map((library) => Map<String, dynamic>.from(library))
        .toList();

    Map<String, dynamic>? initialLibrary;
    if (widget.initialLibraryId != null) {
      for (final library in _libraries) {
        if (library['id']?.toString() == widget.initialLibraryId) {
          initialLibrary = library;
          break;
        }
      }
    }
    initialLibrary ??= _libraries.firstOrNull;
    _selectedLibraryId = initialLibrary?['id']?.toString();
    _selectedFolderId = _foldersFor(
      initialLibrary,
    ).firstOrNull?['id']?.toString();
    _metadataProvider = _providerFor(initialLibrary);
    _metadataProviders = {_metadataProvider, ..._metadataProviders}.toList();
  }

  Future<void> _loadLibrariesFromApi() async {
    final api = widget.apiService;
    if (api == null) return;
    setState(() => _loadingLibraries = true);
    try {
      final fetched = await api.getLibraries();
      if (!mounted) return;
      setState(() {
        _loadingLibraries = false;
        if (_libraries.isEmpty && fetched.isNotEmpty) {
          _applyInitialLibraries(fetched);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLibraries = false);
    }
  }

  Future<void> _loadLibationPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final exe = prefs.getString(kLibationExecutablePathPref);
      final out = prefs.getString(kLibationOutputFolderPref);
      if (!mounted) return;
      setState(() {
        _libationExecutablePath = (exe != null && exe.trim().isNotEmpty)
            ? exe.trim()
            : null;
        _libationOutputFolderPath = (out != null && out.trim().isNotEmpty)
            ? out.trim()
            : null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _series.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedLibrary {
    for (final library in _libraries) {
      if (library['id']?.toString() == _selectedLibraryId) return library;
    }
    return null;
  }

  List<Map<String, dynamic>> get _folders => _foldersFor(_selectedLibrary);

  Map<String, dynamic>? get _selectedFolder {
    for (final folder in _folders) {
      if (folder['id']?.toString() == _selectedFolderId) return folder;
    }
    return null;
  }

  String get _mediaType => _selectedLibrary?['mediaType']?.toString() ?? 'book';
  bool get _isPodcast => _mediaType == 'podcast';
  String get _folderPath =>
      _selectedFolder?['fullPath']?.toString() ??
      _selectedFolder?['path']?.toString() ??
      '';

  String _providerFor(Map<String, dynamic>? library) {
    final provider = library?['provider']?.toString().trim() ?? '';
    return provider.isEmpty ? 'audible' : provider;
  }

  Future<void> _loadMetadataProviders() async {
    final api = widget.apiService;
    if (api == null) return;
    final providers = await api.getMetadataProviders();
    if (!mounted) return;
    setState(() {
      _metadataProviders = {
        _metadataProvider,
        ...providers.where((provider) => provider.isNotEmpty),
      }.toList();
    });
  }

  List<Map<String, dynamic>> _foldersFor(Map<String, dynamic>? library) {
    final folders = library?['folders'] as List? ?? const [];
    return folders
        .whereType<Map>()
        .map((folder) => Map<String, dynamic>.from(folder))
        .toList();
  }

  void _selectLibrary(String? id) {
    if (id == null) return;
    Map<String, dynamic>? library;
    for (final candidate in _libraries) {
      if (candidate['id']?.toString() == id) {
        library = candidate;
        break;
      }
    }
    setState(() {
      _selectedLibraryId = id;
      _selectedFolderId = _folders.firstOrNull?['id']?.toString();
      _metadataProvider = _providerFor(library);
      if (!_metadataProviders.contains(_metadataProvider)) {
        _metadataProviders = [_metadataProvider, ..._metadataProviders];
      }
      _lastMetadataQuery = null;
      _metadataSearching = false;
      _metadataRequestId++;
      _libraryDuplicateTitle = null;
    });
    final candidate = _activeCandidate;
    if (candidate != null) _checkLibraryDuplicate(candidate);
  }

  String _extension(String filename) => libationFileExtension(filename);

  bool _isSupported(MediaUploadFile file) =>
      _supportedExtensions.contains(_extension(file.name));

  bool _isPrimaryFile(MediaUploadFile file) {
    final extension = _extension(file.name);
    return _audioExtensions.contains(extension) ||
        (!_isPodcast && _ebookExtensions.contains(extension));
  }

  String _metadataValue(dynamic value) {
    if (value is String) return value.trim();
    if (value is num) return value.toString();
    return '';
  }

  String _seriesValue(dynamic value) {
    if (value is List && value.isNotEmpty) return _seriesValue(value.first);
    if (value is Map) {
      return _metadataValue(value['series'] ?? value['name']);
    }
    return _metadataValue(value);
  }

  String get _metadataQuery => [
    _metadataProvider,
    _title.text.trim(),
    _author.text.trim(),
  ].join('\u0000');

  void _detailsChanged() {
    setState(() {
      _lastMetadataQuery = null;
      if (_metadataSearching) {
        _metadataRequestId++;
        _metadataSearching = false;
      }
    });
  }

  Future<void> _setAutoFetchMetadata(bool value) async {
    setState(() {
      _autoFetchMetadata = value;
      _lastMetadataQuery = null;
      if (!value) {
        _metadataRequestId++;
        _metadataSearching = false;
      }
    });
    if (value) await _fetchMetadata();
  }

  Future<void> _selectMetadataProvider(String? provider) async {
    if (provider == null || provider == _metadataProvider) return;
    setState(() {
      _metadataProvider = provider;
      _lastMetadataQuery = null;
      _metadataRequestId++;
      _metadataSearching = false;
    });
    if (_autoFetchMetadata) await _fetchMetadata();
  }

  Future<void> _fetchMetadata({bool showNoResults = true}) async {
    if (!_autoFetchMetadata || _isPodcast || _metadataSearching) return;
    final title = _title.text.trim();
    if (title.isEmpty) return;

    final searcher = widget.metadataSearcher;
    final api = widget.apiService;
    if (searcher == null && api == null) return;

    final query = _metadataQuery;
    final requestId = ++_metadataRequestId;
    setState(() => _metadataSearching = true);

    List<Map<String, dynamic>> results;
    try {
      results = searcher != null
          ? await searcher(
              title: title,
              author: _author.text.trim(),
              provider: _metadataProvider,
            )
          : await api!.searchBooks(
              title: title,
              author: _author.text.trim(),
              provider: _metadataProvider,
            );
    } catch (_) {
      if (!mounted || requestId != _metadataRequestId) return;
      setState(() {
        _metadataSearching = false;
        _lastMetadataQuery = query;
      });
      _showError(AppLocalizations.of(context)!.adminUploadMetadataFailed);
      return;
    }

    if (!mounted || requestId != _metadataRequestId) return;
    if (results.isEmpty) {
      setState(() {
        _metadataSearching = false;
        _lastMetadataQuery = query;
      });
      if (showNoResults) {
        showOverlayToast(
          context,
          AppLocalizations.of(context)!.adminUploadMetadataNoResults,
          icon: Icons.search_off_rounded,
        );
      }
      return;
    }

    final result = results.first;
    final nestedBook = result['book'];
    final book = nestedBook is Map
        ? Map<String, dynamic>.from(nestedBook)
        : result;
    final matchedTitle = _metadataValue(book['title']);
    final matchedAuthor = _metadataValue(book['author'] ?? book['authorName']);
    final matchedSeries = _seriesValue(book['series']);

    setState(() {
      if (matchedTitle.isNotEmpty) _title.text = matchedTitle;
      if (matchedAuthor.isNotEmpty) _author.text = matchedAuthor;
      if (matchedSeries.isNotEmpty) _series.text = matchedSeries;
      _metadataSearching = false;
      _lastMetadataQuery = _metadataQuery;
    });
  }

  Future<List<MediaUploadFile>?> _pickWithFilePicker({
    bool exportedOnly = false,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions:
          (exportedOnly ? _libationExportExtensions : _supportedExtensions)
              .toList()
            ..sort(),
      withReadStream: true,
    );
    if (result == null) return null;
    return result.files
        .map(
          (file) => MediaUploadFile(
            name: file.name,
            size: file.size,
            path: file.path,
            bytes: file.bytes,
            readStream: file.readStream,
          ),
        )
        .toList();
  }

  Future<void> _pickFiles({bool exportedOnly = false}) async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    try {
      final picked =
          await (widget.filePicker ??
              () => _pickWithFilePicker(exportedOnly: exportedOnly))();
      if (picked == null || picked.isEmpty || !mounted) return;
      final supported = picked
          .where(
            (file) => exportedOnly
                ? _libationExportExtensions.contains(_extension(file.name))
                : _isSupported(file),
          )
          .toList();
      if (supported.length != picked.length) {
        showOverlayToast(
          context,
          exportedOnly
              ? l.libationImportUnsupported
              : l.adminUploadUnsupportedFiles,
          icon: Icons.warning_amber_rounded,
        );
      }
      if (supported.isEmpty) return;

      final existing = <String>{
        for (final file in _files) '${file.name}\u0000${file.size}',
      };
      final newFiles = supported
          .where((file) => existing.add('${file.name}\u0000${file.size}'))
          .toList();
      if (newFiles.isEmpty) return;

      setState(() {
        if (_files.isEmpty) {
          // Hand-picked files start a new book, not the last scanned folder.
          _activeCandidate = null;
          _libraryDuplicateTitle = null;
        }
        _files = [..._files, ...newFiles];
        final primaryFiles = _files.where(_isPrimaryFile).toList();
        if (_title.text.trim().isEmpty) {
          final inferred = inferTitleFromSelectedFiles(primaryFiles);
          if (inferred != null && inferred.isNotEmpty) {
            _title.text = inferred;
          }
        }
      });
      if (_autoFetchMetadata) await _fetchMetadata();
    } catch (_) {
      if (!mounted) return;
      showOverlayToast(
        context,
        l.adminUploadFilePickerFailed,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _pickExportFolder() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    try {
      final dirPath =
          await (widget.directoryPicker ??
              () => FilePicker.platform.getDirectoryPath())();
      if (dirPath == null || dirPath.trim().isEmpty || !mounted) return;
      await _scanAndSelectFromDirectory(dirPath.trim());
    } catch (_) {
      if (!mounted) return;
      showOverlayToast(
        context,
        l.adminUploadFilePickerFailed,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _scanAndSelectFromDirectory(String directoryPath) async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    final scanner = widget.directoryScanner ?? scanLibationExportDirectory;
    setState(() => _scanning = true);
    List<LibationBookCandidate> candidates;
    try {
      candidates = await scanner(directoryPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showError(l.adminUploadFilePickerFailed);
      return;
    }
    if (!mounted) return;
    setState(() => _scanning = false);
    if (candidates.isEmpty) {
      showOverlayToast(
        context,
        l.libationImportNoExportedBooks,
        icon: Icons.folder_off_outlined,
      );
      return;
    }

    final fresh = newLibationExports(
      candidates,
      importedFolders: _history.importedFolders,
      lastSeen: _history.lastSeen,
      now: _now(),
    ).map((candidate) => libationFolderKey(candidate.directoryPath)).toSet();
    await _markExportsSeen(candidates, directoryPath);
    if (!mounted) return;

    LibationBookCandidate? chosen;
    if (candidates.length == 1) {
      chosen = candidates.single;
    } else {
      chosen = await _showBookCandidatePicker(candidates, newFolders: fresh);
    }
    if (chosen == null || !mounted) return;
    await _applyBookCandidate(chosen);
  }

  /// Once exports have been listed for the user they stop counting as new.
  Future<void> _markExportsSeen(
    List<LibationBookCandidate> candidates,
    String directoryPath,
  ) async {
    DateTime? newest;
    for (final candidate in candidates) {
      final modified = candidate.modified;
      if (modified != null && (newest == null || modified.isAfter(newest))) {
        newest = modified;
      }
    }
    if (newest == null) return;
    await LibationImportHistory.markSeen(newest);
    if (!mounted) return;
    final previous = _history.lastSeen;
    setState(() {
      if (previous == null || newest!.isAfter(previous)) {
        _history = LibationImportHistory(
          importedFolders: _history.importedFolders,
          lastSeen: newest,
        );
      }
      final outputFolder = _libationOutputFolderPath;
      if (outputFolder != null &&
          libationFolderKey(outputFolder) == libationFolderKey(directoryPath)) {
        _newExportCount = 0;
      }
    });
  }

  Future<LibationBookCandidate?> _showBookCandidatePicker(
    List<LibationBookCandidate> candidates, {
    Set<String> newFolders = const <String>{},
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    final imported = _history.importedFolders;
    final showSearch = candidates.length > 8;
    var query = '';
    return showModalBottomSheet<LibationBookCandidate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final needle = query.trim().toLowerCase();
            final visible = needle.isEmpty
                ? candidates
                : candidates
                      .where(
                        (candidate) =>
                            candidate.title.toLowerCase().contains(needle) ||
                            (candidate.author ?? '').toLowerCase().contains(
                              needle,
                            ),
                      )
                      .toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.libationImportSelectBookTitle,
                                    style: tt.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l.libationImportSelectBookSubtitle,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: MaterialLocalizations.of(
                                sheetContext,
                              ).closeButtonTooltip,
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      if (showSearch)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            key: AdminUploadScreen.libationPickerSearchKey,
                            decoration: InputDecoration(
                              hintText: l.libationImportSearchHint,
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) =>
                                setSheetState(() => query = value),
                          ),
                        ),
                      const Divider(height: 1),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.libationImportNoSearchMatches,
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (itemContext, index) {
                              final candidate = visible[index];
                              final key = libationFolderKey(
                                candidate.directoryPath,
                              );
                              final modified = candidate.modified;
                              final details = <String>[
                                if (imported.contains(key))
                                  l.libationImportTagImported
                                else if (newFolders.contains(key))
                                  l.libationImportTagNew,
                                if (candidate.author != null &&
                                    candidate.author!.isNotEmpty)
                                  candidate.author!,
                                if (modified != null)
                                  MaterialLocalizations.of(
                                    itemContext,
                                  ).formatShortDate(modified.toLocal()),
                                l.adminUploadSelectedFiles(
                                  candidate.files.length,
                                ),
                                _formatBytes(candidate.totalBytes),
                              ].join(' · ');
                              return ListTile(
                                leading: Icon(
                                  Icons.audio_file_rounded,
                                  color: cs.primary,
                                ),
                                title: Text(
                                  candidate.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  details,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pop(sheetContext, candidate),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyBookCandidate(LibationBookCandidate candidate) async {
    final l = AppLocalizations.of(context)!;
    if (candidate.skippedFilesCount > 0) {
      showOverlayToast(
        context,
        l.libationImportUnsupported,
        icon: Icons.warning_amber_rounded,
      );
    }
    setState(() {
      _files = List<MediaUploadFile>.from(candidate.files);
      if (candidate.title.trim().isNotEmpty) {
        _title.text = candidate.title.trim();
      }
      final currentAuthor = _author.text.trim();
      final nextAuthor = candidate.author?.trim() ?? '';
      // Keep an author the user typed; replace one a previous folder filled.
      if (currentAuthor.isEmpty || currentAuthor == _candidateAuthor) {
        _author.text = nextAuthor;
      }
      _candidateAuthor = nextAuthor;
      _lastMetadataQuery = null;
      _activeCandidate = candidate;
      _libraryDuplicateTitle = null;
    });
    await _checkLibraryDuplicate(candidate);
    if (!mounted) return;
    if (_autoFetchMetadata) await _fetchMetadata();
  }

  /// Warns (without blocking) when the selected library already has this
  /// book, matched by the ASIN in Libation's folder name or by title.
  Future<void> _checkLibraryDuplicate(LibationBookCandidate candidate) async {
    final libraryId = _selectedLibraryId;
    if (libraryId == null) return;
    final searcher =
        widget.librarySearcher ??
        (widget.apiService == null
            ? null
            : (String id, String query) =>
                  widget.apiService!.searchLibrary(id, query, limit: 10));
    if (searcher == null) return;
    final requestId = ++_duplicateCheckId;
    Map<String, dynamic>? result;
    try {
      result = await searcher(libraryId, candidate.title);
    } catch (_) {
      return;
    }
    if (!mounted || requestId != _duplicateCheckId) return;
    if (!identical(_activeCandidate, candidate)) return;
    final match = matchingLibraryBookTitle(result, candidate);
    if (match == null) return;
    setState(() => _libraryDuplicateTitle = match);
  }

  Future<String?> _pickExecutablePath() async {
    if (widget.executablePicker != null) {
      return widget.executablePicker!();
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? const <String>['exe'] : null,
    );
    return result?.files.firstOrNull?.path;
  }

  Future<void> _configureLibationExecutable() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    try {
      final picked = await _pickExecutablePath();
      if (picked == null || picked.trim().isEmpty || !mounted) return;
      final clean = picked.trim();
      setState(() => _libationExecutablePath = clean);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLibationExecutablePathPref, clean);
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      _showError(l.adminUploadFilePickerFailed);
    }
  }

  Future<void> _launchLibation() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    var exePath = _libationExecutablePath;
    if (exePath == null || exePath.isEmpty) {
      await _configureLibationExecutable();
      if (!mounted) return;
      exePath = _libationExecutablePath;
      if (exePath == null || exePath.isEmpty) return;
    }
    final launcher = widget.executableLauncher ?? launchLibationExecutable;
    final launched = await launcher(exePath);
    if (!mounted) return;
    if (!launched) {
      _showError(l.libationImportLaunchFailed);
    }
  }

  Future<void> _configureLibationOutputFolder() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    try {
      final picked =
          await (widget.directoryPicker ??
              () => FilePicker.platform.getDirectoryPath())();
      if (picked == null || picked.trim().isEmpty || !mounted) return;
      final clean = picked.trim();
      setState(() => _libationOutputFolderPath = clean);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLibationOutputFolderPref, clean);
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      _showError(l.adminUploadFilePickerFailed);
    }
  }

  Future<void> _scanConfiguredOutputFolder() async {
    if (_busy) return;
    var outPath = _libationOutputFolderPath;
    if (outPath == null || outPath.isEmpty) {
      await _configureLibationOutputFolder();
      if (!mounted) return;
      outPath = _libationOutputFolderPath;
      if (outPath == null || outPath.isEmpty) return;
    }
    await _scanAndSelectFromDirectory(outPath);
  }

  void _removeFile(int index) {
    if (_uploading) return;
    setState(() => _files = [..._files]..removeAt(index));
  }

  void _showError(String message) {
    showOverlayToast(context, message, icon: Icons.error_outline_rounded);
  }

  void _updateProgress(int sentBytes, int totalBytes) {
    if (!mounted || totalBytes <= 0) return;
    final now = DateTime.now();
    if (sentBytes < totalBytes &&
        now.difference(_lastProgressUpdate) <
            const Duration(milliseconds: 100)) {
      return;
    }
    _lastProgressUpdate = now;
    setState(() {
      _progress = (sentBytes / totalBytes).clamp(0.0, 1.0);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context)!;
    if (!widget.canUpload) {
      _showError(l.adminUploadPermissionDenied);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedLibraryId == null) {
      _showError(l.adminUploadLibraryRequired);
      return;
    }
    if (_selectedFolderId == null || _folderPath.isEmpty) {
      _showError(l.adminUploadFolderRequired);
      return;
    }
    if (_files.isEmpty) {
      _showError(l.adminUploadFilesRequired);
      return;
    }
    if (!_files.any(_isPrimaryFile)) {
      _showError(
        _isPodcast
            ? l.adminUploadPodcastFileRequired
            : l.adminUploadBookFileRequired,
      );
      return;
    }

    setState(() {
      _uploading = true;
      _progress = null;
    });
    widget.onNavigationGuardChanged?.call();
    var uploadAttempted = false;
    try {
      if (_autoFetchMetadata &&
          !_isPodcast &&
          _lastMetadataQuery != _metadataQuery) {
        await _fetchMetadata();
        if (!mounted) return;
      }

      final request = MediaUploadRequest(
        libraryId: _selectedLibraryId!,
        folderId: _selectedFolderId!,
        mediaType: _mediaType,
        title: _title.text.trim(),
        author: _author.text.trim(),
        series: _series.text.trim(),
        files: _files,
      );

      ApiService? api;
      if (widget.pathChecker == null || widget.uploader == null) {
        api = widget.apiService;
        if (api == null) {
          _showError(l.adminUploadFailed);
          return;
        }
      }

      final pathResult = widget.pathChecker != null
          ? await widget.pathChecker!(request.directory, _folderPath)
          : await api!.checkUploadPathExists(
              directory: request.directory,
              folderPath: _folderPath,
            );
      if (!mounted) return;
      if (!pathResult.success) {
        _showError(
          pathResult.isPermissionDenied
              ? l.adminUploadPermissionDenied
              : l.adminUploadPathCheckFailed,
        );
        return;
      }
      final target = _existingTarget;
      if (target != null && !pathResult.exists) {
        // The folder the server would build does not match the book's real
        // one, usually a character it strips from names. Better a clear stop
        // than a second copy of the book.
        _showError(
          l.adminUploadTargetFolderMismatch(request.directory, target.relPath),
        );
        return;
      }
      if (pathResult.exists && target == null) {
        // The server happily writes into an existing folder, which is how an
        // ebook joins an audiobook that is already there. Ask instead of
        // refusing, since a slip here would merge two different books.
        final existingTitle = pathResult.libraryItemTitle;
        final addAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.adminUploadAddToExistingTitle),
            content: Text(
              existingTitle == null || existingTitle.isEmpty
                  ? l.adminUploadAddToExistingNoItem
                  : l.adminUploadAddToExisting(existingTitle),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.adminUploadAddFiles),
              ),
            ],
          ),
        );
        if (!mounted || addAnyway != true) return;
      }

      uploadAttempted = true;
      final result = widget.uploader != null
          ? await widget.uploader!(request, onProgress: _updateProgress)
          : await api!.uploadMedia(request, onProgress: _updateProgress);
      if (!mounted) return;

      var indexed = true;
      // The upload endpoint can return before the library scanner exposes the
      // destination. Only the real screen path performs this follow-up;
      // injected fixture uploaders intentionally model one request only.
      if (result.success &&
          api != null &&
          widget.pathChecker == null &&
          widget.uploader == null) {
        setState(() => _indexing = true);
        indexed = await _waitForIndex(
          api,
          directory: request.directory,
          folderPath: _folderPath,
        );
        if (!mounted) return;
      }

      final uploadedTitle = target?.title ?? request.title;
      final mustReselectFiles =
          !result.success &&
          _files.any(
            (file) =>
                file.path == null &&
                file.bytes == null &&
                file.readStream != null,
          );
      final importedCandidate = result.success ? _activeCandidate : null;
      setState(() {
        if (result.success) {
          _title.clear();
          _author.clear();
          _series.clear();
          _files = [];
          _candidateAuthor = '';
          _lastMetadataQuery = null;
          _activeCandidate = null;
          _libraryDuplicateTitle = null;
          _existingTarget = null;
          if (importedCandidate != null) {
            _history = LibationImportHistory(
              importedFolders: {
                ..._history.importedFolders,
                libationFolderKey(importedCandidate.directoryPath),
              },
              lastSeen: _history.lastSeen,
            );
          }
        } else if (mustReselectFiles) {
          _files = [];
        }
      });
      if (importedCandidate != null) {
        // Only after Audiobookshelf accepted the upload.
        await LibationImportHistory.recordImported(
          importedCandidate.directoryPath,
        );
        if (!mounted) return;
      }
      if (result.success) {
        widget.onUploadComplete?.call();
        showOverlayToast(
          context,
          target != null
              ? l.adminUploadAddedTo(uploadedTitle)
              : indexed
              ? l.adminUploadComplete(uploadedTitle)
              : l.adminUploadCompletePendingIndex(uploadedTitle),
          icon: Icons.check_circle_outline_rounded,
        );
      } else {
        final String message;
        if (result.isPermissionDenied) {
          message = l.adminUploadPermissionDenied;
        } else {
          final error = result.error?.trim();
          message = error == null || error.isEmpty
              ? l.adminUploadFailed
              : l.adminUploadFailedReason(error);
        }
        _showError(
          mustReselectFiles
              ? '$message ${l.adminUploadReselectFiles}'
              : message,
        );
      }
    } catch (_) {
      if (!mounted) return;
      final mustReselect =
          uploadAttempted &&
          _files.any(
            (file) =>
                file.path == null &&
                file.bytes == null &&
                file.readStream != null,
          );
      if (mustReselect) setState(() => _files = []);
      _showError(
        mustReselect
            ? '${l.adminUploadFailed} ${l.adminUploadReselectFiles}'
            : l.adminUploadFailed,
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _indexing = false;
          _progress = null;
        });
        widget.onNavigationGuardChanged?.call();
      }
    }
  }

  /// Give Audiobookshelf a short, bounded window to expose a newly uploaded
  /// destination. A timeout is not treated as an upload failure: indexing is
  /// server-side work and may continue after the app returns to the library.
  Future<bool> _waitForIndex(
    ApiService api, {
    required String directory,
    required String folderPath,
  }) async {
    const delays = <Duration>[
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (!mounted) return false;
      final result = await api.checkUploadPathExists(
        directory: directory,
        folderPath: folderPath,
      );
      if (result.success && result.exists) return true;
    }
    return false;
  }

  MediaUploadRequest? get _draft {
    if (_selectedLibraryId == null || _selectedFolderId == null) return null;
    final title = _title.text.trim();
    if (title.isEmpty) return null;
    return MediaUploadRequest(
      libraryId: _selectedLibraryId!,
      folderId: _selectedFolderId!,
      mediaType: _mediaType,
      title: title,
      author: _author.text.trim(),
      series: _series.text.trim(),
      files: _files,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !_uploading,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: AbsorbPageHeader(
                        title: l.adminUploadTitle,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: _uploading
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadingLibraries
                    ? const Center(child: CircularProgressIndicator())
                    : _libraries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l.adminUploadNoLibraries,
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!widget.canUpload) ...[
                                      _permissionBanner(cs, tt, l),
                                      const SizedBox(height: 12),
                                    ],
                                    _destinationCard(cs, tt, l),
                                    const SizedBox(height: 12),
                                    _detailsCard(cs, tt, l),
                                    const SizedBox(height: 12),
                                    if (!_isPodcast) ...[
                                      _libationCard(cs, tt, l),
                                      const SizedBox(height: 12),
                                    ],
                                    _filesCard(cs, tt, l),
                                    const SizedBox(height: 16),
                                    if (_uploading) ...[
                                      LinearProgressIndicator(value: _progress),
                                      const SizedBox(height: 8),
                                      Text(
                                        _indexing
                                            ? l.adminUploadIndexing
                                            : _progress == null
                                            ? l.adminUploadUploading
                                            : l.adminUploadProgress(
                                                (_progress! * 100).round(),
                                              ),
                                        textAlign: TextAlign.center,
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    FilledButton.icon(
                                      key: AdminUploadScreen.submitKey,
                                      onPressed: _busy || _metadataSearching
                                          ? null
                                          : _submit,
                                      icon: _uploading
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: cs.onPrimary,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_upload_rounded,
                                            ),
                                      label: Text(
                                        _uploading
                                            ? l.adminUploadUploading
                                            : l.adminUploadButton,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionBanner(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    return Container(
      key: AdminUploadScreen.permissionBannerKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.adminUploadPermissionDenied,
              style: tt.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _destinationCard(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    return _card(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.adminUploadDestination,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _dropdown<String>(
            key: AdminUploadScreen.libraryFieldKey,
            cs: cs,
            label: l.libraryTitle,
            value: _selectedLibraryId,
            enabled: !_uploading,
            items: [
              for (final library in _libraries)
                DropdownMenuItem(
                  value: library['id']?.toString(),
                  child: Text(
                    library['name']?.toString() ?? l.libraryFallback,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _selectLibrary,
          ),
          const SizedBox(height: 12),
          _dropdown<String>(
            key: AdminUploadScreen.folderFieldKey,
            cs: cs,
            label: l.adminUploadFolder,
            value: _selectedFolderId,
            enabled: !_uploading && _folders.isNotEmpty,
            items: [
              for (final folder in _folders)
                DropdownMenuItem(
                  value: folder['id']?.toString(),
                  child: Text(
                    folder['fullPath']?.toString() ??
                        folder['path']?.toString() ??
                        '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(() => _selectedFolderId = id),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${l.libMediaType}:',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Container(
                key: AdminUploadScreen.mediaTypeKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isPodcast ? l.libMediaPodcast : l.libMediaBook,
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    final draft = _draft;
    final destination = draft == null || _folderPath.isEmpty
        ? null
        : '${_folderPath.replaceAll(RegExp(r'[\\/]+$'), '')}/${draft.directory}';
    return _card(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.adminUploadDetails,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          // BookOrbit items carry file names, not a folder path, so the
          // picker cannot aim an upload there.
          if (_existingTarget == null && widget.apiService?.isBookOrbit != true)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy || _selectedLibraryId == null
                    ? null
                    : _pickExistingBook,
                icon: const Icon(Icons.library_add_rounded, size: 18),
                label: Text(l.adminUploadAddToBook),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.library_add_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.adminUploadAddingTo(_existingTarget!.title),
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _existingTarget!.relPath,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _uploading ? null : _clearExistingTarget,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            key: AdminUploadScreen.titleFieldKey,
            controller: _title,
            enabled: !_uploading && _existingTarget == null,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l.title),
            validator: (value) => value == null || value.trim().isEmpty
                ? l.adminUploadTitleRequired
                : null,
            onChanged: (_) => _detailsChanged(),
          ),
          if (!_isPodcast) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final author = TextFormField(
                  key: AdminUploadScreen.authorFieldKey,
                  controller: _author,
                  enabled: !_uploading && _existingTarget == null,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l.author,
                    hintText: l.adminUploadOptional,
                  ),
                  onChanged: (_) => _detailsChanged(),
                );
                final series = TextFormField(
                  key: AdminUploadScreen.seriesFieldKey,
                  controller: _series,
                  enabled: !_uploading && _existingTarget == null,
                  decoration: InputDecoration(
                    labelText: l.seriesLabel,
                    hintText: l.adminUploadOptional,
                  ),
                  onChanged: (_) => _detailsChanged(),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [author, const SizedBox(height: 12), series],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: author),
                    const SizedBox(width: 12),
                    Expanded(child: series),
                  ],
                );
              },
            ),
            if (_existingTarget == null) ...[
              const SizedBox(height: 16),
              _metadataControls(cs, tt, l),
            ],
          ],
          if (destination != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.adminUploadDestinationPreview,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination,
                    style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metadataControls(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.adminUploadAutoMetadata,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metadataSearching
                          ? l.adminUploadMetadataSearching
                          : l.adminUploadAutoMetadataSubtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_metadataSearching) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              Switch(
                key: AdminUploadScreen.autoMetadataKey,
                value: _autoFetchMetadata,
                onChanged: _uploading
                    ? null
                    : (value) async => _setAutoFetchMetadata(value),
              ),
            ],
          ),
          if (_autoFetchMetadata) ...[
            const SizedBox(height: 10),
            _dropdown<String>(
              key: AdminUploadScreen.metadataProviderKey,
              cs: cs,
              label: l.adminUploadMetadataProvider,
              value: _metadataProvider,
              enabled: !_uploading && !_metadataSearching,
              items: [
                for (final provider in _metadataProviders)
                  DropdownMenuItem(value: provider, child: Text(provider)),
              ],
              onChanged: (provider) async => _selectMetadataProvider(provider),
            ),
          ],
        ],
      ),
    );
  }

  Widget _libationCard(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    final showDesktopControls = _desktopLibationEnabled;
    return _card(
      cs,
      child: ExpansionTile(
        key: AdminUploadScreen.libationGuideKey,
        initiallyExpanded: widget.initialLibationExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.drive_folder_upload_outlined, color: cs.primary),
        title: Text(
          l.libationImportTitle,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          _newExportCount > 0
              ? l.libationImportNewReady(_newExportCount)
              : l.libationImportSubtitle,
          style: tt.bodySmall?.copyWith(
            color: _newExportCount > 0 ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
        children: [
          if (_newExportCount > 0) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: AdminUploadScreen.libationReviewNewKey,
                onPressed: _busy ? null : _scanConfiguredOutputFolder,
                icon: const Icon(Icons.new_releases_outlined, size: 18),
                label: Text(l.libationImportReviewNew),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(l.libationImportSteps, style: tt.bodyMedium),
          const SizedBox(height: 12),
          Text(
            l.libationImportPrivacy,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: AdminUploadScreen.libationFilesKey,
                  onPressed: _busy
                      ? null
                      : () => _pickFiles(exportedOnly: true),
                  icon: const Icon(Icons.audio_file_outlined, size: 18),
                  label: Text(l.libationImportChooseFiles),
                ),
                OutlinedButton.icon(
                  key: AdminUploadScreen.libationFolderKey,
                  onPressed: _busy ? null : _pickExportFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(l.libationImportChooseFolder),
                ),
              ],
            ),
          ),
          if (_scanning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              key: AdminUploadScreen.libationScanProgressKey,
            ),
          ],
          if (_libraryDuplicateTitle != null) ...[
            const SizedBox(height: 12),
            Row(
              key: AdminUploadScreen.libationDuplicateWarningKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.libationImportAlreadyInLibrary(_libraryDuplicateTitle!),
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ),
              ],
            ),
          ],
          if (showDesktopControls) ...[
            const SizedBox(height: 12),
            Text(
              l.libationImportDesktopHint,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: AdminUploadScreen.libationLaunchKey,
                    onPressed: _busy ? null : _launchLibation,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l.libationImportLaunchApp),
                  ),
                  OutlinedButton.icon(
                    key: AdminUploadScreen.libationSetAppKey,
                    onPressed: _busy ? null : _configureLibationExecutable,
                    icon: const Icon(
                      Icons.settings_applications_outlined,
                      size: 18,
                    ),
                    label: Text(l.libationImportSetApp),
                  ),
                  OutlinedButton.icon(
                    key: AdminUploadScreen.libationScanOutputFolderKey,
                    onPressed: _busy ? null : _scanConfiguredOutputFolder,
                    icon: const Icon(Icons.library_music_outlined, size: 18),
                    label: Text(l.libationImportScanOutputFolder),
                  ),
                  OutlinedButton.icon(
                    key: AdminUploadScreen.libationSetOutputFolderKey,
                    onPressed: _busy ? null : _configureLibationOutputFolder,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: Text(l.libationImportSetOutputFolder),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filesCard(ColorScheme cs, TextTheme tt, AppLocalizations l) {
    final totalBytes = _files.fold<int>(0, (total, file) => total + file.size);
    return _card(
      cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.adminUploadFiles,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (_files.isNotEmpty)
                    Text(
                      '${l.adminUploadSelectedFiles(_files.length)} · ${_formatBytes(totalBytes)}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              );
              final chooseButton = OutlinedButton.icon(
                key: AdminUploadScreen.chooseFilesKey,
                onPressed: _busy ? null : _pickFiles,
                icon: Icon(
                  _files.isEmpty
                      ? Icons.attach_file_rounded
                      : Icons.add_rounded,
                  size: 18,
                ),
                label: Text(
                  _files.isEmpty
                      ? l.adminUploadChooseFiles
                      : l.adminUploadAddFiles,
                ),
              );
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (constraints.maxWidth < 480 * scale) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 12), chooseButton],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  chooseButton,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (_files.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    size: 32,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPodcast
                        ? l.adminUploadPodcastFilesHint
                        : l.adminUploadBookFilesHint,
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_files.length, (index) {
              final file = _files[index];
              return Container(
                margin: EdgeInsets.only(top: index == 0 ? 0 : 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPrimaryFile(file)
                          ? Icons.audio_file_rounded
                          : Icons.description_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium,
                          ),
                          Text(
                            _formatBytes(file.size),
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.remove,
                      onPressed: _uploading ? null : () => _removeFile(index),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _card(ColorScheme cs, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _dropdown<T>({
    required Key key,
    required ColorScheme cs,
    required String label,
    required T? value,
    required bool enabled,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: key,
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _ExistingBook {
  final String id;
  final String title;
  final String relPath;
  const _ExistingBook({required this.id, required this.title, required this.relPath});
}

/// Search sheet that hands back the one book tapped.
class _ExistingBookPicker extends StatefulWidget {
  final ApiService api;
  final String libraryId;
  const _ExistingBookPicker({required this.api, required this.libraryId});

  @override
  State<_ExistingBookPicker> createState() => _ExistingBookPickerState();
}

class _ExistingBookPickerState extends State<_ExistingBookPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final api = widget.api;
    final index = BookSearchIndex();
    List<Map<String, dynamic>> results = [];
    try {
      await index.ensureIndex(api, widget.libraryId);
      if (!mounted || _controller.text.trim() != query) return;
      if (index.isReady(widget.libraryId)) {
        results = index.search(widget.libraryId, query).map((h) => h.item).toList();
      }
      if (results.isEmpty || index.isTruncated(widget.libraryId)) {
        final server = await api.searchLibrary(widget.libraryId, query);
        if (!mounted || _controller.text.trim() != query) return;
        final seen = results.map((i) => i['id']).toSet();
        for (final r in (server?['book'] as List<dynamic>? ?? const [])) {
          final m = r as Map<String, dynamic>;
          final item = (m['libraryItem'] as Map<String, dynamic>?) ?? m;
          if (!seen.contains(item['id'])) results.add(item);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.adminUploadAddToBook,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: l.adminUploadAddToBookHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _searched && _results.isEmpty && !_searching
              ? Center(
                  child: Text(l.adminUploadNoBooksFound,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: _results.length,
                  itemBuilder: (context, i) => _row(cs, tt, l, _results[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(ColorScheme cs, TextTheme tt, AppLocalizations l, Map<String, dynamic> item) {
    final itemId = item['id'] as String? ?? '';
    final metadata =
        (item['media'] as Map<String, dynamic>?)?['metadata'] as Map<String, dynamic>? ?? {};
    final title = metadata['title'] as String? ?? l.unknown;
    final author = metadata['authorName'] as String? ?? '';
    final relPath = item['relPath'] as String? ?? '';
    final coverUrl = widget.api.getCoverUrl(itemId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(item),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    httpHeaders: widget.api.mediaHeaders,
                    placeholder: (_, __) => ColoredBox(color: cs.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.menu_book_rounded, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (author.isNotEmpty)
                      Text(author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (relPath.isNotEmpty)
                      Text(relPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
