import 'package:flutter/material.dart';

class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? Function(String?)? validator;
  final Function(String)? onAddressSelected;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.labelText,
    this.validator,
    this.onAddressSelected,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // Common South African cities and suburbs for autocomplete
  final List<String> _suggestions = [
    // Major Cities
    'Johannesburg, Gauteng',
    'Cape Town, Western Cape',
    'Durban, KwaZulu-Natal',
    'Pretoria, Gauteng',
    'Port Elizabeth, Eastern Cape',
    'Bloemfontein, Free State',
    'East London, Eastern Cape',
    'Pietermaritzburg, KwaZulu-Natal',
    'Benoni, Gauteng',
    'Vereeniging, Gauteng',
    'Welkom, Free State',
    'Randburg, Gauteng',
    'Roodepoort, Gauteng',
    'Krugersdorp, Gauteng',
    'Alberton, Gauteng',
    'Germiston, Gauteng',
    'Springs, Gauteng',
    'Brakpan, Gauteng',
    'Boksburg, Gauteng',
    'Nigel, Gauteng',

    // Cape Town Areas
    'Bellville, Western Cape',
    'Stellenbosch, Western Cape',
    'Paarl, Western Cape',
    'Worcester, Western Cape',
    'George, Western Cape',
    'Knysna, Western Cape',
    'Mossel Bay, Western Cape',

    // Durban Areas
    'Pinetown, KwaZulu-Natal',
    'Chatsworth, KwaZulu-Natal',
    'Verulam, KwaZulu-Natal',
    'Tongaat, KwaZulu-Natal',

    // Johannesburg Areas
    'Sandton, Gauteng',
    'Rosebank, Gauteng',
    'Parktown, Gauteng',
    'Hyde Park, Gauteng',
    'Melville, Gauteng',
    'Braamfontein, Gauteng',
    'Newtown, Gauteng',
    'Fordsburg, Gauteng',
  ];

  List<String> _filteredSuggestions = [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && widget.controller.text.isNotEmpty) {
      _filterSuggestions(widget.controller.text);
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onTextChange() {
    final text = widget.controller.text;
    if (text.isEmpty) {
      _removeOverlay();
      return;
    }

    _filterSuggestions(text);

    if (_focusNode.hasFocus && _filteredSuggestions.isNotEmpty) {
      _showOverlay();
    } else {
      _removeOverlay();
    }

    // Trigger address parsing for longer inputs
    if (text.length > 10) {
      widget.onAddressSelected?.call(text);
    }
  }

  void _filterSuggestions(String query) {
    final lowercaseQuery = query.toLowerCase();
    _filteredSuggestions = _suggestions
        .where(
          (suggestion) => suggestion.toLowerCase().contains(lowercaseQuery),
        )
        .take(5) // Limit to 5 suggestions
        .toList();
  }

  void _showOverlay() {
    _removeOverlay();

    if (_filteredSuggestions.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height,
        width: size.width,
        child: Material(
          elevation: 4,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _filteredSuggestions[index];
                return InkWell(
                  onTap: () {
                    widget.controller.text = suggestion;
                    widget.onAddressSelected?.call(suggestion);
                    _removeOverlay();
                    _focusNode.unfocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: 'Start typing your city or suburb...',
          suffixIcon: _filteredSuggestions.isNotEmpty && _focusNode.hasFocus
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    widget.controller.clear();
                    _removeOverlay();
                  },
                )
              : null,
        ),
        validator: widget.validator,
      ),
    );
  }
}
