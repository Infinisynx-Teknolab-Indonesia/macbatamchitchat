import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';

/// Simple 2-step "Add Contact" wizard: enter ID + pick a group, then an
/// optional intro message, then Finish. Returns the new contact info via
/// [Navigator.pop] so the caller (BuddyListScreen) can add it to state.
class AddContactDialog extends StatefulWidget {
  final List<String> availableGroups;
  const AddContactDialog({super.key, required this.availableGroups});

  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  int _step = 0;
  final _idCtrl = TextEditingController();
  final _messageCtrl = TextEditingController(
    text: "Hai, aku mau tambahkan kamu sebagai kontak di Batam ChitChat.",
  );
  late String _selectedGroup;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.availableGroups.first;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ymBorderRadius)),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: YmColors.accentPurple),
                  const SizedBox(width: 8),
                  const Text('Tambah Kontak', style: YmTextStyles.username),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 12),
              if (_step == 0) ..._buildStepOne() else ..._buildStepTwo(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepOne() {
    return [
      const Text('Username atau email', style: YmTextStyles.label),
      const SizedBox(height: 4),
      TextField(
        controller: _idCtrl,
        style: YmTextStyles.chatText,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          filled: true,
          fillColor: YmColors.panelBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: YmColors.borderLavender)),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Simpan ke grup', style: YmTextStyles.label),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        value: _selectedGroup,
        items: [for (final g in widget.availableGroups) DropdownMenuItem(value: g, child: Text(g))],
        onChanged: (v) => setState(() => _selectedGroup = v!),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          filled: true,
          fillColor: YmColors.panelBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: YmColors.borderLavender)),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: _idCtrl.text.trim().isEmpty ? null : () => setState(() => _step = 1),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildStepTwo() {
    return [
      Text('Kirim pesan perkenalan ke "${_idCtrl.text.trim()}"', style: YmTextStyles.label),
      const SizedBox(height: 6),
      TextField(
        controller: _messageCtrl,
        maxLines: 3,
        style: YmTextStyles.chatText,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.all(10),
          filled: true,
          fillColor: YmColors.panelBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: YmColors.borderLavender)),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Kembali')),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: YmColors.accentPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop({
              'username': _idCtrl.text.trim(),
              'group': _selectedGroup,
              'message': _messageCtrl.text.trim(),
            }),
            child: const Text('Selesai'),
          ),
        ],
      ),
    ];
  }
}
