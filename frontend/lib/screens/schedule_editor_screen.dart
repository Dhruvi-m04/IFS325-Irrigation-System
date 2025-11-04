import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants.dart';
import '../models.dart';
import '../utils.dart';

// ============================================================================
// SCHEDULE EDITOR SCREEN - OPTIMIZED
// ============================================================================
class ScheduleEditorScreen extends StatefulWidget {
  final IrrigationSchedule? schedule;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  const ScheduleEditorScreen({super.key, this.schedule, required this.onSave, this.onDelete});

  @override
  State<ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<ScheduleEditorScreen> {
  late TimeOfDay _selectedTime;
  late Duration _selectedDuration;
  late String _scheduleName;
  late List<bool> _repeatDays;
  DateTime? _selectedDate;

  final TextEditingController _nameController = TextEditingController();
  static const List<String> _dayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.schedule != null;
    
    _selectedTime = widget.schedule?.time ?? TimeOfDay.now();
    _selectedDuration = widget.schedule?.duration ?? const Duration(minutes: 15);
    _scheduleName = widget.schedule?.name ?? 'Irrigation';
    _repeatDays = List.from(widget.schedule?.repeatDays ?? List.filled(7, false));
    
    if(widget.schedule != null && !widget.schedule!.repeatDays.any((d) => d)) {
        if (widget.schedule!.name.startsWith('One-time on')) {
           try {
             String dateStr = widget.schedule!.name.replaceFirst('One-time on ', '');
             _selectedDate = DateFormat('MMM d, yyyy').parse(dateStr);
           } catch(e) { /* ignore */ }
        }
    }

     _nameController.text = (widget.schedule != null && !widget.schedule!.name.startsWith('One-time on') && widget.schedule!.name != 'Scheduled Irrigation')
                           ? widget.schedule!.name
                           : '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(primaryColor),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(primaryColor),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _pickDuration() async {
    int selectedHours = _selectedDuration.inHours.clamp(0, 23);
    int selectedMinutes = _selectedDuration.inMinutes % 60;

    final hourController = FixedExtentScrollController(initialItem: selectedHours);
    final minuteController = FixedExtentScrollController(initialItem: selectedMinutes);

    final int? newTotalMinutes = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext context) {
        final numberStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 22);
        final labelStyle = numberStyle?.copyWith(fontSize: 18, fontWeight: FontWeight.normal, color: Theme.of(context).textTheme.bodySmall?.color);

