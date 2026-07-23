import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Snaps [raw] to the nearest [step] increment within [min]..[sliderMax].
int snapSteppedValue({
  required int raw,
  required int min,
  required int sliderMax,
  int step = 1,
}) {
  if (step <= 1) return raw.clamp(min, sliderMax);
  final snapped = ((raw - min) / step).round() * step + min;
  return snapped.clamp(min, sliderMax);
}

/// Slider capped at [sliderMax]; text field accepts any value ≥ [min].
class SteppedValuePicker extends StatefulWidget {
  final int value;
  final int min;
  final int sliderMax;
  final int step;
  final String suffix;
  final ValueChanged<int>? onChanged;
  final ValueChanged<int>? onCommit;

  const SteppedValuePicker({
    super.key,
    required this.value,
    required this.min,
    required this.sliderMax,
    this.step = 1,
    this.suffix = '',
    this.onChanged,
    this.onCommit,
  });

  @override
  State<SteppedValuePicker> createState() => _SteppedValuePickerState();
}

class _SteppedValuePickerState extends State<SteppedValuePicker> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(SteppedValuePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = '${widget.value}';
      _errorText = null;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  int _snapForSlider(int raw) => snapSteppedValue(
        raw: raw,
        min: widget.min,
        sliderMax: widget.sliderMax,
        step: widget.step,
      );

  /// Commits the text field; returns the new value if accepted.
  int? commitPending() => _commitText();

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitText();
    }
  }

  int? _commitText() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() {
        _controller.text = '${widget.value}';
        _errorText = null;
      });
      return widget.value;
    }
    if (parsed < widget.min) {
      setState(() {
        _errorText = 'At least ${widget.min}';
      });
      return null;
    }
    setState(() {
      _controller.text = '$parsed';
      _errorText = null;
    });
    if (parsed != widget.value) {
      widget.onChanged?.call(parsed);
      widget.onCommit?.call(parsed);
    }
    return parsed;
  }

  void _setFromSlider(double v) {
    final next = _snapForSlider(v.round());
    _controller.text = '$next';
    widget.onChanged?.call(next);
  }

  double get _sliderValue =>
      widget.value.clamp(widget.min, widget.sliderMax).toDouble();

  int get _divisions {
    if (widget.step <= 1) return widget.sliderMax - widget.min;
    return ((widget.sliderMax - widget.min) / widget.step).round();
  }

  @override
  Widget build(BuildContext context) {
    final suffix = widget.suffix.trim();
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 88,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _errorText != null
                          ? Theme.of(context).colorScheme.error
                          : AppTheme.divider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _errorText != null
                          ? Theme.of(context).colorScheme.error
                          : AppTheme.accent,
                    ),
                  ),
                ),
                onSubmitted: (_) => _commitText(),
              ),
            ),
            if (suffix.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                suffix,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Slider(
          value: _sliderValue,
          min: widget.min.toDouble(),
          max: widget.sliderMax.toDouble(),
          divisions: _divisions,
          label: '${widget.value}',
          onChanged: _setFromSlider,
          onChangeEnd: (v) => widget.onCommit?.call(_snapForSlider(v.round())),
        ),
      ],
    );
  }
}

/// Dialog wrapper around [SteppedValuePicker].
Future<int?> showSteppedValuePickerDialog(
  BuildContext context, {
  required String title,
  required int initial,
  required int min,
  required int sliderMax,
  int step = 1,
  String suffix = '',
}) {
  var value = initial < min ? min : initial;
  final pickerKey = GlobalKey<_SteppedValuePickerState>();

  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SteppedValuePicker(
          key: pickerKey,
          value: value,
          min: min,
          sliderMax: sliderMax,
          step: step,
          suffix: suffix,
          onChanged: (v) => setState(() => value = v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final next = pickerKey.currentState?.commitPending();
              if (next == null) return;
              Navigator.pop(ctx, next);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
