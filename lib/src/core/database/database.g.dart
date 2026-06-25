// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BlockedAppsTable extends BlockedApps
    with TableInfo<$BlockedAppsTable, BlockedApp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockedAppsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isBlockedMeta =
      const VerificationMeta('isBlocked');
  @override
  late final GeneratedColumn<bool> isBlocked = GeneratedColumn<bool>(
      'is_blocked', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_blocked" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
      'added_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: Constant(DateTime.now().millisecondsSinceEpoch));
  @override
  List<GeneratedColumn> get $columns =>
      [packageName, displayName, isBlocked, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blocked_apps';
  @override
  VerificationContext validateIntegrity(Insertable<BlockedApp> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_blocked')) {
      context.handle(_isBlockedMeta,
          isBlocked.isAcceptableOrUnknown(data['is_blocked']!, _isBlockedMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packageName};
  @override
  BlockedApp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockedApp(
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      isBlocked: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_blocked'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $BlockedAppsTable createAlias(String alias) {
    return $BlockedAppsTable(attachedDatabase, alias);
  }
}

class BlockedApp extends DataClass implements Insertable<BlockedApp> {
  final String packageName;
  final String displayName;
  final bool isBlocked;
  final int addedAt;
  const BlockedApp(
      {required this.packageName,
      required this.displayName,
      required this.isBlocked,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['package_name'] = Variable<String>(packageName);
    map['display_name'] = Variable<String>(displayName);
    map['is_blocked'] = Variable<bool>(isBlocked);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  BlockedAppsCompanion toCompanion(bool nullToAbsent) {
    return BlockedAppsCompanion(
      packageName: Value(packageName),
      displayName: Value(displayName),
      isBlocked: Value(isBlocked),
      addedAt: Value(addedAt),
    );
  }

  factory BlockedApp.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockedApp(
      packageName: serializer.fromJson<String>(json['packageName']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isBlocked: serializer.fromJson<bool>(json['isBlocked']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packageName': serializer.toJson<String>(packageName),
      'displayName': serializer.toJson<String>(displayName),
      'isBlocked': serializer.toJson<bool>(isBlocked),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  BlockedApp copyWith(
          {String? packageName,
          String? displayName,
          bool? isBlocked,
          int? addedAt}) =>
      BlockedApp(
        packageName: packageName ?? this.packageName,
        displayName: displayName ?? this.displayName,
        isBlocked: isBlocked ?? this.isBlocked,
        addedAt: addedAt ?? this.addedAt,
      );
  BlockedApp copyWithCompanion(BlockedAppsCompanion data) {
    return BlockedApp(
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      isBlocked: data.isBlocked.present ? data.isBlocked.value : this.isBlocked,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockedApp(')
          ..write('packageName: $packageName, ')
          ..write('displayName: $displayName, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packageName, displayName, isBlocked, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockedApp &&
          other.packageName == this.packageName &&
          other.displayName == this.displayName &&
          other.isBlocked == this.isBlocked &&
          other.addedAt == this.addedAt);
}

class BlockedAppsCompanion extends UpdateCompanion<BlockedApp> {
  final Value<String> packageName;
  final Value<String> displayName;
  final Value<bool> isBlocked;
  final Value<int> addedAt;
  final Value<int> rowid;
  const BlockedAppsCompanion({
    this.packageName = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockedAppsCompanion.insert({
    required String packageName,
    required String displayName,
    this.isBlocked = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : packageName = Value(packageName),
        displayName = Value(displayName);
  static Insertable<BlockedApp> custom({
    Expression<String>? packageName,
    Expression<String>? displayName,
    Expression<bool>? isBlocked,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packageName != null) 'package_name': packageName,
      if (displayName != null) 'display_name': displayName,
      if (isBlocked != null) 'is_blocked': isBlocked,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockedAppsCompanion copyWith(
      {Value<String>? packageName,
      Value<String>? displayName,
      Value<bool>? isBlocked,
      Value<int>? addedAt,
      Value<int>? rowid}) {
    return BlockedAppsCompanion(
      packageName: packageName ?? this.packageName,
      displayName: displayName ?? this.displayName,
      isBlocked: isBlocked ?? this.isBlocked,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isBlocked.present) {
      map['is_blocked'] = Variable<bool>(isBlocked.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockedAppsCompanion(')
          ..write('packageName: $packageName, ')
          ..write('displayName: $displayName, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlockRulesTable extends BlockRules
    with TableInfo<$BlockRulesTable, BlockRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _cardsRequiredMeta =
      const VerificationMeta('cardsRequired');
  @override
  late final GeneratedColumn<int> cardsRequired = GeneratedColumn<int>(
      'cards_required', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(10));
  static const VerificationMeta _dailyCardsGoalMeta =
      const VerificationMeta('dailyCardsGoal');
  @override
  late final GeneratedColumn<int> dailyCardsGoal = GeneratedColumn<int>(
      'daily_cards_goal', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(30));
  static const VerificationMeta _unlockDurationMinutesMeta =
      const VerificationMeta('unlockDurationMinutes');
  @override
  late final GeneratedColumn<int> unlockDurationMinutes = GeneratedColumn<int>(
      'unlock_duration_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(10));
  static const VerificationMeta _bypassEnabledMeta =
      const VerificationMeta('bypassEnabled');
  @override
  late final GeneratedColumn<bool> bypassEnabled = GeneratedColumn<bool>(
      'bypass_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("bypass_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _bypassDailyCapMeta =
      const VerificationMeta('bypassDailyCap');
  @override
  late final GeneratedColumn<int> bypassDailyCap = GeneratedColumn<int>(
      'bypass_daily_cap', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(2));
  static const VerificationMeta _bypassSecondsMeta =
      const VerificationMeta('bypassSeconds');
  @override
  late final GeneratedColumn<int> bypassSeconds = GeneratedColumn<int>(
      'bypass_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(60));
  static const VerificationMeta _isEnabledMeta =
      const VerificationMeta('isEnabled');
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
      'is_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: Constant(DateTime.now().millisecondsSinceEpoch));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        cardsRequired,
        dailyCardsGoal,
        unlockDurationMinutes,
        bypassEnabled,
        bypassDailyCap,
        bypassSeconds,
        isEnabled,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'block_rules';
  @override
  VerificationContext validateIntegrity(Insertable<BlockRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cards_required')) {
      context.handle(
          _cardsRequiredMeta,
          cardsRequired.isAcceptableOrUnknown(
              data['cards_required']!, _cardsRequiredMeta));
    }
    if (data.containsKey('daily_cards_goal')) {
      context.handle(
          _dailyCardsGoalMeta,
          dailyCardsGoal.isAcceptableOrUnknown(
              data['daily_cards_goal']!, _dailyCardsGoalMeta));
    }
    if (data.containsKey('unlock_duration_minutes')) {
      context.handle(
          _unlockDurationMinutesMeta,
          unlockDurationMinutes.isAcceptableOrUnknown(
              data['unlock_duration_minutes']!, _unlockDurationMinutesMeta));
    }
    if (data.containsKey('bypass_enabled')) {
      context.handle(
          _bypassEnabledMeta,
          bypassEnabled.isAcceptableOrUnknown(
              data['bypass_enabled']!, _bypassEnabledMeta));
    }
    if (data.containsKey('bypass_daily_cap')) {
      context.handle(
          _bypassDailyCapMeta,
          bypassDailyCap.isAcceptableOrUnknown(
              data['bypass_daily_cap']!, _bypassDailyCapMeta));
    }
    if (data.containsKey('bypass_seconds')) {
      context.handle(
          _bypassSecondsMeta,
          bypassSeconds.isAcceptableOrUnknown(
              data['bypass_seconds']!, _bypassSecondsMeta));
    }
    if (data.containsKey('is_enabled')) {
      context.handle(_isEnabledMeta,
          isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BlockRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      cardsRequired: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cards_required'])!,
      dailyCardsGoal: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}daily_cards_goal'])!,
      unlockDurationMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}unlock_duration_minutes'])!,
      bypassEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}bypass_enabled'])!,
      bypassDailyCap: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bypass_daily_cap'])!,
      bypassSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bypass_seconds'])!,
      isEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_enabled'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $BlockRulesTable createAlias(String alias) {
    return $BlockRulesTable(attachedDatabase, alias);
  }
}

class BlockRule extends DataClass implements Insertable<BlockRule> {
  final int id;
  final int cardsRequired;
  final int dailyCardsGoal;
  final int unlockDurationMinutes;
  final bool bypassEnabled;
  final int bypassDailyCap;
  final int bypassSeconds;
  final bool isEnabled;
  final int updatedAt;
  const BlockRule(
      {required this.id,
      required this.cardsRequired,
      required this.dailyCardsGoal,
      required this.unlockDurationMinutes,
      required this.bypassEnabled,
      required this.bypassDailyCap,
      required this.bypassSeconds,
      required this.isEnabled,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cards_required'] = Variable<int>(cardsRequired);
    map['daily_cards_goal'] = Variable<int>(dailyCardsGoal);
    map['unlock_duration_minutes'] = Variable<int>(unlockDurationMinutes);
    map['bypass_enabled'] = Variable<bool>(bypassEnabled);
    map['bypass_daily_cap'] = Variable<int>(bypassDailyCap);
    map['bypass_seconds'] = Variable<int>(bypassSeconds);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BlockRulesCompanion toCompanion(bool nullToAbsent) {
    return BlockRulesCompanion(
      id: Value(id),
      cardsRequired: Value(cardsRequired),
      dailyCardsGoal: Value(dailyCardsGoal),
      unlockDurationMinutes: Value(unlockDurationMinutes),
      bypassEnabled: Value(bypassEnabled),
      bypassDailyCap: Value(bypassDailyCap),
      bypassSeconds: Value(bypassSeconds),
      isEnabled: Value(isEnabled),
      updatedAt: Value(updatedAt),
    );
  }

  factory BlockRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockRule(
      id: serializer.fromJson<int>(json['id']),
      cardsRequired: serializer.fromJson<int>(json['cardsRequired']),
      dailyCardsGoal: serializer.fromJson<int>(json['dailyCardsGoal']),
      unlockDurationMinutes:
          serializer.fromJson<int>(json['unlockDurationMinutes']),
      bypassEnabled: serializer.fromJson<bool>(json['bypassEnabled']),
      bypassDailyCap: serializer.fromJson<int>(json['bypassDailyCap']),
      bypassSeconds: serializer.fromJson<int>(json['bypassSeconds']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cardsRequired': serializer.toJson<int>(cardsRequired),
      'dailyCardsGoal': serializer.toJson<int>(dailyCardsGoal),
      'unlockDurationMinutes': serializer.toJson<int>(unlockDurationMinutes),
      'bypassEnabled': serializer.toJson<bool>(bypassEnabled),
      'bypassDailyCap': serializer.toJson<int>(bypassDailyCap),
      'bypassSeconds': serializer.toJson<int>(bypassSeconds),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BlockRule copyWith(
          {int? id,
          int? cardsRequired,
          int? dailyCardsGoal,
          int? unlockDurationMinutes,
          bool? bypassEnabled,
          int? bypassDailyCap,
          int? bypassSeconds,
          bool? isEnabled,
          int? updatedAt}) =>
      BlockRule(
        id: id ?? this.id,
        cardsRequired: cardsRequired ?? this.cardsRequired,
        dailyCardsGoal: dailyCardsGoal ?? this.dailyCardsGoal,
        unlockDurationMinutes:
            unlockDurationMinutes ?? this.unlockDurationMinutes,
        bypassEnabled: bypassEnabled ?? this.bypassEnabled,
        bypassDailyCap: bypassDailyCap ?? this.bypassDailyCap,
        bypassSeconds: bypassSeconds ?? this.bypassSeconds,
        isEnabled: isEnabled ?? this.isEnabled,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  BlockRule copyWithCompanion(BlockRulesCompanion data) {
    return BlockRule(
      id: data.id.present ? data.id.value : this.id,
      cardsRequired: data.cardsRequired.present
          ? data.cardsRequired.value
          : this.cardsRequired,
      dailyCardsGoal: data.dailyCardsGoal.present
          ? data.dailyCardsGoal.value
          : this.dailyCardsGoal,
      unlockDurationMinutes: data.unlockDurationMinutes.present
          ? data.unlockDurationMinutes.value
          : this.unlockDurationMinutes,
      bypassEnabled: data.bypassEnabled.present
          ? data.bypassEnabled.value
          : this.bypassEnabled,
      bypassDailyCap: data.bypassDailyCap.present
          ? data.bypassDailyCap.value
          : this.bypassDailyCap,
      bypassSeconds: data.bypassSeconds.present
          ? data.bypassSeconds.value
          : this.bypassSeconds,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockRule(')
          ..write('id: $id, ')
          ..write('cardsRequired: $cardsRequired, ')
          ..write('dailyCardsGoal: $dailyCardsGoal, ')
          ..write('unlockDurationMinutes: $unlockDurationMinutes, ')
          ..write('bypassEnabled: $bypassEnabled, ')
          ..write('bypassDailyCap: $bypassDailyCap, ')
          ..write('bypassSeconds: $bypassSeconds, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      cardsRequired,
      dailyCardsGoal,
      unlockDurationMinutes,
      bypassEnabled,
      bypassDailyCap,
      bypassSeconds,
      isEnabled,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockRule &&
          other.id == this.id &&
          other.cardsRequired == this.cardsRequired &&
          other.dailyCardsGoal == this.dailyCardsGoal &&
          other.unlockDurationMinutes == this.unlockDurationMinutes &&
          other.bypassEnabled == this.bypassEnabled &&
          other.bypassDailyCap == this.bypassDailyCap &&
          other.bypassSeconds == this.bypassSeconds &&
          other.isEnabled == this.isEnabled &&
          other.updatedAt == this.updatedAt);
}

class BlockRulesCompanion extends UpdateCompanion<BlockRule> {
  final Value<int> id;
  final Value<int> cardsRequired;
  final Value<int> dailyCardsGoal;
  final Value<int> unlockDurationMinutes;
  final Value<bool> bypassEnabled;
  final Value<int> bypassDailyCap;
  final Value<int> bypassSeconds;
  final Value<bool> isEnabled;
  final Value<int> updatedAt;
  const BlockRulesCompanion({
    this.id = const Value.absent(),
    this.cardsRequired = const Value.absent(),
    this.dailyCardsGoal = const Value.absent(),
    this.unlockDurationMinutes = const Value.absent(),
    this.bypassEnabled = const Value.absent(),
    this.bypassDailyCap = const Value.absent(),
    this.bypassSeconds = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  BlockRulesCompanion.insert({
    this.id = const Value.absent(),
    this.cardsRequired = const Value.absent(),
    this.dailyCardsGoal = const Value.absent(),
    this.unlockDurationMinutes = const Value.absent(),
    this.bypassEnabled = const Value.absent(),
    this.bypassDailyCap = const Value.absent(),
    this.bypassSeconds = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<BlockRule> custom({
    Expression<int>? id,
    Expression<int>? cardsRequired,
    Expression<int>? dailyCardsGoal,
    Expression<int>? unlockDurationMinutes,
    Expression<bool>? bypassEnabled,
    Expression<int>? bypassDailyCap,
    Expression<int>? bypassSeconds,
    Expression<bool>? isEnabled,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardsRequired != null) 'cards_required': cardsRequired,
      if (dailyCardsGoal != null) 'daily_cards_goal': dailyCardsGoal,
      if (unlockDurationMinutes != null)
        'unlock_duration_minutes': unlockDurationMinutes,
      if (bypassEnabled != null) 'bypass_enabled': bypassEnabled,
      if (bypassDailyCap != null) 'bypass_daily_cap': bypassDailyCap,
      if (bypassSeconds != null) 'bypass_seconds': bypassSeconds,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  BlockRulesCompanion copyWith(
      {Value<int>? id,
      Value<int>? cardsRequired,
      Value<int>? dailyCardsGoal,
      Value<int>? unlockDurationMinutes,
      Value<bool>? bypassEnabled,
      Value<int>? bypassDailyCap,
      Value<int>? bypassSeconds,
      Value<bool>? isEnabled,
      Value<int>? updatedAt}) {
    return BlockRulesCompanion(
      id: id ?? this.id,
      cardsRequired: cardsRequired ?? this.cardsRequired,
      dailyCardsGoal: dailyCardsGoal ?? this.dailyCardsGoal,
      unlockDurationMinutes:
          unlockDurationMinutes ?? this.unlockDurationMinutes,
      bypassEnabled: bypassEnabled ?? this.bypassEnabled,
      bypassDailyCap: bypassDailyCap ?? this.bypassDailyCap,
      bypassSeconds: bypassSeconds ?? this.bypassSeconds,
      isEnabled: isEnabled ?? this.isEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cardsRequired.present) {
      map['cards_required'] = Variable<int>(cardsRequired.value);
    }
    if (dailyCardsGoal.present) {
      map['daily_cards_goal'] = Variable<int>(dailyCardsGoal.value);
    }
    if (unlockDurationMinutes.present) {
      map['unlock_duration_minutes'] =
          Variable<int>(unlockDurationMinutes.value);
    }
    if (bypassEnabled.present) {
      map['bypass_enabled'] = Variable<bool>(bypassEnabled.value);
    }
    if (bypassDailyCap.present) {
      map['bypass_daily_cap'] = Variable<int>(bypassDailyCap.value);
    }
    if (bypassSeconds.present) {
      map['bypass_seconds'] = Variable<int>(bypassSeconds.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockRulesCompanion(')
          ..write('id: $id, ')
          ..write('cardsRequired: $cardsRequired, ')
          ..write('dailyCardsGoal: $dailyCardsGoal, ')
          ..write('unlockDurationMinutes: $unlockDurationMinutes, ')
          ..write('bypassEnabled: $bypassEnabled, ')
          ..write('bypassDailyCap: $bypassDailyCap, ')
          ..write('bypassSeconds: $bypassSeconds, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DailyStatsTable extends DailyStats
    with TableInfo<$DailyStatsTable, DailyStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardsReviewedMeta =
      const VerificationMeta('cardsReviewed');
  @override
  late final GeneratedColumn<int> cardsReviewed = GeneratedColumn<int>(
      'cards_reviewed', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _unlocksEarnedMeta =
      const VerificationMeta('unlocksEarned');
  @override
  late final GeneratedColumn<int> unlocksEarned = GeneratedColumn<int>(
      'unlocks_earned', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _blockedAttemptsMeta =
      const VerificationMeta('blockedAttempts');
  @override
  late final GeneratedColumn<int> blockedAttempts = GeneratedColumn<int>(
      'blocked_attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _bypassesUsedMeta =
      const VerificationMeta('bypassesUsed');
  @override
  late final GeneratedColumn<int> bypassesUsed = GeneratedColumn<int>(
      'bypasses_used', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [date, cardsReviewed, unlocksEarned, blockedAttempts, bypassesUsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_stats';
  @override
  VerificationContext validateIntegrity(Insertable<DailyStat> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('cards_reviewed')) {
      context.handle(
          _cardsReviewedMeta,
          cardsReviewed.isAcceptableOrUnknown(
              data['cards_reviewed']!, _cardsReviewedMeta));
    }
    if (data.containsKey('unlocks_earned')) {
      context.handle(
          _unlocksEarnedMeta,
          unlocksEarned.isAcceptableOrUnknown(
              data['unlocks_earned']!, _unlocksEarnedMeta));
    }
    if (data.containsKey('blocked_attempts')) {
      context.handle(
          _blockedAttemptsMeta,
          blockedAttempts.isAcceptableOrUnknown(
              data['blocked_attempts']!, _blockedAttemptsMeta));
    }
    if (data.containsKey('bypasses_used')) {
      context.handle(
          _bypassesUsedMeta,
          bypassesUsed.isAcceptableOrUnknown(
              data['bypasses_used']!, _bypassesUsedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailyStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyStat(
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      cardsReviewed: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cards_reviewed'])!,
      unlocksEarned: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unlocks_earned'])!,
      blockedAttempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}blocked_attempts'])!,
      bypassesUsed: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bypasses_used'])!,
    );
  }

  @override
  $DailyStatsTable createAlias(String alias) {
    return $DailyStatsTable(attachedDatabase, alias);
  }
}

class DailyStat extends DataClass implements Insertable<DailyStat> {
  final String date;
  final int cardsReviewed;
  final int unlocksEarned;
  final int blockedAttempts;
  final int bypassesUsed;
  const DailyStat(
      {required this.date,
      required this.cardsReviewed,
      required this.unlocksEarned,
      required this.blockedAttempts,
      required this.bypassesUsed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['cards_reviewed'] = Variable<int>(cardsReviewed);
    map['unlocks_earned'] = Variable<int>(unlocksEarned);
    map['blocked_attempts'] = Variable<int>(blockedAttempts);
    map['bypasses_used'] = Variable<int>(bypassesUsed);
    return map;
  }

  DailyStatsCompanion toCompanion(bool nullToAbsent) {
    return DailyStatsCompanion(
      date: Value(date),
      cardsReviewed: Value(cardsReviewed),
      unlocksEarned: Value(unlocksEarned),
      blockedAttempts: Value(blockedAttempts),
      bypassesUsed: Value(bypassesUsed),
    );
  }

  factory DailyStat.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyStat(
      date: serializer.fromJson<String>(json['date']),
      cardsReviewed: serializer.fromJson<int>(json['cardsReviewed']),
      unlocksEarned: serializer.fromJson<int>(json['unlocksEarned']),
      blockedAttempts: serializer.fromJson<int>(json['blockedAttempts']),
      bypassesUsed: serializer.fromJson<int>(json['bypassesUsed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'cardsReviewed': serializer.toJson<int>(cardsReviewed),
      'unlocksEarned': serializer.toJson<int>(unlocksEarned),
      'blockedAttempts': serializer.toJson<int>(blockedAttempts),
      'bypassesUsed': serializer.toJson<int>(bypassesUsed),
    };
  }

  DailyStat copyWith(
          {String? date,
          int? cardsReviewed,
          int? unlocksEarned,
          int? blockedAttempts,
          int? bypassesUsed}) =>
      DailyStat(
        date: date ?? this.date,
        cardsReviewed: cardsReviewed ?? this.cardsReviewed,
        unlocksEarned: unlocksEarned ?? this.unlocksEarned,
        blockedAttempts: blockedAttempts ?? this.blockedAttempts,
        bypassesUsed: bypassesUsed ?? this.bypassesUsed,
      );
  DailyStat copyWithCompanion(DailyStatsCompanion data) {
    return DailyStat(
      date: data.date.present ? data.date.value : this.date,
      cardsReviewed: data.cardsReviewed.present
          ? data.cardsReviewed.value
          : this.cardsReviewed,
      unlocksEarned: data.unlocksEarned.present
          ? data.unlocksEarned.value
          : this.unlocksEarned,
      blockedAttempts: data.blockedAttempts.present
          ? data.blockedAttempts.value
          : this.blockedAttempts,
      bypassesUsed: data.bypassesUsed.present
          ? data.bypassesUsed.value
          : this.bypassesUsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStat(')
          ..write('date: $date, ')
          ..write('cardsReviewed: $cardsReviewed, ')
          ..write('unlocksEarned: $unlocksEarned, ')
          ..write('blockedAttempts: $blockedAttempts, ')
          ..write('bypassesUsed: $bypassesUsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      date, cardsReviewed, unlocksEarned, blockedAttempts, bypassesUsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStat &&
          other.date == this.date &&
          other.cardsReviewed == this.cardsReviewed &&
          other.unlocksEarned == this.unlocksEarned &&
          other.blockedAttempts == this.blockedAttempts &&
          other.bypassesUsed == this.bypassesUsed);
}

class DailyStatsCompanion extends UpdateCompanion<DailyStat> {
  final Value<String> date;
  final Value<int> cardsReviewed;
  final Value<int> unlocksEarned;
  final Value<int> blockedAttempts;
  final Value<int> bypassesUsed;
  final Value<int> rowid;
  const DailyStatsCompanion({
    this.date = const Value.absent(),
    this.cardsReviewed = const Value.absent(),
    this.unlocksEarned = const Value.absent(),
    this.blockedAttempts = const Value.absent(),
    this.bypassesUsed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyStatsCompanion.insert({
    required String date,
    this.cardsReviewed = const Value.absent(),
    this.unlocksEarned = const Value.absent(),
    this.blockedAttempts = const Value.absent(),
    this.bypassesUsed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyStat> custom({
    Expression<String>? date,
    Expression<int>? cardsReviewed,
    Expression<int>? unlocksEarned,
    Expression<int>? blockedAttempts,
    Expression<int>? bypassesUsed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (cardsReviewed != null) 'cards_reviewed': cardsReviewed,
      if (unlocksEarned != null) 'unlocks_earned': unlocksEarned,
      if (blockedAttempts != null) 'blocked_attempts': blockedAttempts,
      if (bypassesUsed != null) 'bypasses_used': bypassesUsed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyStatsCompanion copyWith(
      {Value<String>? date,
      Value<int>? cardsReviewed,
      Value<int>? unlocksEarned,
      Value<int>? blockedAttempts,
      Value<int>? bypassesUsed,
      Value<int>? rowid}) {
    return DailyStatsCompanion(
      date: date ?? this.date,
      cardsReviewed: cardsReviewed ?? this.cardsReviewed,
      unlocksEarned: unlocksEarned ?? this.unlocksEarned,
      blockedAttempts: blockedAttempts ?? this.blockedAttempts,
      bypassesUsed: bypassesUsed ?? this.bypassesUsed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (cardsReviewed.present) {
      map['cards_reviewed'] = Variable<int>(cardsReviewed.value);
    }
    if (unlocksEarned.present) {
      map['unlocks_earned'] = Variable<int>(unlocksEarned.value);
    }
    if (blockedAttempts.present) {
      map['blocked_attempts'] = Variable<int>(blockedAttempts.value);
    }
    if (bypassesUsed.present) {
      map['bypasses_used'] = Variable<int>(bypassesUsed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyStatsCompanion(')
          ..write('date: $date, ')
          ..write('cardsReviewed: $cardsReviewed, ')
          ..write('unlocksEarned: $unlocksEarned, ')
          ..write('blockedAttempts: $blockedAttempts, ')
          ..write('bypassesUsed: $bypassesUsed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InstalledAppsCacheTable extends InstalledAppsCache
    with TableInfo<$InstalledAppsCacheTable, CachedInstalledApp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstalledAppsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isSystemMeta =
      const VerificationMeta('isSystem');
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
      'is_system', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_system" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<Uint8List> icon = GeneratedColumn<Uint8List>(
      'icon', aliasedName, true,
      type: DriftSqlType.blob, requiredDuringInsert: false);
  static const VerificationMeta _usageMsMeta =
      const VerificationMeta('usageMs');
  @override
  late final GeneratedColumn<int> usageMs = GeneratedColumn<int>(
      'usage_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: Constant(DateTime.now().millisecondsSinceEpoch));
  @override
  List<GeneratedColumn> get $columns =>
      [packageName, displayName, isSystem, icon, usageMs, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installed_apps_cache';
  @override
  VerificationContext validateIntegrity(Insertable<CachedInstalledApp> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_system')) {
      context.handle(_isSystemMeta,
          isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta));
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    }
    if (data.containsKey('usage_ms')) {
      context.handle(_usageMsMeta,
          usageMs.isAcceptableOrUnknown(data['usage_ms']!, _usageMsMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {packageName};
  @override
  CachedInstalledApp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedInstalledApp(
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      isSystem: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_system'])!,
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}icon']),
      usageMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}usage_ms'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $InstalledAppsCacheTable createAlias(String alias) {
    return $InstalledAppsCacheTable(attachedDatabase, alias);
  }
}

class CachedInstalledApp extends DataClass
    implements Insertable<CachedInstalledApp> {
  final String packageName;
  final String displayName;
  final bool isSystem;
  final Uint8List? icon;
  final int usageMs;
  final int cachedAt;
  const CachedInstalledApp(
      {required this.packageName,
      required this.displayName,
      required this.isSystem,
      this.icon,
      required this.usageMs,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['package_name'] = Variable<String>(packageName);
    map['display_name'] = Variable<String>(displayName);
    map['is_system'] = Variable<bool>(isSystem);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<Uint8List>(icon);
    }
    map['usage_ms'] = Variable<int>(usageMs);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  InstalledAppsCacheCompanion toCompanion(bool nullToAbsent) {
    return InstalledAppsCacheCompanion(
      packageName: Value(packageName),
      displayName: Value(displayName),
      isSystem: Value(isSystem),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      usageMs: Value(usageMs),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedInstalledApp.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedInstalledApp(
      packageName: serializer.fromJson<String>(json['packageName']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
      icon: serializer.fromJson<Uint8List?>(json['icon']),
      usageMs: serializer.fromJson<int>(json['usageMs']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'packageName': serializer.toJson<String>(packageName),
      'displayName': serializer.toJson<String>(displayName),
      'isSystem': serializer.toJson<bool>(isSystem),
      'icon': serializer.toJson<Uint8List?>(icon),
      'usageMs': serializer.toJson<int>(usageMs),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedInstalledApp copyWith(
          {String? packageName,
          String? displayName,
          bool? isSystem,
          Value<Uint8List?> icon = const Value.absent(),
          int? usageMs,
          int? cachedAt}) =>
      CachedInstalledApp(
        packageName: packageName ?? this.packageName,
        displayName: displayName ?? this.displayName,
        isSystem: isSystem ?? this.isSystem,
        icon: icon.present ? icon.value : this.icon,
        usageMs: usageMs ?? this.usageMs,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedInstalledApp copyWithCompanion(InstalledAppsCacheCompanion data) {
    return CachedInstalledApp(
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
      icon: data.icon.present ? data.icon.value : this.icon,
      usageMs: data.usageMs.present ? data.usageMs.value : this.usageMs,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedInstalledApp(')
          ..write('packageName: $packageName, ')
          ..write('displayName: $displayName, ')
          ..write('isSystem: $isSystem, ')
          ..write('icon: $icon, ')
          ..write('usageMs: $usageMs, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(packageName, displayName, isSystem,
      $driftBlobEquality.hash(icon), usageMs, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedInstalledApp &&
          other.packageName == this.packageName &&
          other.displayName == this.displayName &&
          other.isSystem == this.isSystem &&
          $driftBlobEquality.equals(other.icon, this.icon) &&
          other.usageMs == this.usageMs &&
          other.cachedAt == this.cachedAt);
}

class InstalledAppsCacheCompanion extends UpdateCompanion<CachedInstalledApp> {
  final Value<String> packageName;
  final Value<String> displayName;
  final Value<bool> isSystem;
  final Value<Uint8List?> icon;
  final Value<int> usageMs;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const InstalledAppsCacheCompanion({
    this.packageName = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.icon = const Value.absent(),
    this.usageMs = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstalledAppsCacheCompanion.insert({
    required String packageName,
    required String displayName,
    this.isSystem = const Value.absent(),
    this.icon = const Value.absent(),
    this.usageMs = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : packageName = Value(packageName),
        displayName = Value(displayName);
  static Insertable<CachedInstalledApp> custom({
    Expression<String>? packageName,
    Expression<String>? displayName,
    Expression<bool>? isSystem,
    Expression<Uint8List>? icon,
    Expression<int>? usageMs,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (packageName != null) 'package_name': packageName,
      if (displayName != null) 'display_name': displayName,
      if (isSystem != null) 'is_system': isSystem,
      if (icon != null) 'icon': icon,
      if (usageMs != null) 'usage_ms': usageMs,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstalledAppsCacheCompanion copyWith(
      {Value<String>? packageName,
      Value<String>? displayName,
      Value<bool>? isSystem,
      Value<Uint8List?>? icon,
      Value<int>? usageMs,
      Value<int>? cachedAt,
      Value<int>? rowid}) {
    return InstalledAppsCacheCompanion(
      packageName: packageName ?? this.packageName,
      displayName: displayName ?? this.displayName,
      isSystem: isSystem ?? this.isSystem,
      icon: icon ?? this.icon,
      usageMs: usageMs ?? this.usageMs,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    if (icon.present) {
      map['icon'] = Variable<Uint8List>(icon.value);
    }
    if (usageMs.present) {
      map['usage_ms'] = Variable<int>(usageMs.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstalledAppsCacheCompanion(')
          ..write('packageName: $packageName, ')
          ..write('displayName: $displayName, ')
          ..write('isSystem: $isSystem, ')
          ..write('icon: $icon, ')
          ..write('usageMs: $usageMs, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BlockedAppsTable blockedApps = $BlockedAppsTable(this);
  late final $BlockRulesTable blockRules = $BlockRulesTable(this);
  late final $DailyStatsTable dailyStats = $DailyStatsTable(this);
  late final $InstalledAppsCacheTable installedAppsCache =
      $InstalledAppsCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [blockedApps, blockRules, dailyStats, installedAppsCache];
}

typedef $$BlockedAppsTableCreateCompanionBuilder = BlockedAppsCompanion
    Function({
  required String packageName,
  required String displayName,
  Value<bool> isBlocked,
  Value<int> addedAt,
  Value<int> rowid,
});
typedef $$BlockedAppsTableUpdateCompanionBuilder = BlockedAppsCompanion
    Function({
  Value<String> packageName,
  Value<String> displayName,
  Value<bool> isBlocked,
  Value<int> addedAt,
  Value<int> rowid,
});

class $$BlockedAppsTableFilterComposer
    extends Composer<_$AppDatabase, $BlockedAppsTable> {
  $$BlockedAppsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBlocked => $composableBuilder(
      column: $table.isBlocked, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$BlockedAppsTableOrderingComposer
    extends Composer<_$AppDatabase, $BlockedAppsTable> {
  $$BlockedAppsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBlocked => $composableBuilder(
      column: $table.isBlocked, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$BlockedAppsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BlockedAppsTable> {
  $$BlockedAppsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<bool> get isBlocked =>
      $composableBuilder(column: $table.isBlocked, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$BlockedAppsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BlockedAppsTable,
    BlockedApp,
    $$BlockedAppsTableFilterComposer,
    $$BlockedAppsTableOrderingComposer,
    $$BlockedAppsTableAnnotationComposer,
    $$BlockedAppsTableCreateCompanionBuilder,
    $$BlockedAppsTableUpdateCompanionBuilder,
    (BlockedApp, BaseReferences<_$AppDatabase, $BlockedAppsTable, BlockedApp>),
    BlockedApp,
    PrefetchHooks Function()> {
  $$BlockedAppsTableTableManager(_$AppDatabase db, $BlockedAppsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockedAppsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockedAppsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockedAppsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> packageName = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<bool> isBlocked = const Value.absent(),
            Value<int> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BlockedAppsCompanion(
            packageName: packageName,
            displayName: displayName,
            isBlocked: isBlocked,
            addedAt: addedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String packageName,
            required String displayName,
            Value<bool> isBlocked = const Value.absent(),
            Value<int> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BlockedAppsCompanion.insert(
            packageName: packageName,
            displayName: displayName,
            isBlocked: isBlocked,
            addedAt: addedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BlockedAppsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BlockedAppsTable,
    BlockedApp,
    $$BlockedAppsTableFilterComposer,
    $$BlockedAppsTableOrderingComposer,
    $$BlockedAppsTableAnnotationComposer,
    $$BlockedAppsTableCreateCompanionBuilder,
    $$BlockedAppsTableUpdateCompanionBuilder,
    (BlockedApp, BaseReferences<_$AppDatabase, $BlockedAppsTable, BlockedApp>),
    BlockedApp,
    PrefetchHooks Function()>;
typedef $$BlockRulesTableCreateCompanionBuilder = BlockRulesCompanion Function({
  Value<int> id,
  Value<int> cardsRequired,
  Value<int> dailyCardsGoal,
  Value<int> unlockDurationMinutes,
  Value<bool> bypassEnabled,
  Value<int> bypassDailyCap,
  Value<int> bypassSeconds,
  Value<bool> isEnabled,
  Value<int> updatedAt,
});
typedef $$BlockRulesTableUpdateCompanionBuilder = BlockRulesCompanion Function({
  Value<int> id,
  Value<int> cardsRequired,
  Value<int> dailyCardsGoal,
  Value<int> unlockDurationMinutes,
  Value<bool> bypassEnabled,
  Value<int> bypassDailyCap,
  Value<int> bypassSeconds,
  Value<bool> isEnabled,
  Value<int> updatedAt,
});

class $$BlockRulesTableFilterComposer
    extends Composer<_$AppDatabase, $BlockRulesTable> {
  $$BlockRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cardsRequired => $composableBuilder(
      column: $table.cardsRequired, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyCardsGoal => $composableBuilder(
      column: $table.dailyCardsGoal,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get bypassEnabled => $composableBuilder(
      column: $table.bypassEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bypassDailyCap => $composableBuilder(
      column: $table.bypassDailyCap,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bypassSeconds => $composableBuilder(
      column: $table.bypassSeconds, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$BlockRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $BlockRulesTable> {
  $$BlockRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cardsRequired => $composableBuilder(
      column: $table.cardsRequired,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyCardsGoal => $composableBuilder(
      column: $table.dailyCardsGoal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get bypassEnabled => $composableBuilder(
      column: $table.bypassEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bypassDailyCap => $composableBuilder(
      column: $table.bypassDailyCap,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bypassSeconds => $composableBuilder(
      column: $table.bypassSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$BlockRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BlockRulesTable> {
  $$BlockRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cardsRequired => $composableBuilder(
      column: $table.cardsRequired, builder: (column) => column);

  GeneratedColumn<int> get dailyCardsGoal => $composableBuilder(
      column: $table.dailyCardsGoal, builder: (column) => column);

  GeneratedColumn<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes, builder: (column) => column);

  GeneratedColumn<bool> get bypassEnabled => $composableBuilder(
      column: $table.bypassEnabled, builder: (column) => column);

  GeneratedColumn<int> get bypassDailyCap => $composableBuilder(
      column: $table.bypassDailyCap, builder: (column) => column);

  GeneratedColumn<int> get bypassSeconds => $composableBuilder(
      column: $table.bypassSeconds, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BlockRulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BlockRulesTable,
    BlockRule,
    $$BlockRulesTableFilterComposer,
    $$BlockRulesTableOrderingComposer,
    $$BlockRulesTableAnnotationComposer,
    $$BlockRulesTableCreateCompanionBuilder,
    $$BlockRulesTableUpdateCompanionBuilder,
    (BlockRule, BaseReferences<_$AppDatabase, $BlockRulesTable, BlockRule>),
    BlockRule,
    PrefetchHooks Function()> {
  $$BlockRulesTableTableManager(_$AppDatabase db, $BlockRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> cardsRequired = const Value.absent(),
            Value<int> dailyCardsGoal = const Value.absent(),
            Value<int> unlockDurationMinutes = const Value.absent(),
            Value<bool> bypassEnabled = const Value.absent(),
            Value<int> bypassDailyCap = const Value.absent(),
            Value<int> bypassSeconds = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              BlockRulesCompanion(
            id: id,
            cardsRequired: cardsRequired,
            dailyCardsGoal: dailyCardsGoal,
            unlockDurationMinutes: unlockDurationMinutes,
            bypassEnabled: bypassEnabled,
            bypassDailyCap: bypassDailyCap,
            bypassSeconds: bypassSeconds,
            isEnabled: isEnabled,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> cardsRequired = const Value.absent(),
            Value<int> dailyCardsGoal = const Value.absent(),
            Value<int> unlockDurationMinutes = const Value.absent(),
            Value<bool> bypassEnabled = const Value.absent(),
            Value<int> bypassDailyCap = const Value.absent(),
            Value<int> bypassSeconds = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              BlockRulesCompanion.insert(
            id: id,
            cardsRequired: cardsRequired,
            dailyCardsGoal: dailyCardsGoal,
            unlockDurationMinutes: unlockDurationMinutes,
            bypassEnabled: bypassEnabled,
            bypassDailyCap: bypassDailyCap,
            bypassSeconds: bypassSeconds,
            isEnabled: isEnabled,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BlockRulesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BlockRulesTable,
    BlockRule,
    $$BlockRulesTableFilterComposer,
    $$BlockRulesTableOrderingComposer,
    $$BlockRulesTableAnnotationComposer,
    $$BlockRulesTableCreateCompanionBuilder,
    $$BlockRulesTableUpdateCompanionBuilder,
    (BlockRule, BaseReferences<_$AppDatabase, $BlockRulesTable, BlockRule>),
    BlockRule,
    PrefetchHooks Function()>;
typedef $$DailyStatsTableCreateCompanionBuilder = DailyStatsCompanion Function({
  required String date,
  Value<int> cardsReviewed,
  Value<int> unlocksEarned,
  Value<int> blockedAttempts,
  Value<int> bypassesUsed,
  Value<int> rowid,
});
typedef $$DailyStatsTableUpdateCompanionBuilder = DailyStatsCompanion Function({
  Value<String> date,
  Value<int> cardsReviewed,
  Value<int> unlocksEarned,
  Value<int> blockedAttempts,
  Value<int> bypassesUsed,
  Value<int> rowid,
});

class $$DailyStatsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cardsReviewed => $composableBuilder(
      column: $table.cardsReviewed, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unlocksEarned => $composableBuilder(
      column: $table.unlocksEarned, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get blockedAttempts => $composableBuilder(
      column: $table.blockedAttempts,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bypassesUsed => $composableBuilder(
      column: $table.bypassesUsed, builder: (column) => ColumnFilters(column));
}

class $$DailyStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cardsReviewed => $composableBuilder(
      column: $table.cardsReviewed,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unlocksEarned => $composableBuilder(
      column: $table.unlocksEarned,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get blockedAttempts => $composableBuilder(
      column: $table.blockedAttempts,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bypassesUsed => $composableBuilder(
      column: $table.bypassesUsed,
      builder: (column) => ColumnOrderings(column));
}

class $$DailyStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyStatsTable> {
  $$DailyStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get cardsReviewed => $composableBuilder(
      column: $table.cardsReviewed, builder: (column) => column);

  GeneratedColumn<int> get unlocksEarned => $composableBuilder(
      column: $table.unlocksEarned, builder: (column) => column);

  GeneratedColumn<int> get blockedAttempts => $composableBuilder(
      column: $table.blockedAttempts, builder: (column) => column);

  GeneratedColumn<int> get bypassesUsed => $composableBuilder(
      column: $table.bypassesUsed, builder: (column) => column);
}

class $$DailyStatsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DailyStatsTable,
    DailyStat,
    $$DailyStatsTableFilterComposer,
    $$DailyStatsTableOrderingComposer,
    $$DailyStatsTableAnnotationComposer,
    $$DailyStatsTableCreateCompanionBuilder,
    $$DailyStatsTableUpdateCompanionBuilder,
    (DailyStat, BaseReferences<_$AppDatabase, $DailyStatsTable, DailyStat>),
    DailyStat,
    PrefetchHooks Function()> {
  $$DailyStatsTableTableManager(_$AppDatabase db, $DailyStatsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> date = const Value.absent(),
            Value<int> cardsReviewed = const Value.absent(),
            Value<int> unlocksEarned = const Value.absent(),
            Value<int> blockedAttempts = const Value.absent(),
            Value<int> bypassesUsed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyStatsCompanion(
            date: date,
            cardsReviewed: cardsReviewed,
            unlocksEarned: unlocksEarned,
            blockedAttempts: blockedAttempts,
            bypassesUsed: bypassesUsed,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String date,
            Value<int> cardsReviewed = const Value.absent(),
            Value<int> unlocksEarned = const Value.absent(),
            Value<int> blockedAttempts = const Value.absent(),
            Value<int> bypassesUsed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyStatsCompanion.insert(
            date: date,
            cardsReviewed: cardsReviewed,
            unlocksEarned: unlocksEarned,
            blockedAttempts: blockedAttempts,
            bypassesUsed: bypassesUsed,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DailyStatsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DailyStatsTable,
    DailyStat,
    $$DailyStatsTableFilterComposer,
    $$DailyStatsTableOrderingComposer,
    $$DailyStatsTableAnnotationComposer,
    $$DailyStatsTableCreateCompanionBuilder,
    $$DailyStatsTableUpdateCompanionBuilder,
    (DailyStat, BaseReferences<_$AppDatabase, $DailyStatsTable, DailyStat>),
    DailyStat,
    PrefetchHooks Function()>;
typedef $$InstalledAppsCacheTableCreateCompanionBuilder
    = InstalledAppsCacheCompanion Function({
  required String packageName,
  required String displayName,
  Value<bool> isSystem,
  Value<Uint8List?> icon,
  Value<int> usageMs,
  Value<int> cachedAt,
  Value<int> rowid,
});
typedef $$InstalledAppsCacheTableUpdateCompanionBuilder
    = InstalledAppsCacheCompanion Function({
  Value<String> packageName,
  Value<String> displayName,
  Value<bool> isSystem,
  Value<Uint8List?> icon,
  Value<int> usageMs,
  Value<int> cachedAt,
  Value<int> rowid,
});

class $$InstalledAppsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $InstalledAppsCacheTable> {
  $$InstalledAppsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get usageMs => $composableBuilder(
      column: $table.usageMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$InstalledAppsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $InstalledAppsCacheTable> {
  $$InstalledAppsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get usageMs => $composableBuilder(
      column: $table.usageMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$InstalledAppsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstalledAppsCacheTable> {
  $$InstalledAppsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<bool> get isSystem =>
      $composableBuilder(column: $table.isSystem, builder: (column) => column);

  GeneratedColumn<Uint8List> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get usageMs =>
      $composableBuilder(column: $table.usageMs, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$InstalledAppsCacheTableTableManager extends RootTableManager<
    _$AppDatabase,
    $InstalledAppsCacheTable,
    CachedInstalledApp,
    $$InstalledAppsCacheTableFilterComposer,
    $$InstalledAppsCacheTableOrderingComposer,
    $$InstalledAppsCacheTableAnnotationComposer,
    $$InstalledAppsCacheTableCreateCompanionBuilder,
    $$InstalledAppsCacheTableUpdateCompanionBuilder,
    (
      CachedInstalledApp,
      BaseReferences<_$AppDatabase, $InstalledAppsCacheTable,
          CachedInstalledApp>
    ),
    CachedInstalledApp,
    PrefetchHooks Function()> {
  $$InstalledAppsCacheTableTableManager(
      _$AppDatabase db, $InstalledAppsCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstalledAppsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstalledAppsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstalledAppsCacheTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> packageName = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<Uint8List?> icon = const Value.absent(),
            Value<int> usageMs = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InstalledAppsCacheCompanion(
            packageName: packageName,
            displayName: displayName,
            isSystem: isSystem,
            icon: icon,
            usageMs: usageMs,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String packageName,
            required String displayName,
            Value<bool> isSystem = const Value.absent(),
            Value<Uint8List?> icon = const Value.absent(),
            Value<int> usageMs = const Value.absent(),
            Value<int> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InstalledAppsCacheCompanion.insert(
            packageName: packageName,
            displayName: displayName,
            isSystem: isSystem,
            icon: icon,
            usageMs: usageMs,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$InstalledAppsCacheTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $InstalledAppsCacheTable,
    CachedInstalledApp,
    $$InstalledAppsCacheTableFilterComposer,
    $$InstalledAppsCacheTableOrderingComposer,
    $$InstalledAppsCacheTableAnnotationComposer,
    $$InstalledAppsCacheTableCreateCompanionBuilder,
    $$InstalledAppsCacheTableUpdateCompanionBuilder,
    (
      CachedInstalledApp,
      BaseReferences<_$AppDatabase, $InstalledAppsCacheTable,
          CachedInstalledApp>
    ),
    CachedInstalledApp,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BlockedAppsTableTableManager get blockedApps =>
      $$BlockedAppsTableTableManager(_db, _db.blockedApps);
  $$BlockRulesTableTableManager get blockRules =>
      $$BlockRulesTableTableManager(_db, _db.blockRules);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db, _db.dailyStats);
  $$InstalledAppsCacheTableTableManager get installedAppsCache =>
      $$InstalledAppsCacheTableTableManager(_db, _db.installedAppsCache);
}
