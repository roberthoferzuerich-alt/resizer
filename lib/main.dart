import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

void main() {
  runApp(const PictureResizeApp());
}

class PictureResizeApp extends StatelessWidget {
  const PictureResizeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Web Image Resizer',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueAccent,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 400),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueAccent,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 400),
            ),
          ),
          themeMode: currentMode,
          home: const ResizerHome(),
        );
      },
    );
  }
}

class ResizerHome extends StatefulWidget {
  const ResizerHome({super.key});

  @override
  State<ResizerHome> createState() => _ResizerHomeState();
}

class _ResizerHomeState extends State<ResizerHome> {
  Uint8List? _previewBytes;
  int? _originalWidth;
  int? _originalHeight;
  
  bool _isLoading = false;
  bool _isDragging = false;
  
  // Gallery
  final List<Uint8List> _gallery = [];
  int _activeGalleryIndex = -1;
  
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  bool _keepAspectRatio = true;
  
  String _selectedFormat = 'jpg'; // jpg, png
  double _quality = 85; // 0 - 100

  // Erweiterte Einstellungen
  img.Interpolation _interpolation = img.Interpolation.linear;
  bool _stripMetadata = true;
  String _watermarkText = '';
  bool _grayscale = false;
  bool _adjustContrast = false;
  String _filenamePattern = '[original]_web_[width]x[height]';
  final TextEditingController _maxKbController = TextEditingController();
  String? _originalFilename;

  Future<void> _processImageBytes(Uint8List bytes, {bool isNewImport = false}) async {
    setState(() {
      _isLoading = true;
    });
    
    // Wichtig: Kurz warten, damit Flutter das Lade-Overlay auf dem Bildschirm zeichnen kann,
    // bevor die schwere Arbeit den Haupt-Thread (besonders im Web) blockiert.
    await Future.delayed(const Duration(milliseconds: 50));
    
    try {
      // Decode ONLY the dimensions natively (instantaneous, no UI block!)
      final ui.Image decoded = await decodeImageFromList(bytes);
      
      setState(() {
        _previewBytes = bytes;
        _originalWidth = decoded.width;
        _originalHeight = decoded.height;
        _widthController.text = decoded.width.toString();
        _heightController.text = decoded.height.toString();
        
        if (isNewImport) {
          _gallery.add(bytes);
          _activeGalleryIndex = _gallery.length - 1;
        } else if (_activeGalleryIndex >= 0 && _activeGalleryIndex < _gallery.length) {
          _gallery[_activeGalleryIndex] = bytes;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bild konnte nicht geladen werden.')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.image,
    );

    if (result.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _originalFilename = result.first.name;
      });
      await Future.delayed(const Duration(milliseconds: 50));
      final file = result.first;
      final bytes = await file.readAsBytes();
      await _processImageBytes(bytes, isNewImport: true);
    }
  }

  void _selectGalleryItem(int index) {
    if (_activeGalleryIndex >= 0 && _activeGalleryIndex < _gallery.length) {
      _gallery[_activeGalleryIndex] = _previewBytes!; // Speichere aktuellen Zustand (z.B. Crop/Rotate)
    }
    setState(() {
      _activeGalleryIndex = index;
      _processImageBytes(_gallery[index]); // Lädt Dimensionen neu etc.
    });
  }

  void _duplicateCurrent() {
    if (_previewBytes == null) return;
    setState(() {
      if (_activeGalleryIndex >= 0 && _activeGalleryIndex < _gallery.length) {
        _gallery[_activeGalleryIndex] = _previewBytes!;
      }
      _gallery.add(Uint8List.fromList(_previewBytes!)); // Echte Kopie
      _activeGalleryIndex = _gallery.length - 1;
    });
  }

  void _deleteGalleryItem(int index) {
    setState(() {
      _gallery.removeAt(index);
      if (_gallery.isEmpty) {
        _previewBytes = null;
        _originalWidth = null;
        _activeGalleryIndex = -1;
      } else {
        if (_activeGalleryIndex == index) {
          _activeGalleryIndex = index > 0 ? index - 1 : 0;
          _processImageBytes(_gallery[_activeGalleryIndex]);
        } else if (_activeGalleryIndex > index) {
          _activeGalleryIndex--;
        }
      }
    });
  }

  void _onWidthChanged(String value) {
    if (!_keepAspectRatio || _originalWidth == null) return;
    final w = int.tryParse(value);
    if (w != null && w > 0) {
      final ratio = _originalHeight! / _originalWidth!;
      final h = (w * ratio).round();
      _heightController.text = h.toString();
    }
  }

  void _onHeightChanged(String value) {
    if (!_keepAspectRatio || _originalWidth == null) return;
    final h = int.tryParse(value);
    if (h != null && h > 0) {
      final ratio = _originalWidth! / _originalHeight!;
      final w = (h * ratio).round();
      _widthController.text = w.toString();
    }
  }

  void _showCropDialog() {
    if (_previewBytes == null) return;
    
    final controller = CropController(
      aspectRatio: _keepAspectRatio ? (_originalWidth! / _originalHeight!) : null,
    );
    String selectedRatioName = _keepAspectRatio ? 'Original' : 'Frei';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Bild zuschneiden'),
              content: SizedBox(
                width: 800,
                height: 600,
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('Original'),
                            selected: selectedRatioName == 'Original',
                            onSelected: (val) {
                              if (val) {
                                controller.aspectRatio = _originalWidth! / _originalHeight!;
                                setDialogState(() => selectedRatioName = 'Original');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Frei'),
                            selected: selectedRatioName == 'Frei',
                            onSelected: (val) {
                              if (val) {
                                controller.aspectRatio = null;
                                setDialogState(() => selectedRatioName = 'Frei');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('1:1 (Quadrat)'),
                            selected: selectedRatioName == '1:1',
                            onSelected: (val) {
                              if (val) {
                                controller.aspectRatio = 1.0;
                                setDialogState(() => selectedRatioName = '1:1');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('16:9'),
                            selected: selectedRatioName == '16:9',
                            onSelected: (val) {
                              if (val) {
                                controller.aspectRatio = 16 / 9;
                                setDialogState(() => selectedRatioName = '16:9');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('4:3'),
                            selected: selectedRatioName == '4:3',
                            onSelected: (val) {
                              if (val) {
                                controller.aspectRatio = 4 / 3;
                                setDialogState(() => selectedRatioName = '4:3');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: CropImage(
                        image: Image.memory(_previewBytes!),
                        controller: controller,
                        onCrop: (_) {},
                        scrimColor: Colors.black.withAlpha(127),
                      ),
                    ),
                  ],
                ),
              ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() { _isLoading = true; });
                await Future.delayed(const Duration(milliseconds: 50));
                
                final uiImage = await controller.croppedBitmap();
                final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
                
                if (byteData != null) {
                  final bytes = byteData.buffer.asUint8List();
                  await _processImageBytes(bytes);
                } else {
                  setState(() { _isLoading = false; });
                }
              },
              child: const Text('Übernehmen'),
            ),
          ],
        );
        }
      );
      },
    );
  }

