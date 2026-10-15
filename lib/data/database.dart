
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(
        min: 1,
        max: 30,
      )();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [UserProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'clove_db'));

  static final AppDatabase instance = AppDatabase();

  @override
  int get schemaVersion => 1;

  /// Returns the saved profile, or null on the first launch.
  Future<UserProfile?> getProfile() async {
    return (select(userProfiles)
          ..orderBy([(profile) => OrderingTerm.asc(profile.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Saves the user's name, updating the existing profile if present.
  Future<void> saveProfile(String name) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty || normalizedName.length > 30) {
      throw ArgumentError('Name must be between 1 and 30 characters.');
    }

    await transaction(() async {
      final existing = await getProfile();

      if (existing == null) {
        await into(userProfiles).insert(
          UserProfilesCompanion.insert(name: normalizedName),
        );
      } else {
        await (update(userProfiles)
              ..where((profile) => profile.id.equals(existing.id)))
            .write(
          UserProfilesCompanion(name: Value(normalizedName)),
        );
      }
    });
  }
}
