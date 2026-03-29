import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class ExportScreen extends StatefulWidget {
  final List<List<String>> tableData;

  const ExportScreen({super.key, required this.tableData});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen>
    with SingleTickerProviderStateMixin {
  bool _isExporting = false;
  bool _exportComplete = false;
  String? _savedFilePath;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ===================================================================
  //  Excel Generation & Save
  // ===================================================================
  Future<void> _generateAndSaveExcel() async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      // Create a new Excel workbook
      final excel = Excel.createExcel();
      final sheetName = 'Camizaphone Data';

      // Remove default 'Sheet1' and create our named sheet
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      // Style for header row
      final headerStyle = CellStyle(
        bold: true,
        fontSize: 12,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#6C63FF'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // Style for data cells
      final dataStyle = CellStyle(
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // Write data into the sheet
      for (int rowIdx = 0; rowIdx < widget.tableData.length; rowIdx++) {
        final row = widget.tableData[rowIdx];
        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          final cellValue = row[colIdx];
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx),
          );

          // Try to parse as number, otherwise store as text
          final numValue = double.tryParse(cellValue);
          if (numValue != null) {
            // Check if it's an integer
            if (numValue == numValue.roundToDouble()) {
              cell.value = IntCellValue(numValue.toInt());
            } else {
              cell.value = DoubleCellValue(numValue);
            }
          } else {
            cell.value = TextCellValue(cellValue);
          }

          // Apply style (header for first row, data for rest)
          cell.cellStyle = rowIdx == 0 ? headerStyle : dataStyle;
        }
      }

      // Set column widths
      for (int col = 0;
          col < (widget.tableData.isNotEmpty ? widget.tableData.first.length : 0);
          col++) {
        sheet.setColumnWidth(col, 18.0);
      }

      // Encode the Excel file
      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('Failed to encode Excel file.');
      }

      // Save to Downloads folder
      final savedPath = await _saveToDownloads(fileBytes);

      setState(() {
        _isExporting = false;
        _exportComplete = true;
        _savedFilePath = savedPath;
      });

      _animController.forward();
    } catch (e) {
      setState(() {
        _isExporting = false;
        _errorMessage = 'Export failed: ${e.toString()}';
      });
    }
  }

  /// Save file to the Downloads directory
  Future<String> _saveToDownloads(List<int> fileBytes) async {
    // Request storage permission for pre-Android 11
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      // On Android 11+, we use app-specific directories which don't need permission
    }

    // Generate a unique filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'Camizaphone_Table_$timestamp.xlsx';

    String filePath;

    if (Platform.isAndroid) {
      // Try to save to Downloads folder
      // On Android 10+, use the app's external files directory
      final Directory? downloadsDir =
          await getExternalStorageDirectory();

      if (downloadsDir != null) {
        // Navigate up to the root external storage and into Downloads
        final pathSegments = downloadsDir.path.split('/');
        final androidIdx = pathSegments.indexOf('Android');
        String basePath;
        if (androidIdx > 0) {
          basePath = pathSegments.sublist(0, androidIdx).join('/');
          final downloadPath = '$basePath/Download';
          final downloadDir = Directory(downloadPath);
          if (await downloadDir.exists()) {
            filePath = '$downloadPath/$fileName';
          } else {
            filePath = '${downloadsDir.path}/$fileName';
          }
        } else {
          filePath = '${downloadsDir.path}/$fileName';
        }
      } else {
        // Fallback to app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        filePath = '${appDir.path}/$fileName';
      }
    } else {
      // iOS / other platforms
      final appDir = await getApplicationDocumentsDirectory();
      filePath = '${appDir.path}/$fileName';
    }

    // Write the file
    final file = File(filePath);
    await file.writeAsBytes(fileBytes, flush: true);

    return filePath;
  }

  /// Share the generated file
  Future<void> _shareFile() async {
    if (_savedFilePath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(_savedFilePath!)],
        subject: 'Camizaphone - Excel Table Export',
        text: 'Here is the exported table from Camizaphone 📊',
      );
    } catch (e) {
      _showSnackbar('Share failed: ${e.toString()}');
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: const Color(0xFF1C2333),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ===================================================================
  //  UI BUILD
  // ===================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Export to Excel',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _exportComplete
          ? _buildSuccessView()
          : _isExporting
              ? _buildExportingView()
              : _errorMessage != null
                  ? _buildErrorView()
                  : _buildPreExportView(),
    );
  }

  /// === Pre-Export View (Data preview + Export button) ===
  Widget _buildPreExportView() {
    final rowCount = widget.tableData.length;
    final colCount =
        widget.tableData.isNotEmpty ? widget.tableData.first.length : 0;

    return Column(
      children: [
        // Data Summary Card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1C2333),
                const Color(0xFF1C2333).withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6C63FF).withOpacity(0.2),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.table_chart_rounded,
                      color: Color(0xFF6C63FF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ready to Export',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$rowCount rows × $colCount columns',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D9A6).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '.xlsx',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00D9A6),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              // Feature list
              _buildFeatureTile(
                Icons.format_list_numbered,
                'Auto number detection',
                'Numeric cells formatted as numbers',
              ),
              _buildFeatureTile(
                Icons.color_lens_outlined,
                'Styled headers',
                'First row styled with colors',
              ),
              _buildFeatureTile(
                Icons.folder_rounded,
                'Save to Downloads',
                'File saved for easy access',
              ),
            ],
          ),
        ),

        // Data Preview (scrollable)
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2333),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.preview_rounded,
                          color: Colors.white38, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Data Preview',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _buildPreviewTable(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Export Button
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _generateAndSaveExcel,
              icon: const Icon(Icons.file_download_rounded, size: 22),
              label: const Text('Generate & Save Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
                shadowColor: const Color(0xFF6C63FF).withOpacity(0.3),
                textStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.white30,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF00D9A6)),
        ],
      ),
    );
  }

  /// Preview table (read-only)
  Widget _buildPreviewTable() {
    return Table(
      border: TableBorder.all(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      defaultColumnWidth: const FixedColumnWidth(100),
      children: widget.tableData.asMap().entries.map((entry) {
        final rowIdx = entry.key;
        final row = entry.value;
        return TableRow(
          decoration: BoxDecoration(
            color: rowIdx == 0
                ? const Color(0xFF6C63FF).withOpacity(0.15)
                : rowIdx.isEven
                    ? Colors.white.withOpacity(0.02)
                    : Colors.transparent,
          ),
          children: row.map((cell) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                cell.isEmpty ? '—' : cell,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight:
                      rowIdx == 0 ? FontWeight.w700 : FontWeight.normal,
                  color: rowIdx == 0
                      ? const Color(0xFF6C63FF)
                      : Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  /// === Exporting View ===
  Widget _buildExportingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Generating Excel...',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Writing data & styling cells',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  /// === Success View ===
  Widget _buildSuccessView() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D9A6).withOpacity(0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D9A6).withOpacity(0.1),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: Color(0xFF00D9A6),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Export Successful! 🎉',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your Excel file has been saved',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 20),

                // File path display
                if (_savedFilePath != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2333),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFF6C63FF),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _savedFilePath!,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // Share button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _shareFile,
                    icon: const Icon(Icons.share_rounded, size: 22),
                    label: const Text('Share File 📤'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 6,
                      shadowColor:
                          const Color(0xFF6C63FF).withOpacity(0.3),
                      textStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // New Scan button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Pop all routes and go back to home
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (route) => false);
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: const Text('New Scan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
                Icons.error_outline_rounded,
                size: 48,
                color: Color(0xFFFF6B6B),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generateAndSaveExcel,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Export'),
            ),
          ],
        ),
      ),
    );
  }
}