  Future<void> _saveImage() async {
    if (_previewBytes == null || _originalWidth == null) return;
    
    final w = int.tryParse(_widthController.text) ?? _originalWidth!;
    final h = int.tryParse(_heightController.text) ?? _originalHeight!;

    setState(() {
      _isLoading = true;
    });
    await Future.delayed(const Duration(milliseconds: 50));

    final args = {
      'bytes': _previewBytes!,
      'width': w,
      'height': h,
      'format': _selectedFormat,
      'quality': _quality.toInt(),
      'interpolation': _interpolation,
      'stripMetadata': _stripMetadata,
      'watermarkText': _watermarkText,
      'grayscale': _grayscale,
      'adjustContrast': _adjustContrast,
      'maxKb': int.tryParse(_maxKbController.text),
    };
    
    // Perform decoding, resize and encoding in a separate isolate
    final bytes = await compute(_processImage, args);
    
    if (bytes != null) {
      String ext = _selectedFormat;
      String mime = ext == 'jpg' ? 'image/jpeg' : 'image/png';
      
      String baseName = _originalFilename?.split('.').first ?? 'image';
      String newName = _filenamePattern
        .replaceAll('[original]', baseName)
        .replaceAll('[width]', w.toString())
        .replaceAll('[height]', h.toString())
        .replaceAll('[ext]', ext);
      if (!newName.toLowerCase().endsWith('.$ext')) newName += '.$ext';
      
      setState(() {
        _isLoading = false;
      });
      
      Uri? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Speichern unter...',
        fileName: newName,
        mimeType: mime,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
      );

      if (outputFile != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bild erfolgreich gespeichert! (${(bytes.length / 1024).toStringAsFixed(1)} KB)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _transformImage(String action) async {
    if (_previewBytes == null) return;
    
    setState(() {
      _isLoading = true;
    });
    await Future.delayed(const Duration(milliseconds: 50));
    
    final args = {
      'bytes': _previewBytes!,
      'action': action,
    };
    
    final resultBytes = await compute(_doTransform, args);
    if (resultBytes != null) {
      await _processImageBytes(resultBytes);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  static Uint8List? _doTransform(Map<String, dynamic> args) {
    final Uint8List bytes = args['bytes'];
    final String action = args['action'];
    
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return null;
    
    if (action == 'rotate_left') {
      image = img.copyRotate(image, angle: -90);
    } else if (action == 'rotate_right') {
      image = img.copyRotate(image, angle: 90);
    } else if (action == 'flip_h') {
      image = img.flipHorizontal(image);
    } else if (action == 'flip_v') {
      image = img.flipVertical(image);
    }
    
    // We encode to PNG losslessly to prevent compression artifacts during repeated edits
    return Uint8List.fromList(img.encodePng(image));
  }

  // Top-level function for isolate
  static Uint8List? _processImage(Map<String, dynamic> args) {
    final Uint8List bytes = args['bytes'];
    final int width = args['width'];
    final int height = args['height'];
    final String format = args['format'];
    final int quality = args['quality'];
    
    final img.Interpolation interpolation = args['interpolation'];
    final bool stripMetadata = args['stripMetadata'];
    final String watermarkText = args['watermarkText'];
    final bool grayscale = args['grayscale'];
    final bool adjustContrast = args['adjustContrast'];
    final int? maxKb = args['maxKb'];

    // Decode original image here in the background thread!
    img.Image? processed = img.decodeImage(bytes);
    if (processed == null) return null;

    // Metadata
    if (stripMetadata) {
      processed.exif.clear();
    }

    // Resize image
    processed = img.copyResize(processed, width: width, height: height, interpolation: interpolation);

    // Filters
    if (grayscale) {
      processed = img.grayscale(processed);
    }
    
    if (adjustContrast) {
      processed = img.adjustColor(processed, contrast: 1.2);
    }

    // Watermark
    if (watermarkText.isNotEmpty) {
      img.drawString(
        processed, 
        watermarkText, 
        font: img.arial24, 
        x: 20, 
        y: processed.height - 40, 
      );
    }

    // Encode
    Uint8List outputBytes;
    if (format == 'jpg') {
      outputBytes = Uint8List.fromList(img.encodeJpg(processed, quality: quality));
      
      // Target File Size Logic
      if (maxKb != null && maxKb > 0) {
        int currentQuality = quality;
        while (outputBytes.lengthInBytes > maxKb * 1024 && currentQuality > 10) {
          currentQuality -= 5;
          outputBytes = Uint8List.fromList(img.encodeJpg(processed, quality: currentQuality));
        }
      }
    } else {
      outputBytes = Uint8List.fromList(img.encodePng(processed));
    }
    return outputBytes;
  }

  Widget _buildLivePreview() {
    Widget imageWidget = Image.memory(_previewBytes!, fit: BoxFit.contain);
    
    // Grayscale
    if (_grayscale) {
      imageWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: imageWidget,
      );
    }
    
    // Contrast (+20%)
    if (_adjustContrast) {
      imageWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.2, 0, 0, 0, -25.5,
          0, 1.2, 0, 0, -25.5,
          0, 0, 1.2, 0, -25.5,
          0, 0, 0, 1, 0,
        ]),
        child: imageWidget,
      );
    }

    // Watermark
    if (_watermarkText.isNotEmpty) {
      // Simulate watermark on the bottom left (we use a Stack relative to the Box).
      // It's a preview representation, not pixel-perfect with the image package's drawString.
      imageWidget = Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          Positioned(
            left: 20,
            bottom: 40,
            child: IgnorePointer(
              child: Text(
                _watermarkText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1,1))
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    return imageWidget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withAlpha(50),
                Theme.of(context).colorScheme.tertiary.withAlpha(20),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_size_select_large, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Web Image Resizer'),
          ],
        ),
        centerTitle: true,
        elevation: 2,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            tooltip: 'Optionen',
            onSelected: (value) {
              if (value == 'settings') {
                Offset dialogPosition = Offset.zero;
                
                showDialog(
                  context: context,
                  barrierColor: Colors.black12, // Leichterer Hintergrund für Live-Vorschau
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        return Transform.translate(
                          offset: dialogPosition,
                          child: AlertDialog(
                            titlePadding: EdgeInsets.zero,
                            title: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) {
                                setDialogState(() {
                                  dialogPosition += details.delta;
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
                                child: Row(
                                  children: [
                                    Icon(Icons.drag_indicator, color: Colors.grey),
                                    SizedBox(width: 8),
                                    Expanded(child: Text('Erweiterte Bildeinstellungen')),
                                  ],
                                ),
                              ),
                            ),
                          content: SingleChildScrollView(
                            child: SizedBox(
                              width: 450,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<img.Interpolation>(
                                    initialValue: _interpolation,
                                    decoration: const InputDecoration(labelText: 'Skalierungs-Algorithmus'),
                                    items: const [
                                      DropdownMenuItem(value: img.Interpolation.linear, child: Text('Bilinear (Guter Standard)')),
                                      DropdownMenuItem(value: img.Interpolation.cubic, child: Text('Bikubisch (Schärfer)')),
                                      DropdownMenuItem(value: img.Interpolation.nearest, child: Text('Nearest Neighbor (Pixel)')),
                                      DropdownMenuItem(value: img.Interpolation.average, child: Text('Average (Weich)')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setDialogState(() => _interpolation = val);
                                        setState(() => _interpolation = val);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  SwitchListTile(
                                    title: const Text('Metadaten (EXIF) entfernen'),
                                    subtitle: const Text('Löscht GPS & Kamera-Infos'),
                                    value: _stripMetadata,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (val) {
                                      setDialogState(() => _stripMetadata = val);
                                      setState(() => _stripMetadata = val);
                                    },
                                  ),
                                  SwitchListTile(
                                    title: const Text('Schwarz-Weiß Filter (Grayscale)'),
                                    value: _grayscale,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (val) {
                                      setDialogState(() => _grayscale = val);
                                      setState(() => _grayscale = val);
                                    },
                                  ),
                                  SwitchListTile(
                                    title: const Text('Kontrast leicht anheben (+20%)'),
                                    value: _adjustContrast,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (val) {
                                      setDialogState(() => _adjustContrast = val);
                                      setState(() => _adjustContrast = val);
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    initialValue: _watermarkText,
                                    decoration: const InputDecoration(
                                      labelText: 'Wasserzeichen-Text',
                                      hintText: 'z.B. © Robert Hofer 2026',
                                    ),
                                    onChanged: (val) {
                                      _watermarkText = val;
                                      setState(() {});
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    initialValue: _filenamePattern,
                                    decoration: const InputDecoration(
                                      labelText: 'Dateinamen-Muster',
                                      hintText: '[original]_[width]x[height]',
                                    ),
                                    onChanged: (val) {
                                      _filenamePattern = val;
                                      setState(() {});
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _maxKbController,
                                    decoration: const InputDecoration(
                                      labelText: 'Ziel-Dateigröße (Max KB, nur JPG)',
                                      hintText: 'Leer lassen für keine Grenze',
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Schließen & Anwenden'),
                            ),
                          ],
                        ),
                        );
                      }
                    );
                  }
                );
              } else if (value == 'darkmode') {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
              } else if (value == 'guide') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GuideScreen()),
                );
              }
            },
            itemBuilder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return [
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 20),
                      SizedBox(width: 12),
                      Text('Einstellungen'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'darkmode',
                  child: Row(
                    children: [
                      Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
                      const SizedBox(width: 12),
                      Text(isDark ? 'Light Mode' : 'Dark Mode'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'guide',
                  child: Row(
                    children: [
                      Icon(Icons.menu_book, size: 20),
                      SizedBox(width: 12),
                      Text('Benutzerführung'),
                    ],
                  ),
                ),
              ];
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Menu Bar
          Theme(
            data: Theme.of(context).copyWith(
              menuBarTheme: MenuBarThemeData(
                style: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.primaryContainer),
                  elevation: const WidgetStatePropertyAll(4),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
                  shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                ),
              ),
              menuButtonTheme: MenuButtonThemeData(
                style: MenuItemButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  textStyle: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
            child: MenuBar(
              children: [
                SubmenuButton(
                  menuChildren: [
                    MenuItemButton(
                      onPressed: _pickImage,
                      leadingIcon: const Icon(Icons.folder_open, size: 18),
                      child: const Text('Bild öffnen...'),
                    ),
                    MenuItemButton(
                      onPressed: _previewBytes != null ? _saveImage : null,
                      leadingIcon: const Icon(Icons.save_alt, size: 18),
                      child: const Text('Webkonform speichern...'),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: () => SystemNavigator.pop(),
                      leadingIcon: const Icon(Icons.exit_to_app, size: 18),
                      child: const Text('Beenden'),
                    ),
                  ],
                  child: const Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Datei'),
                    ],
                  ),
                ),
                SubmenuButton(
                  menuChildren: [
                    MenuItemButton(
                      onPressed: _previewBytes != null ? _showCropDialog : null,
                      leadingIcon: const Icon(Icons.crop, size: 18),
                      child: const Text('Zuschneiden (Crop)'),
                    ),
                  ],
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Bearbeiten'),
                    ],
                  ),
                ),
                SubmenuButton(
                  menuChildren: [
                    MenuItemButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AboutScreen()),
                        );
                      },
                      leadingIcon: const Icon(Icons.info_outline, size: 18),
                      child: const Text('Über die App'),
                    ),
                  ],
                  child: const Row(
                    children: [
                      Icon(Icons.help_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Hilfe'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Main Body
          Expanded(
            child: DropTarget(
              onDragDone: (detail) async {
                if (detail.files.isNotEmpty) {
                  setState(() {
                    _isLoading = true;
                    _originalFilename = detail.files.first.name;
                  });
                  await Future.delayed(const Duration(milliseconds: 50));
                  final bytes = await detail.files.first.readAsBytes();
                  await _processImageBytes(bytes, isNewImport: true);
                }
              },
              onDragEntered: (detail) {
                setState(() {
                  _isDragging = true;
                });
              },
              onDragExited: (detail) {
                setState(() {
                  _isDragging = false;
                });
              },
              child: Container(
                color: _isDragging 
                  ? Theme.of(context).colorScheme.primaryContainer.withAlpha(127) 
                  : Colors.transparent,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        // Left side - Image Preview
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: _previewBytes != null
                                  ? Column(
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            alignment: Alignment.center,
                                            fit: StackFit.expand,
                                            children: [
                                              _buildLivePreview(),
                                              Positioned(
                                                bottom: 16,
                                                child: Card(
                                                  elevation: 4,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          onPressed: _duplicateCurrent,
                                                          icon: const Icon(Icons.control_point_duplicate),
                                                          tooltip: 'Arbeitskopie anlegen',
                                                        ),
                                                        const SizedBox(width: 8),
                                                        IconButton(
                                                          onPressed: () => _transformImage('flip_h'),
                                                          icon: const Icon(Icons.flip),
                                                          tooltip: 'Horizontal spiegeln',
                                                        ),
                                                        IconButton(
                                                          onPressed: () => _transformImage('rotate_left'),
                                                          icon: const Icon(Icons.rotate_left),
                                                          tooltip: 'Links drehen',
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Tooltip(
                                                          message: 'Bildbereich zuschneiden',
                                                          child: FilledButton.icon(
                                                            onPressed: _showCropDialog,
                                                            icon: const Icon(Icons.crop),
                                                            label: const Text('Zuschneiden'),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        IconButton(
                                                          onPressed: () => _transformImage('rotate_right'),
                                                          icon: const Icon(Icons.rotate_right),
                                                          tooltip: 'Rechts drehen',
                                                        ),
                                                        IconButton(
                                                          onPressed: () => _transformImage('flip_v'),
                                                          icon: Transform.rotate(
                                                            angle: 1.5708, // 90 degrees
                                                            child: const Icon(Icons.flip)
                                                          ),
                                                          tooltip: 'Vertikal spiegeln',
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 16,
                                                right: 16,
                                                child: IconButton.filledTonal(
                                                  onPressed: _pickImage,
                                                  icon: const Icon(Icons.image_search),
                                                  tooltip: 'Anderes Bild wählen',
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                        if (_gallery.length > 1)
                                          Container(
                                            height: 80,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: _gallery.length,
                                              itemBuilder: (context, index) {
                                                final isSelected = index == _activeGalleryIndex;
                                                return GestureDetector(
                                                  onTap: () => _selectGalleryItem(index),
                                                  child: Container(
                                                    width: 80,
                                                    margin: const EdgeInsets.only(right: 8),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withAlpha(100),
                                                        width: isSelected ? 3 : 1,
                                                      ),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        ClipRRect(
                                                          borderRadius: BorderRadius.circular(6),
                                                          child: Image.memory(_gallery[index], fit: BoxFit.cover),
                                                        ),
                                                        Positioned(
                                                          top: 2,
                                                          right: 2,
                                                          child: InkWell(
                                                            onTap: () => _deleteGalleryItem(index),
                                                            child: Container(
                                                              padding: const EdgeInsets.all(2),
                                                              decoration: const BoxDecoration(
                                                                color: Colors.black54,
                                                                shape: BoxShape.circle,
                                                              ),
                                                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                      ],
                                    )
                                  : InkWell(
                                      onTap: _pickImage,
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add_photo_alternate, size: 80, color: Colors.grey),
                                            SizedBox(height: 16),
                                            Text('Bild auswählen oder hier ablegen', style: TextStyle(fontSize: 18)),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        
                        // Right side - Controls
                        if (_originalWidth != null)
                          Expanded(
                            flex: 1,
                            child: Card(
                              margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
                                    const Divider(height: 32),
                                    
                                    // Size
                                    Text('Größe (px)', style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _widthController,
                                            decoration: const InputDecoration(
                                              labelText: 'Breite',
                                              border: OutlineInputBorder(),
                                            ),
                                            keyboardType: TextInputType.number,
                                            onChanged: _onWidthChanged,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: TextField(
                                            controller: _heightController,
                                            decoration: const InputDecoration(
                                              labelText: 'Höhe',
                                              border: OutlineInputBorder(),
                                            ),
                                            keyboardType: TextInputType.number,
                                            onChanged: _onHeightChanged,
                                          ),
                                        ),
                                      ],
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Seitenverhältnis beibehalten'),
                                      value: _keepAspectRatio,
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      onChanged: (value) {
                                        setState(() {
                                          _keepAspectRatio = value ?? true;
                                        });
                                      },
                                    ),
                                    
                                    const SizedBox(height: 24),
                                    
                                    // Format
                                    Text('Export-Format', style: Theme.of(context).textTheme.titleMedium),
                                    const SizedBox(height: 16),
                                    SegmentedButton<String>(
                                      segments: const [
                                        ButtonSegment(value: 'jpg', label: Text('JPEG')),
                                        ButtonSegment(value: 'png', label: Text('PNG')),
                                      ],
                                      selected: {_selectedFormat},
                                      onSelectionChanged: (Set<String> newSelection) {
                                        setState(() {
                                          _selectedFormat = newSelection.first;
                                        });
                                      },
                                    ),
                                    
                                    const SizedBox(height: 24),
                                    
                                    // Quality
                                    if (_selectedFormat == 'jpg') ...[
                                      Text('JPG Qualität: ${_quality.toInt()}%', style: Theme.of(context).textTheme.titleMedium),
                                      Slider(
                                        value: _quality,
                                        min: 10,
                                        max: 100,
                                        divisions: 90,
                                        label: _quality.round().toString(),
                                        onChanged: (value) {
                                          setState(() {
                                            _quality = value;
                                          });
                                        },
                                      ),
                                      const Text(
                                        'Web-Tipp: 70-85% bietet meist die beste Balance zwischen Dateigröße und Qualität.',
                                        style: TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                    
                                    const Spacer(),
                                    
                                    // Save Button
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: FilledButton.icon(
                                        onPressed: _saveImage,
                                        icon: const Icon(Icons.save),
                                        label: const Text('Bild Speichern', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_isLoading)
                      Container(
                        color: Colors.black.withAlpha(127),
                        child: Center(
                          child: Card(
                            elevation: 8,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Bild wird verarbeitet...',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Über die App'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            elevation: 4,
            margin: const EdgeInsets.all(32),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bildauswahl / Logo Platzhalter oben
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.image, size: 50),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Web Image Resizer',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Eine moderne Web-App zur schnellen und sicheren Bildverarbeitung.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  // Personalien
                  const ListTile(
                    leading: CircleAvatar(child: Icon(Icons.person)),
                    title: Text('Entwickler & Initiator'),
                    subtitle: Text('Robert Hofer\nrobert.hofer.zuerich@bluewin.ch'),
                    isThreeLine: true,
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.smart_toy),
                    ),
                    title: Text('KI-Assistent'),
                    subtitle: Text('Antigravity (by Google Deepmind)\nMit Herz und Code entwickelt.'),
                    isThreeLine: true,
                  ),
                  
                  const SizedBox(height: 48),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Zurück zur App'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benutzerführung'),
        centerTitle: true,
      ),
      body: const Center(
        child: SizedBox(
          width: 800,
          child: Markdown(
            data: _guideMarkdown,
            selectable: true,
          ),
        ),
      ),
    );
  }
}

const _guideMarkdown = '''
# 📖 Benutzerführung: Web Image Resizer

Willkommen! Diese App wurde entwickelt, um deine Bilder schnell, sicher und webkonform aufzubereiten. Hier erfährst du, wie du alle Funktionen optimal nutzt.

---

## 1. Ein Bild öffnen
* **Per Klick:** Klicke einfach auf das große Feld "Bild auswählen oder hier ablegen", um ein Bild von deiner Festplatte zu wählen.
* **Drag & Drop:** Du kannst auch einfach ein Bild aus deinem Datei-Explorer nehmen und direkt in das App-Fenster ziehen.
* **Menüleiste:** Alternativ findest du oben links unter **Datei > Bild öffnen...** dieselbe Funktion.

## 2. Größe anpassen (Skalieren)
Sobald ein Bild geladen ist, siehst du rechts die aktuellen Abmessungen.
* Trage bei **Breite** oder **Höhe** deinen gewünschten Wert (in Pixeln) ein.
* Solange **"Seitenverhältnis beibehalten"** aktiv ist, passt sich der jeweils andere Wert automatisch an, sodass dein Bild nicht verzerrt wird.

## 3. Zuschneiden (Crop)
Möchtest du nur einen bestimmten Teil des Bildes behalten?
* Klicke direkt im Bild auf **Zuschneiden** oder nutze das Menü **Bearbeiten > Zuschneiden (Crop)**.
* Ziehe den Rahmen über den gewünschten Bereich. Wenn "Seitenverhältnis beibehalten" aktiv ist, bleibt der Rahmen immer proportional zum Originalbild.
* Bestätige mit **Übernehmen**.

## 4. Format & Qualität
* **Export-Format:** Wähle zwischen **JPEG** (ideal für Fotos) und **PNG** (ideal für Grafiken oder transparente Bilder).
* **Qualität (nur bei JPEG):** Für das Web sind Werte zwischen 70% und 85% oft ein optimaler Kompromiss aus geringer Dateigröße und guter Optik.

## 5. Erweiterte Bildeinstellungen (Das Zahnrad-Menü ⚙️)
Klicke oben rechts auf das Zahnrad und dann auf **Einstellungen**, um echte Profi-Funktionen zu aktivieren. Alle hier getroffenen Einstellungen werden **beim Speichern** automatisch im Hintergrund auf das Bild angewendet!

* **Skalierungs-Algorithmus:** Bestimmt, wie das Bild mathematisch vergrößert/verkleinert wird (Bilinear ist ein guter Standard, Bikubisch liefert oft schärfere Ergebnisse).
* **Metadaten (EXIF) entfernen:** *(Empfohlen für das Web!)* Löscht unsichtbare Daten wie GPS-Koordinaten oder Kameramodelle sicher aus der Bilddatei.
* **Schwarz-Weiß Filter (Grayscale):** Wandelt das Bild beim Speichern komplett in Graustufen um.
* **Kontrast leicht anheben:** Gibt flauen Bildern etwas mehr farblichen "Punch".
* **Wasserzeichen-Text:** Trägst du hier etwas ein, wird der Text automatisch als weißes Wasserzeichen unten links in das fertige Bild gebrannt.
* **Dateinamen-Muster:** Hier kannst du bestimmen, wie deine Dateien nach dem Export heißen sollen. Nutze Platzhalter wie `[original]` (der alte Name), `[width]` (Breite) und `[height]` (Höhe).
* **Ziel-Dateigröße (Max KB):** Du brauchst ein Bild zwingend unter z.B. 500 KB? Trag den Wert hier ein. Die App probiert beim Speichern automatisch so lange verschiedene Kompressionsstufen aus, bis das Bild garantiert klein genug ist.

## 6. Bild speichern
Bist du zufrieden? Klicke unten rechts auf den großen Button **Bild Speichern** (oder nutze das Menü **Datei > Webkonform speichern...**). Du wirst gefragt, wo die Datei auf deinem Computer abgelegt werden soll. Fertig!
''';
