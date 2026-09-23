enum BuddyStatus { online, busy, offline, invisible }
enum BuddyGender { male, female, unspecified }

class Buddy {
  final String username;
  final String? statusMessage;
  final BuddyStatus status;
  final String group;
  final BuddyGender gender;
  final bool hasSpeakerEnabled;

  const Buddy({
    required this.username,
    this.statusMessage,
    this.status = BuddyStatus.online,
    this.group = 'Teman',
    this.gender = BuddyGender.unspecified,
    this.hasSpeakerEnabled = false,
  });
}
