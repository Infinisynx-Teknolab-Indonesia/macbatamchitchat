import 'package:flutter/material.dart';
import '../theme/ym_theme.dart';

class AudibleItem {
  final String label;
  final IconData icon;
  const AudibleItem(this.label, this.icon);
}

/// Marker prefix for audible messages sent through chat — a Unicode
/// Private Use Area character, guaranteed to never appear in normal
/// typed text, so both chat screens can unambiguously tell "this is an
/// audible" apart from someone literally typing similar words. Replaces
/// an earlier version that just inserted plain text like
/// "[Audible: Tepuk Tangan]" into the composer — which the RECEIVING
/// side rendered as literal text with no icon, matching the "cuma
/// tulisan doang, mana iconnya" complaint. Now both label AND icon
/// travel together and the receiving bubble renders a proper chip.
const String audibleMessagePrefix = '\uE000AUDIBLE';
const String audibleMessageSeparator = '\u241F'; // unlikely-to-collide separator

String encodeAudibleMessage(AudibleItem item) =>
    '$audibleMessagePrefix$audibleMessageSeparator${item.label}$audibleMessageSeparator${item.icon.codePoint}';

/// Returns the decoded AudibleItem if [message] is an audible-encoded
/// string, or null if it's just a normal chat message.
AudibleItem? decodeAudibleMessage(String message) {
  if (!message.startsWith(audibleMessagePrefix)) return null;
  final parts = message.split(audibleMessageSeparator);
  if (parts.length != 3) return null;
  final label = parts[1];
  final codePoint = int.tryParse(parts[2]);
  if (codePoint == null) return null;
  // Cocokkan ke salah satu icon TETAP di EmoticonPicker._audibles, JANGAN
  // membuat IconData baru dari angka sembarangan (`IconData(codePoint,
  // fontFamily: 'MaterialIcons')` yang lama). `flutter build --release`
  // menyusutkan (tree-shake) font Material Icons berdasarkan pemakaian
  // IconData yang bisa dilacak secara STATIS saat compile — IconData yang
  // dibuat dari variabel runtime tidak bisa dilacak begitu, dan itu
  // sebabnya build release gagal dengan error "Avoid non-constant
  // invocations of IconData" (build debug tidak kena karena tree-shaking
  // cuma jalan di release/profile). Himpunan audible memang tetap dan
  // sudah diketahui semua dari awal, jadi cukup dicocokkan ke situ.
  for (final a in EmoticonPicker._audibles) {
    if (a.icon.codePoint == codePoint) {
      return AudibleItem(label, a.icon);
    }
  }
  return null; // codePoint tak dikenali (mis. audible baru dari versi lebih baru) -> jangan dianggap audible
}

/// Two-tab picker: Emoticons (inserted inline as text/emoji) and Audibles
/// (bigger "icon + sound" reactions sent as their own recognizable chat
/// message — see encodeAudibleMessage/decodeAudibleMessage above). We
/// don't ship licensed per-audible sound files, so every audible reuses
/// the same synthesized buzz.wav for its "ding" — distinct animated
/// icon/label per audible, shared sound, rather than silence.
class EmoticonPicker extends StatefulWidget {
  final ValueChanged<String> onPicked;
  final ValueChanged<String>? onAudiblePicked;

  const EmoticonPicker({super.key, required this.onPicked, this.onAudiblePicked});

  static const _emojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
    '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
    '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
    '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔',
    '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🥵', '🥶', '🥴',
    '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁',
    '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥',
    '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱',
    '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '💩', '🤡', '👻',
    '👍', '👎', '👏', '🙌', '🤝', '🙏', '💪', '✌️', '🤞', '👌',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💔', '❣️', '💕',
    '🔥', '✨', '🎉', '🎊', '🎁', '🌟', '⭐', '💯', '☕', '🍕',
  ];

  static const _audibles = [
    AudibleItem('Tepuk Tangan', Icons.front_hand_rounded),
    AudibleItem('Tawa Ngakak', Icons.sentiment_very_satisfied_rounded),
    AudibleItem('Drum Roll', Icons.music_note_rounded),
    AudibleItem('Peluk', Icons.favorite_rounded),
    AudibleItem('Kejutan!', Icons.celebration_rounded),
    AudibleItem('Krik Krik', Icons.nightlight_round),
    AudibleItem('Bel', Icons.notifications_active_rounded),
    AudibleItem('Toast', Icons.emoji_food_beverage_rounded),
  ];

  @override
  State<EmoticonPicker> createState() => _EmoticonPickerState();
}

class _EmoticonPickerState extends State<EmoticonPicker> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 260,
      decoration: BoxDecoration(
        color: YmColors.contentBackground,
        borderRadius: BorderRadius.circular(ymBorderRadius),
        border: Border.all(color: YmColors.borderLavender),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Material(
        // ListTile (in the Audibles tab below) paints its ink splashes on
        // the nearest Material ancestor — without this, the outer
        // Container's own background/border/shadow (the DecoratedBox
        // above) blocks that, and Flutter throws an assertion for it.
        color: Colors.transparent,
        child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: YmColors.accentPurple,
            unselectedLabelColor: YmColors.textMuted,
            indicatorColor: YmColors.accentPurple,
            labelStyle: const TextStyle(fontSize: 12),
            tabs: const [Tab(text: 'Emoticon'), Tab(text: 'Audibles')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildEmoticonGrid(), _buildAudiblesList()],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildEmoticonGrid() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: EmoticonPicker._emojis.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
        itemBuilder: (context, i) => InkWell(
          onTap: () => widget.onPicked(EmoticonPicker._emojis[i]),
          borderRadius: BorderRadius.circular(4),
          child: Center(child: Text(EmoticonPicker._emojis[i], style: const TextStyle(fontSize: 18))),
        ),
      ),
    );
  }

  Widget _buildAudiblesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: EmoticonPicker._audibles.length,
      itemBuilder: (context, i) {
        final a = EmoticonPicker._audibles[i];
        return ListTile(
          dense: true,
          leading: Icon(a.icon, color: YmColors.accentPurple, size: 20),
          title: Text(a.label, style: YmTextStyles.chatText),
          // Sends the ENCODED form (icon + label together) — this is what
          // lets the receiving side render a real icon+label chip instead
          // of plain bracketed text.
          onTap: () => (widget.onAudiblePicked ?? widget.onPicked).call(encodeAudibleMessage(a)),
        );
      },
    );
  }
}
