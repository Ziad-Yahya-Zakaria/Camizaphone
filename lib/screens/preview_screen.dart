import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class PreviewScreen extends StatefulWidget {
  final String croppedImagePath;

  const PreviewScreen({super.key, required this.croppedImagePath});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  bool _isProcessing = true;
  String? _errorMessage;
  List<List<String>> _tableData = [];
  List<List<TextEditingController>> _controllers = [];

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Processing progress
  String _statusMessage = 'Initializing OCR Engine...';
  double _progressValue = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _processImage();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final row in _controllers) {
      for (final ctrl in row) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  // ===================================================================
  //  CORE: OCR Processing Pipeline
  // ===================================================================
  Future<void> _processImage() async {
    try {
      setState(() {
        _statusMessage = 'Loading image...';
        _progressValue = 0.15;
      });

      final inputImage = InputImage.fromFilePath(widget.croppedImagePath);

      setState(() {
        _statusMessage = 'Running Text Recognition...';
        _progressValue = 0.35;
      });

      // Initialize the text recognizer (offline, Arabic/Latin combined)
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      await textRecognizer.close();

      setState(() {
        _statusMessage = 'Extracting text elements...';
        _progressValue = 0.55;
      });

      // Extract all text elements with bounding boxes
      final List<_TextElement> elements = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final box = element.boundingBox;
            // Normalize Hindi/Arabic numerals to English
            final normalizedText = _normalizeNumerals(element.text);
            elements.add(_TextElement(
              text: normalizedText,
              rect: box,
            ));
          }
        }
      }

      if (elements.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'No text was recognized in this image.\n'
              'Please try again with a clearer photo.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Building table structure...';
        _progressValue = 0.75;
      });

      // Run the table parsing algorithm
      final table = _buildTableFromElements(elements);

      setState(() {
        _statusMessage = 'Preparing editor...';
        _progressValue = 0.95;
      });

      // Build text editing controllers
      final controllers = table.map((row) {
        return row.map((cell) => TextEditingController(text: cell)).toList();
      }).toList();

      setState(() {
        _tableData = table;
        _controllers = controllers;
        _isProcessing = false;
        _progressValue = 1.0;
      });

      _animController.forward();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'OCR Processing failed:\n${e.toString()}';
      });
    }
  }

  // ===================================================================
  //  Hindi/Arabic Numeral Normalization
  // ===================================================================
  /// Converts Hindi (Eastern Arabic) numerals ٠-٩ to English 0-9
  static String _normalizeNumerals(String input) {
    const hindiNumerals = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const englishNumerals = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    String result = input;
    for (int i = 0; i < hindiNumerals.length; i++) {
      result = result.replaceAll(hindiNumerals[i], englishNumerals[i]);
    }
    return result;
  }

  // ===================================================================
  //  TABLE PARSING ALGORITHM (Critical)
  // ===================================================================
  /// Groups OCR text elements into a structured 2D table based on
  /// their bounding box coordinates. Uses Y-tolerance for row grouping
  /// and X-coordinate sorting for column ordering.
  List<List<String>> _buildTableFromElements(List<_TextElement> elements) {
    if (elements.isEmpty) return [];

    // Step 1: Calculate adaptive Y-tolerance based on median element height
    final heights = elements.map((e) => e.rect.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];
    // Tolerance = 50% of median character height (handles slight skew)
    final yTolerance = medianHeight * 0.5;

    // Step 2: Sort elements primarily by Y (top), then by X (left)
    elements.sort((a, b) {
      final yDiff = a.rect.top - b.rect.top;
      if (yDiff.abs() <= yTolerance) {
        return a.rect.left.compareTo(b.rect.left);
      }
      return yDiff.toInt();
    });

    // Step 3: Group elements into rows using Y-tolerance clustering
    final List<List<_TextElement>> rows = [];
    List<_TextElement> currentRow = [elements.first];

    for (int i = 1; i < elements.length; i++) {
      final element = elements[i];
      // Calculate the average Y of the current row for comparison
      final avgY = currentRow
              .map((e) => e.rect.center.dy)
              .reduce((a, b) => a + b) /
          currentRow.length;

      if ((element.rect.center.dy - avgY).abs() <= yTolerance) {
        // Same row
        currentRow.add(element);
      } else {
        // New row — finalize the current one
        currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
        rows.add(currentRow);
        currentRow = [element];
      }
    }
    // Don't forget the last row
    currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    rows.add(currentRow);

    // Step 4: Determine column boundaries using X-coordinate clustering
    // Collect all unique X-center positions
    final List<double> allXCenters = [];
    for (final row in rows) {
      for (final elem in row) {
        allXCenters.add(elem.rect.center.dx);
      }
    }
    allXCenters.sort();

    // Cluster X positions into columns
    final widths = elements.map((e) => e.rect.width).toList()..sort();
    final medianWidth = widths[widths.length ~/ 2];
    final xTolerance = medianWidth * 0.6;

    final List<double> columnCenters = [];
    for (final x in allXCenters) {
      bool matched = false;
      for (int i = 0; i < columnCenters.length; i++) {
        if ((x - columnCenters[i]).abs() <= xTolerance) {
          // Update running average
          columnCenters[i] = (columnCenters[i] + x) / 2;
          matched = true;
          break;
        }
      }
      if (!matched) {
        columnCenters.add(x);
      }
    }
    columnCenters.sort();

    final numColumns = columnCenters.isEmpty ? 1 : columnCenters.length;

    // Step 5: Map elements to grid cells
    final List<List<String>> table = [];
    for (final row in rows) {
      final List<String> gridRow = List.filled(numColumns, '');

      for (final elem in row) {
        // Find the closest column
        int bestCol = 0;
        double bestDist = double.infinity;
        for (int c = 0; c < columnCenters.length; c++) {
          final dist = (elem.rect.center.dx - columnCenters[c]).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestCol = c;
          }
        }

        // Append text (handles merging multiple elements in same cell)
        if (gridRow[bestCol].isEmpty) {
          gridRow[bestCol] = elem.text;
        } else {
          gridRow[bestCol] = '${gridRow[bestCol]} ${elem.text}';
        }
      }

      table.add(gridRow);
    }

    return table;
  }

  // ===================================================================
  //  Confirm and navigate to ExportScreen
  // ===================================================================
  void _confirmAndExport() {
    // Read the latest values from controllers
    final updatedTable = _controllers.map((row) {
      return row.map((ctrl) => ctrl.text).toList();
    }).toList();

    Navigator.pushNamed(context, '/export', arguments: updatedTable);
  }

  // ===================================================================
  //  UI BUILD
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: _isProcessing
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              title: const Text(
                'Review Table',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (_tableData.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: TextButton.icon(
                      onPressed: _confirmAndExport,
                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                      label: const Text('Export'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF00D9A6),
                        textStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      body: _isProcessing
          ? _buildProcessingView()
          : _errorMessage != null
              ? _buildErrorView()
              : _buildTableView(),
    );
  }

  /// === Processing / Loading View ===
  Widget _buildProcessingView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1117), Color(0xFF161B22)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated scanning icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 2),
                builder: (context, value, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: _progressValue,
                          color: const Color(0xFF6C63FF),
                          backgroundColor: const Color(0xFF6C63FF)
                              .withOpacity(0.15),
                          strokeWidth: 4,
                        ),
                      ),
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.document_scanner_rounded,
                          size: 40,
                          color: Color(0xFF6C63FF),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 36),
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '${(_progressValue * 100).toInt()}%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6C63FF).withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progressValue,
                    backgroundColor:
                        const Color(0xFF6C63FF).withOpacity(0.15),
                    color: const Color(0xFF6C63FF),
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// === Error View ===
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_rounded,
                size: 48,
                color: Color(0xFFFF6B6B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isProcessing = true;
                      _errorMessage = null;
                      _progressValue = 0;
                    });
                    _processImage();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// === Table Review View ===
  Widget _buildTableView() {
    final rowCount = _tableData.length;
    final colCount = _tableData.isNotEmpty ? _tableData.first.length : 0;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          // Summary bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withOpacity(0.15),
                  const Color(0xFF00D9A6).withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart_rounded,
                    color: Color(0xFF6C63FF), size: 20),
                const SizedBox(width: 10),
                Text(
                  '$rowCount rows × $colCount columns',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D9A6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Editable',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Color(0xFF00D9A6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cropped image preview (small thumbnail)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.croppedImagePath),
                fit: BoxFit.cover,
                color: Colors.white.withOpacity(0.85),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Scrollable table
          Expanded(
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(40),
              minScale: 0.5,
              maxScale: 3.0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildDataTable(),
              ),
            ),
          ),

          // Bottom action bar
          _buildBottomBar(),
        ],
      ),
    );
  }

  /// Build the editable DataTable
  Widget _buildDataTable() {
    if (_controllers.isEmpty) return const SizedBox.shrink();

    final colCount = _controllers.first.length;

    return Theme(
      data: Theme.of(context).copyWith(
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(
            const Color(0xFF6C63FF).withOpacity(0.15),
          ),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF6C63FF).withOpacity(0.1);
            }
            return Colors.transparent;
          }),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2333),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
      ),
      child: DataTable(
        border: TableBorder.all(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        columnSpacing: 16,
        horizontalMargin: 12,
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 60,
        columns: List.generate(colCount, (colIdx) {
          return DataColumn(
            label: Text(
              'Col ${colIdx + 1}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6C63FF),
              ),
            ),
          );
        }),
        rows: List.generate(_controllers.length, (rowIdx) {
          return DataRow(
            color: WidgetStateProperty.all(
              rowIdx.isEven
                  ? Colors.transparent
                  : Colors.white.withOpacity(0.02),
            ),
            cells: List.generate(colCount, (colIdx) {
              return DataCell(
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _controllers[rowIdx][colIdx],
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: InputBorder.none,
                      hintText: '...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 13,
                      ),
                    ),
                    onChanged: (value) {
                      _tableData[rowIdx][colIdx] = value;
                    },
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  /// Bottom action bar
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          // Add Row
          _buildSmallAction(
            icon: Icons.add_circle_outline,
            label: 'Add Row',
            onTap: _addRow,
          ),
          const SizedBox(width: 12),
          // Remove Last Row
          _buildSmallAction(
            icon: Icons.remove_circle_outline,
            label: 'Remove Row',
            onTap: _removeLastRow,
          ),
          const Spacer(),
          // Export Button
          ElevatedButton.icon(
            onPressed: _confirmAndExport,
            icon: const Icon(Icons.file_download_rounded, size: 20),
            label: const Text('Confirm & Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9A6),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Add a new empty row
  void _addRow() {
    if (_tableData.isEmpty) return;
    final colCount = _tableData.first.length;
    final newRow = List.filled(colCount, '');
    final newControllers =
        List.generate(colCount, (_) => TextEditingController());

    setState(() {
      _tableData.add(newRow);
      _controllers.add(newControllers);
    });
  }

  /// Remove the last row
  void _removeLastRow() {
    if (_tableData.length <= 1) return;
    setState(() {
      final removed = _controllers.removeLast();
      for (final ctrl in removed) {
        ctrl.dispose();
      }
      _tableData.removeLast();
    });
  }
}

// ===================================================================
//  Internal model class for text elements
// ===================================================================
class _TextElement {
  final String text;
  final Rect rect;

  _TextElement({required this.text, required this.rect});
}