        return SizedBox(
          height: 280,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Set Duration', style: Theme.of(context).textTheme.titleLarge),
                    TextButton(
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(primaryColor),
                        ),
                      ),
                      onPressed: () {
                        final totalMinutes = (selectedHours * 60) + selectedMinutes;
                        Navigator.of(context).pop(totalMinutes == 0 ? 1 : totalMinutes);
                      },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: const Color(primaryColor).withOpacity(0.2)),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 70,
                        child: CupertinoPicker(
                          looping: true,
                          itemExtent: 40.0,
                          scrollController: hourController,
                          onSelectedItemChanged: (index) {
                            selectedHours = index;
                          },
                          children: List<Widget>.generate(24, (index) {
                            return Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: numberStyle,
                              ),
                            );
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0, right: 16.0),
                        child: Text('hours', style: labelStyle),
                      ),
                      SizedBox(
                        width: 70,
                        child: CupertinoPicker(
                          looping: true,
                          itemExtent: 40.0,
                          scrollController: minuteController,
                          onSelectedItemChanged: (index) {
                            selectedMinutes = index;
                          },
                          children: List<Widget>.generate(60, (index) {
                            return Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: numberStyle,
                              ),
                            );
                          }),
                        ),
                      ),
                       Padding(
                         padding: const EdgeInsets.only(left: 4.0),
                         child: Text('min', style: labelStyle),
                       ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (newTotalMinutes != null) {
      setState(() {
        _selectedDuration = Duration(minutes: newTotalMinutes);
      });
    }
  }

  Future<void> _saveSchedule() async {
    final DateTime dateToSend = _selectedDate ?? DateTime.now();

    final runDateTime = DateTime(
        dateToSend.year,
        dateToSend.month,
        dateToSend.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

    bool repeats = _repeatDays.any((day) => day == true);
    
    if (!repeats && _selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text('Please select a Start Date for one-time schedules.'),
             backgroundColor: Color(warningColor),
           ),
        );
        return;
    }

    if (!repeats && runDateTime.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text('Cannot schedule a non-repeating event in the past.'),
             backgroundColor: Color(warningColor),
           ),
        );
        return;
    }

    setState(() => _isLoading = true);

    try {
      const dayMap = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
      final List<String> repeatDaysList = [];
      for (int i = 0; i < _repeatDays.length; i++) {
        if (_repeatDays[i]) repeatDaysList.add(dayMap[i]);
      }
      
      final String repeatDaysStr;
      if (repeats) {
        repeatDaysStr = repeatDaysList.join(',');
      } else {
        repeatDaysStr = DateFormat('yyyy-MM-dd').format(dateToSend);
      }

      final String nameToSend = _nameController.text.trim().isNotEmpty
                                ? _nameController.text.trim()
                                : 'Scheduled Irrigation';

      final http.Response response;
      
      if (_isEditing) {
        // UPDATE existing schedule
        response = await http.put(
          Uri.parse('$backendBaseUrl/schedule/update/${widget.schedule!.id}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'start_time_of_day': '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00',
            'duration_minutes': _selectedDuration.inMinutes,
            'repeat_days': repeatDaysStr.isEmpty ? null : repeatDaysStr,
            'name': nameToSend,
          }),
        ).timeout(const Duration(seconds: 10));
      } else {
        // CREATE new schedule
        response = await http.post(
          Uri.parse('$backendBaseUrl/schedule/create'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'action': 'ON',
            'run_time': runDateTime.toIso8601String(),
            'duration_minutes': _selectedDuration.inMinutes,
            'repeat_days': repeatDaysStr.isEmpty ? null : repeatDaysStr,
            'name': nameToSend,
          }),
        ).timeout(const Duration(seconds: 10));
      }

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        widget.onSave();
        if (mounted) Navigator.of(context).pop();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to ${_isEditing ? 'update' : 'save'}: ${response.statusCode} ${response.body}'),
              backgroundColor: const Color(errorColor),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${_isEditing ? 'updating' : 'saving'} schedule: $e'),
            backgroundColor: const Color(errorColor),
          ),
        );
      }
    }
  }

  void _confirmDelete() {
     if (widget.onDelete != null) {
       widget.onDelete!();
     }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Schedule' : 'Add Schedule'),
        backgroundColor: const Color(primaryColor),
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Schedule Name",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(primaryColor),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: "e.g., 'Morning Watering'",
                    prefixIcon: const Icon(Icons.label_outline, color: Color(primaryColor)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(primaryColor), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  "Time & Duration",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(primaryColor),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      _buildDateTimePickerTile(
                        icon: Icons.calendar_today_outlined,
                        label: "Start Date",
                        value: _selectedDate == null ? "Optional (Repeats)" : DateFormat('EEE, MMM d, yyyy').format(_selectedDate!),
                        onTap: _pickDate,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildDateTimePickerTile(
                        icon: Icons.access_time_outlined,
                        label: "Start Time",
                        value: _selectedTime.format(context),
                        onTap: _pickTime,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildDateTimePickerTile(
                        icon: Icons.timer_outlined,
                        label: "Duration",
                        value: formatScheduleDuration(_selectedDuration),
                        onTap: _pickDuration,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  "Repeat",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(primaryColor),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDaySelector(),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _repeatDays.any((d) => d) ? "Repeats on selected days." : "Runs once.",
                    style: textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha(230),
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(primaryColor),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'Update Schedule' : 'Save Schedule'),
              ),
            ),
          ),

           if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(primaryColor),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateTimePickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    Color? valueColor,
  }) {
     return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            Icon(icon, color: const Color(primaryColor).withOpacity(onTap != null ? 1.0 : 0.5)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label, 
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).textTheme.titleMedium?.color?.withOpacity(onTap != null ? 1.0 : 0.5)
                )
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: valueColor ?? (onTap != null 
                    ? Theme.of(context).colorScheme.onSurfaceVariant 
                    : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                ),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Theme.of(context).iconTheme.color?.withOpacity(onTap != null ? 0.5 : 0.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
     return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        return FilterChip(
          label: Text(_dayLetters[index]),
          selected: _repeatDays[index],
          onSelected: (selected) {
            setState(() {
              _repeatDays[index] = selected;
            });
          },
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(8),
          labelStyle: TextStyle(
            fontWeight: FontWeight.bold,
            color: _repeatDays[index]
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          selectedColor: const Color(primaryColor),
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          showCheckmark: false,
          side: BorderSide.none,
        );
      }),
    );
  }
}