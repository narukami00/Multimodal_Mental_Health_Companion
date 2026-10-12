import 'package:flutter/material.dart';

import '../../core/models/emergency_contact.dart';
import '../../core/theme/solace_palette.dart';
import '../../services/dialer_service.dart';
import '../profile/profile_controller.dart';

/// Lets the user keep their own support numbers on the device.
///
/// Every number here is user-entered. Solace does not verify numbers, does not
/// call anyone on the user's behalf, and never notifies a contact
/// automatically.
class CareContactsPage extends StatelessWidget {
  const CareContactsPage({
    required this.profileController,
    this.dialer = const DialerService(),
    super.key,
  });

  final ProfileController profileController;
  final DialerService dialer;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profileController,
      builder: (context, _) {
        final contacts = profileController.profile.emergencyContacts;

        return Scaffold(
          backgroundColor: SolaceColors.from(context).background,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: contacts.isEmpty
                      ? const _EmptyContacts()
                      : ListView(
                          // Same 22px inset as the main pages, so cards line
                          // up app-wide.
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                          children: [
                            for (final contact in contacts)
                              _ContactCard(
                                key: ValueKey('contact-${contact.id}'),
                                contact: contact,
                                onCall: () => _call(context, contact),
                                onEdit: () => _editContact(context, contact),
                                onDelete: () =>
                                    _confirmDelete(context, contact),
                                onMakeIce: contact.isIce
                                    ? null
                                    : () => profileController
                                          .saveEmergencyContact(
                                            contact.copyWith(isIce: true),
                                          ),
                              ),
                          ],
                        ),
                ),
                _buildAddButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF3A3125),
              minimumSize: const Size(44, 44),
              backgroundColor: const Color(0xFFFFFDF6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your people',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A3125),
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Numbers you add stay on this device.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF93887A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          key: const ValueKey('add-contact'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFB534),
            foregroundColor: const Color(0xFF3D2E14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _editContact(context, null),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text(
            'Add a contact',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext context, EmergencyContact contact) async {
    final opened = await dialer.openDialer(contact.phone);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No dialer available on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _editContact(
    BuildContext context,
    EmergencyContact? existing,
  ) async {
    final result = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactEditorSheet(existing: existing),
    );
    if (result == null) return;
    await profileController.saveEmergencyContact(result);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    EmergencyContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this contact?'),
        content: Text('${contact.name} will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await profileController.removeEmergencyContact(contact.id);
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0x24FFB534),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Icon(
                  Icons.people_outline_rounded,
                  size: 32,
                  color: Color(0xFFB26E0F),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No one saved yet',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A3125),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add someone you trust, or a local helpline you want within reach. '
              'Nothing is shared, and nothing is called for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: Color(0xFF7B6A55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
    required this.onMakeIce,
    super.key,
  });

  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Null when this contact is already the call-first contact.
  final VoidCallback? onMakeIce;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: contact.isIce
              ? const Color(0xFFFFB534)
              : const Color(0xFFF7F2E6),
          width: contact.isIce ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14785C28),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF3B3327),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.phone,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93887A),
                      ),
                    ),
                  ],
                ),
              ),
              if (contact.isIce)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3DC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Call first',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB57A12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton.icon(
                    key: ValueKey('call-${contact.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB534),
                      foregroundColor: const Color(0xFF3D2E14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded, size: 17),
                    label: const Text(
                      'Call',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined, size: 19),
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFF8E8272),
                  minimumSize: const Size(42, 42),
                  backgroundColor: const Color(0xFFFFFDF6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFB4522C),
                  minimumSize: const Size(42, 42),
                  backgroundColor: const Color(0xFFFFF4EE),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ],
          ),
          if (onMakeIce != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onMakeIce,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF96620C),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.bolt_outlined, size: 16),
              label: const Text(
                'Make this my call-first contact',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Add or edit sheet for a support contact.
class _ContactEditorSheet extends StatefulWidget {
  const _ContactEditorSheet({this.existing});

  final EmergencyContact? existing;

  @override
  State<_ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<_ContactEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late bool _ice;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _ice = widget.existing?.isIce ?? false;
    _name.addListener(_onChanged);
    _phone.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    final id =
        widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.of(context).pop(
      EmergencyContact(
        id: id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        isIce: _ice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFDF8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFE2D6C0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.existing == null ? 'Add a contact' : 'Edit contact',
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3B3327),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Saved only on this device. Solace never calls anyone for you.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF93887A),
            ),
          ),
          const SizedBox(height: 16),
          _buildField(
            key: const ValueKey('contact-name'),
            controller: _name,
            label: 'Name',
            hint: 'Who is this?',
          ),
          const SizedBox(height: 12),
          _buildField(
            key: const ValueKey('contact-phone'),
            controller: _phone,
            label: 'Phone number',
            hint: 'Include country code if needed',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Call this person first',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B3327),
                  ),
                ),
              ),
              Switch(
                value: _ice,
                activeColor: const Color(0xFFFFB534),
                onChanged: (value) => setState(() => _ice = value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              key: const ValueKey('save-contact'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB534),
                foregroundColor: const Color(0xFF3D2E14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _canSave ? _save : null,
              child: const Text(
                'Save contact',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2D6C0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2D6C0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFB534), width: 1.8),
        ),
      ),
    );
  }
}
