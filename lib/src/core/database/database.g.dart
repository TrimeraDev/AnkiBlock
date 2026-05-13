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
      defaultValue: const Constant(3));
  static const VerificationMeta _unlockDurationMinutesMeta =
      const VerificationMeta('unlockDurationMinutes');
  @override
  late final GeneratedColumn<int> unlockDurationMinutes = GeneratedColumn<int>(
      'unlock_duration_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(10));
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
  static const VerificationMeta _dailyNewCardsLimitMeta =
      const VerificationMeta('dailyNewCardsLimit');
  @override
  late final GeneratedColumn<int> dailyNewCardsLimit = GeneratedColumn<int>(
      'daily_new_cards_limit', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(20));
  static const VerificationMeta _dailyReviewsLimitMeta =
      const VerificationMeta('dailyReviewsLimit');
  @override
  late final GeneratedColumn<int> dailyReviewsLimit = GeneratedColumn<int>(
      'daily_reviews_limit', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(200));
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
        unlockDurationMinutes,
        isEnabled,
        dailyNewCardsLimit,
        dailyReviewsLimit,
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
    if (data.containsKey('unlock_duration_minutes')) {
      context.handle(
          _unlockDurationMinutesMeta,
          unlockDurationMinutes.isAcceptableOrUnknown(
              data['unlock_duration_minutes']!, _unlockDurationMinutesMeta));
    }
    if (data.containsKey('is_enabled')) {
      context.handle(_isEnabledMeta,
          isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta));
    }
    if (data.containsKey('daily_new_cards_limit')) {
      context.handle(
          _dailyNewCardsLimitMeta,
          dailyNewCardsLimit.isAcceptableOrUnknown(
              data['daily_new_cards_limit']!, _dailyNewCardsLimitMeta));
    }
    if (data.containsKey('daily_reviews_limit')) {
      context.handle(
          _dailyReviewsLimitMeta,
          dailyReviewsLimit.isAcceptableOrUnknown(
              data['daily_reviews_limit']!, _dailyReviewsLimitMeta));
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
      unlockDurationMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}unlock_duration_minutes'])!,
      isEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_enabled'])!,
      dailyNewCardsLimit: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}daily_new_cards_limit'])!,
      dailyReviewsLimit: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}daily_reviews_limit'])!,
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
  final int unlockDurationMinutes;
  final bool isEnabled;
  final int dailyNewCardsLimit;
  final int dailyReviewsLimit;
  final int updatedAt;
  const BlockRule(
      {required this.id,
      required this.cardsRequired,
      required this.unlockDurationMinutes,
      required this.isEnabled,
      required this.dailyNewCardsLimit,
      required this.dailyReviewsLimit,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cards_required'] = Variable<int>(cardsRequired);
    map['unlock_duration_minutes'] = Variable<int>(unlockDurationMinutes);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['daily_new_cards_limit'] = Variable<int>(dailyNewCardsLimit);
    map['daily_reviews_limit'] = Variable<int>(dailyReviewsLimit);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BlockRulesCompanion toCompanion(bool nullToAbsent) {
    return BlockRulesCompanion(
      id: Value(id),
      cardsRequired: Value(cardsRequired),
      unlockDurationMinutes: Value(unlockDurationMinutes),
      isEnabled: Value(isEnabled),
      dailyNewCardsLimit: Value(dailyNewCardsLimit),
      dailyReviewsLimit: Value(dailyReviewsLimit),
      updatedAt: Value(updatedAt),
    );
  }

  factory BlockRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockRule(
      id: serializer.fromJson<int>(json['id']),
      cardsRequired: serializer.fromJson<int>(json['cardsRequired']),
      unlockDurationMinutes:
          serializer.fromJson<int>(json['unlockDurationMinutes']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      dailyNewCardsLimit: serializer.fromJson<int>(json['dailyNewCardsLimit']),
      dailyReviewsLimit: serializer.fromJson<int>(json['dailyReviewsLimit']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cardsRequired': serializer.toJson<int>(cardsRequired),
      'unlockDurationMinutes': serializer.toJson<int>(unlockDurationMinutes),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'dailyNewCardsLimit': serializer.toJson<int>(dailyNewCardsLimit),
      'dailyReviewsLimit': serializer.toJson<int>(dailyReviewsLimit),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BlockRule copyWith(
          {int? id,
          int? cardsRequired,
          int? unlockDurationMinutes,
          bool? isEnabled,
          int? dailyNewCardsLimit,
          int? dailyReviewsLimit,
          int? updatedAt}) =>
      BlockRule(
        id: id ?? this.id,
        cardsRequired: cardsRequired ?? this.cardsRequired,
        unlockDurationMinutes:
            unlockDurationMinutes ?? this.unlockDurationMinutes,
        isEnabled: isEnabled ?? this.isEnabled,
        dailyNewCardsLimit: dailyNewCardsLimit ?? this.dailyNewCardsLimit,
        dailyReviewsLimit: dailyReviewsLimit ?? this.dailyReviewsLimit,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  BlockRule copyWithCompanion(BlockRulesCompanion data) {
    return BlockRule(
      id: data.id.present ? data.id.value : this.id,
      cardsRequired: data.cardsRequired.present
          ? data.cardsRequired.value
          : this.cardsRequired,
      unlockDurationMinutes: data.unlockDurationMinutes.present
          ? data.unlockDurationMinutes.value
          : this.unlockDurationMinutes,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      dailyNewCardsLimit: data.dailyNewCardsLimit.present
          ? data.dailyNewCardsLimit.value
          : this.dailyNewCardsLimit,
      dailyReviewsLimit: data.dailyReviewsLimit.present
          ? data.dailyReviewsLimit.value
          : this.dailyReviewsLimit,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockRule(')
          ..write('id: $id, ')
          ..write('cardsRequired: $cardsRequired, ')
          ..write('unlockDurationMinutes: $unlockDurationMinutes, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('dailyNewCardsLimit: $dailyNewCardsLimit, ')
          ..write('dailyReviewsLimit: $dailyReviewsLimit, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cardsRequired, unlockDurationMinutes,
      isEnabled, dailyNewCardsLimit, dailyReviewsLimit, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockRule &&
          other.id == this.id &&
          other.cardsRequired == this.cardsRequired &&
          other.unlockDurationMinutes == this.unlockDurationMinutes &&
          other.isEnabled == this.isEnabled &&
          other.dailyNewCardsLimit == this.dailyNewCardsLimit &&
          other.dailyReviewsLimit == this.dailyReviewsLimit &&
          other.updatedAt == this.updatedAt);
}

class BlockRulesCompanion extends UpdateCompanion<BlockRule> {
  final Value<int> id;
  final Value<int> cardsRequired;
  final Value<int> unlockDurationMinutes;
  final Value<bool> isEnabled;
  final Value<int> dailyNewCardsLimit;
  final Value<int> dailyReviewsLimit;
  final Value<int> updatedAt;
  const BlockRulesCompanion({
    this.id = const Value.absent(),
    this.cardsRequired = const Value.absent(),
    this.unlockDurationMinutes = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.dailyNewCardsLimit = const Value.absent(),
    this.dailyReviewsLimit = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  BlockRulesCompanion.insert({
    this.id = const Value.absent(),
    this.cardsRequired = const Value.absent(),
    this.unlockDurationMinutes = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.dailyNewCardsLimit = const Value.absent(),
    this.dailyReviewsLimit = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<BlockRule> custom({
    Expression<int>? id,
    Expression<int>? cardsRequired,
    Expression<int>? unlockDurationMinutes,
    Expression<bool>? isEnabled,
    Expression<int>? dailyNewCardsLimit,
    Expression<int>? dailyReviewsLimit,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardsRequired != null) 'cards_required': cardsRequired,
      if (unlockDurationMinutes != null)
        'unlock_duration_minutes': unlockDurationMinutes,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (dailyNewCardsLimit != null)
        'daily_new_cards_limit': dailyNewCardsLimit,
      if (dailyReviewsLimit != null) 'daily_reviews_limit': dailyReviewsLimit,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  BlockRulesCompanion copyWith(
      {Value<int>? id,
      Value<int>? cardsRequired,
      Value<int>? unlockDurationMinutes,
      Value<bool>? isEnabled,
      Value<int>? dailyNewCardsLimit,
      Value<int>? dailyReviewsLimit,
      Value<int>? updatedAt}) {
    return BlockRulesCompanion(
      id: id ?? this.id,
      cardsRequired: cardsRequired ?? this.cardsRequired,
      unlockDurationMinutes:
          unlockDurationMinutes ?? this.unlockDurationMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      dailyNewCardsLimit: dailyNewCardsLimit ?? this.dailyNewCardsLimit,
      dailyReviewsLimit: dailyReviewsLimit ?? this.dailyReviewsLimit,
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
    if (unlockDurationMinutes.present) {
      map['unlock_duration_minutes'] =
          Variable<int>(unlockDurationMinutes.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (dailyNewCardsLimit.present) {
      map['daily_new_cards_limit'] = Variable<int>(dailyNewCardsLimit.value);
    }
    if (dailyReviewsLimit.present) {
      map['daily_reviews_limit'] = Variable<int>(dailyReviewsLimit.value);
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
          ..write('unlockDurationMinutes: $unlockDurationMinutes, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('dailyNewCardsLimit: $dailyNewCardsLimit, ')
          ..write('dailyReviewsLimit: $dailyReviewsLimit, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $UnlockSessionsTable extends UnlockSessions
    with TableInfo<$UnlockSessionsTable, UnlockSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnlockSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
      'started_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: Constant(DateTime.now().millisecondsSinceEpoch));
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
      'expires_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _requiredCardsMeta =
      const VerificationMeta('requiredCards');
  @override
  late final GeneratedColumn<int> requiredCards = GeneratedColumn<int>(
      'required_cards', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _completedCardsMeta =
      const VerificationMeta('completedCards');
  @override
  late final GeneratedColumn<int> completedCards = GeneratedColumn<int>(
      'completed_cards', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumnWithTypeConverter<UnlockStatus, int> status =
      GeneratedColumn<int>('status', aliasedName, false,
              type: DriftSqlType.int,
              requiredDuringInsert: false,
              defaultValue: const Constant(0))
          .withConverter<UnlockStatus>($UnlockSessionsTable.$converterstatus);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        packageName,
        startedAt,
        expiresAt,
        requiredCards,
        completedCards,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'unlock_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<UnlockSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('required_cards')) {
      context.handle(
          _requiredCardsMeta,
          requiredCards.isAcceptableOrUnknown(
              data['required_cards']!, _requiredCardsMeta));
    } else if (isInserting) {
      context.missing(_requiredCardsMeta);
    }
    if (data.containsKey('completed_cards')) {
      context.handle(
          _completedCardsMeta,
          completedCards.isAcceptableOrUnknown(
              data['completed_cards']!, _completedCardsMeta));
    }
    context.handle(_statusMeta, const VerificationResult.success());
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UnlockSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UnlockSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expires_at'])!,
      requiredCards: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}required_cards'])!,
      completedCards: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_cards'])!,
      status: $UnlockSessionsTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!),
    );
  }

  @override
  $UnlockSessionsTable createAlias(String alias) {
    return $UnlockSessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<UnlockStatus, int, int> $converterstatus =
      const EnumIndexConverter<UnlockStatus>(UnlockStatus.values);
}

class UnlockSession extends DataClass implements Insertable<UnlockSession> {
  final int id;
  final String packageName;
  final int startedAt;
  final int expiresAt;
  final int requiredCards;
  final int completedCards;
  final UnlockStatus status;
  const UnlockSession(
      {required this.id,
      required this.packageName,
      required this.startedAt,
      required this.expiresAt,
      required this.requiredCards,
      required this.completedCards,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['package_name'] = Variable<String>(packageName);
    map['started_at'] = Variable<int>(startedAt);
    map['expires_at'] = Variable<int>(expiresAt);
    map['required_cards'] = Variable<int>(requiredCards);
    map['completed_cards'] = Variable<int>(completedCards);
    {
      map['status'] =
          Variable<int>($UnlockSessionsTable.$converterstatus.toSql(status));
    }
    return map;
  }

  UnlockSessionsCompanion toCompanion(bool nullToAbsent) {
    return UnlockSessionsCompanion(
      id: Value(id),
      packageName: Value(packageName),
      startedAt: Value(startedAt),
      expiresAt: Value(expiresAt),
      requiredCards: Value(requiredCards),
      completedCards: Value(completedCards),
      status: Value(status),
    );
  }

  factory UnlockSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UnlockSession(
      id: serializer.fromJson<int>(json['id']),
      packageName: serializer.fromJson<String>(json['packageName']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
      requiredCards: serializer.fromJson<int>(json['requiredCards']),
      completedCards: serializer.fromJson<int>(json['completedCards']),
      status: $UnlockSessionsTable.$converterstatus
          .fromJson(serializer.fromJson<int>(json['status'])),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'packageName': serializer.toJson<String>(packageName),
      'startedAt': serializer.toJson<int>(startedAt),
      'expiresAt': serializer.toJson<int>(expiresAt),
      'requiredCards': serializer.toJson<int>(requiredCards),
      'completedCards': serializer.toJson<int>(completedCards),
      'status': serializer
          .toJson<int>($UnlockSessionsTable.$converterstatus.toJson(status)),
    };
  }

  UnlockSession copyWith(
          {int? id,
          String? packageName,
          int? startedAt,
          int? expiresAt,
          int? requiredCards,
          int? completedCards,
          UnlockStatus? status}) =>
      UnlockSession(
        id: id ?? this.id,
        packageName: packageName ?? this.packageName,
        startedAt: startedAt ?? this.startedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        requiredCards: requiredCards ?? this.requiredCards,
        completedCards: completedCards ?? this.completedCards,
        status: status ?? this.status,
      );
  UnlockSession copyWithCompanion(UnlockSessionsCompanion data) {
    return UnlockSession(
      id: data.id.present ? data.id.value : this.id,
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      requiredCards: data.requiredCards.present
          ? data.requiredCards.value
          : this.requiredCards,
      completedCards: data.completedCards.present
          ? data.completedCards.value
          : this.completedCards,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UnlockSession(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('startedAt: $startedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('requiredCards: $requiredCards, ')
          ..write('completedCards: $completedCards, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, packageName, startedAt, expiresAt,
      requiredCards, completedCards, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnlockSession &&
          other.id == this.id &&
          other.packageName == this.packageName &&
          other.startedAt == this.startedAt &&
          other.expiresAt == this.expiresAt &&
          other.requiredCards == this.requiredCards &&
          other.completedCards == this.completedCards &&
          other.status == this.status);
}

class UnlockSessionsCompanion extends UpdateCompanion<UnlockSession> {
  final Value<int> id;
  final Value<String> packageName;
  final Value<int> startedAt;
  final Value<int> expiresAt;
  final Value<int> requiredCards;
  final Value<int> completedCards;
  final Value<UnlockStatus> status;
  const UnlockSessionsCompanion({
    this.id = const Value.absent(),
    this.packageName = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.requiredCards = const Value.absent(),
    this.completedCards = const Value.absent(),
    this.status = const Value.absent(),
  });
  UnlockSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String packageName,
    this.startedAt = const Value.absent(),
    required int expiresAt,
    required int requiredCards,
    this.completedCards = const Value.absent(),
    this.status = const Value.absent(),
  })  : packageName = Value(packageName),
        expiresAt = Value(expiresAt),
        requiredCards = Value(requiredCards);
  static Insertable<UnlockSession> custom({
    Expression<int>? id,
    Expression<String>? packageName,
    Expression<int>? startedAt,
    Expression<int>? expiresAt,
    Expression<int>? requiredCards,
    Expression<int>? completedCards,
    Expression<int>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (packageName != null) 'package_name': packageName,
      if (startedAt != null) 'started_at': startedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (requiredCards != null) 'required_cards': requiredCards,
      if (completedCards != null) 'completed_cards': completedCards,
      if (status != null) 'status': status,
    });
  }

  UnlockSessionsCompanion copyWith(
      {Value<int>? id,
      Value<String>? packageName,
      Value<int>? startedAt,
      Value<int>? expiresAt,
      Value<int>? requiredCards,
      Value<int>? completedCards,
      Value<UnlockStatus>? status}) {
    return UnlockSessionsCompanion(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      requiredCards: requiredCards ?? this.requiredCards,
      completedCards: completedCards ?? this.completedCards,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (requiredCards.present) {
      map['required_cards'] = Variable<int>(requiredCards.value);
    }
    if (completedCards.present) {
      map['completed_cards'] = Variable<int>(completedCards.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
          $UnlockSessionsTable.$converterstatus.toSql(status.value));
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnlockSessionsCompanion(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('startedAt: $startedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('requiredCards: $requiredCards, ')
          ..write('completedCards: $completedCards, ')
          ..write('status: $status')
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
  @override
  List<GeneratedColumn> get $columns =>
      [date, cardsReviewed, unlocksEarned, blockedAttempts];
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
  const DailyStat(
      {required this.date,
      required this.cardsReviewed,
      required this.unlocksEarned,
      required this.blockedAttempts});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['cards_reviewed'] = Variable<int>(cardsReviewed);
    map['unlocks_earned'] = Variable<int>(unlocksEarned);
    map['blocked_attempts'] = Variable<int>(blockedAttempts);
    return map;
  }

  DailyStatsCompanion toCompanion(bool nullToAbsent) {
    return DailyStatsCompanion(
      date: Value(date),
      cardsReviewed: Value(cardsReviewed),
      unlocksEarned: Value(unlocksEarned),
      blockedAttempts: Value(blockedAttempts),
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
    };
  }

  DailyStat copyWith(
          {String? date,
          int? cardsReviewed,
          int? unlocksEarned,
          int? blockedAttempts}) =>
      DailyStat(
        date: date ?? this.date,
        cardsReviewed: cardsReviewed ?? this.cardsReviewed,
        unlocksEarned: unlocksEarned ?? this.unlocksEarned,
        blockedAttempts: blockedAttempts ?? this.blockedAttempts,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStat(')
          ..write('date: $date, ')
          ..write('cardsReviewed: $cardsReviewed, ')
          ..write('unlocksEarned: $unlocksEarned, ')
          ..write('blockedAttempts: $blockedAttempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(date, cardsReviewed, unlocksEarned, blockedAttempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStat &&
          other.date == this.date &&
          other.cardsReviewed == this.cardsReviewed &&
          other.unlocksEarned == this.unlocksEarned &&
          other.blockedAttempts == this.blockedAttempts);
}

class DailyStatsCompanion extends UpdateCompanion<DailyStat> {
  final Value<String> date;
  final Value<int> cardsReviewed;
  final Value<int> unlocksEarned;
  final Value<int> blockedAttempts;
  final Value<int> rowid;
  const DailyStatsCompanion({
    this.date = const Value.absent(),
    this.cardsReviewed = const Value.absent(),
    this.unlocksEarned = const Value.absent(),
    this.blockedAttempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyStatsCompanion.insert({
    required String date,
    this.cardsReviewed = const Value.absent(),
    this.unlocksEarned = const Value.absent(),
    this.blockedAttempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyStat> custom({
    Expression<String>? date,
    Expression<int>? cardsReviewed,
    Expression<int>? unlocksEarned,
    Expression<int>? blockedAttempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (cardsReviewed != null) 'cards_reviewed': cardsReviewed,
      if (unlocksEarned != null) 'unlocks_earned': unlocksEarned,
      if (blockedAttempts != null) 'blocked_attempts': blockedAttempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyStatsCompanion copyWith(
      {Value<String>? date,
      Value<int>? cardsReviewed,
      Value<int>? unlocksEarned,
      Value<int>? blockedAttempts,
      Value<int>? rowid}) {
    return DailyStatsCompanion(
      date: date ?? this.date,
      cardsReviewed: cardsReviewed ?? this.cardsReviewed,
      unlocksEarned: unlocksEarned ?? this.unlocksEarned,
      blockedAttempts: blockedAttempts ?? this.blockedAttempts,
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
  late final $UnlockSessionsTable unlockSessions = $UnlockSessionsTable(this);
  late final $DailyStatsTable dailyStats = $DailyStatsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [blockedApps, blockRules, unlockSessions, dailyStats];
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
  Value<int> unlockDurationMinutes,
  Value<bool> isEnabled,
  Value<int> dailyNewCardsLimit,
  Value<int> dailyReviewsLimit,
  Value<int> updatedAt,
});
typedef $$BlockRulesTableUpdateCompanionBuilder = BlockRulesCompanion Function({
  Value<int> id,
  Value<int> cardsRequired,
  Value<int> unlockDurationMinutes,
  Value<bool> isEnabled,
  Value<int> dailyNewCardsLimit,
  Value<int> dailyReviewsLimit,
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

  ColumnFilters<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyNewCardsLimit => $composableBuilder(
      column: $table.dailyNewCardsLimit,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyReviewsLimit => $composableBuilder(
      column: $table.dailyReviewsLimit,
      builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyNewCardsLimit => $composableBuilder(
      column: $table.dailyNewCardsLimit,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyReviewsLimit => $composableBuilder(
      column: $table.dailyReviewsLimit,
      builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<int> get unlockDurationMinutes => $composableBuilder(
      column: $table.unlockDurationMinutes, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<int> get dailyNewCardsLimit => $composableBuilder(
      column: $table.dailyNewCardsLimit, builder: (column) => column);

  GeneratedColumn<int> get dailyReviewsLimit => $composableBuilder(
      column: $table.dailyReviewsLimit, builder: (column) => column);

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
            Value<int> unlockDurationMinutes = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<int> dailyNewCardsLimit = const Value.absent(),
            Value<int> dailyReviewsLimit = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              BlockRulesCompanion(
            id: id,
            cardsRequired: cardsRequired,
            unlockDurationMinutes: unlockDurationMinutes,
            isEnabled: isEnabled,
            dailyNewCardsLimit: dailyNewCardsLimit,
            dailyReviewsLimit: dailyReviewsLimit,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> cardsRequired = const Value.absent(),
            Value<int> unlockDurationMinutes = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
            Value<int> dailyNewCardsLimit = const Value.absent(),
            Value<int> dailyReviewsLimit = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              BlockRulesCompanion.insert(
            id: id,
            cardsRequired: cardsRequired,
            unlockDurationMinutes: unlockDurationMinutes,
            isEnabled: isEnabled,
            dailyNewCardsLimit: dailyNewCardsLimit,
            dailyReviewsLimit: dailyReviewsLimit,
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
typedef $$UnlockSessionsTableCreateCompanionBuilder = UnlockSessionsCompanion
    Function({
  Value<int> id,
  required String packageName,
  Value<int> startedAt,
  required int expiresAt,
  required int requiredCards,
  Value<int> completedCards,
  Value<UnlockStatus> status,
});
typedef $$UnlockSessionsTableUpdateCompanionBuilder = UnlockSessionsCompanion
    Function({
  Value<int> id,
  Value<String> packageName,
  Value<int> startedAt,
  Value<int> expiresAt,
  Value<int> requiredCards,
  Value<int> completedCards,
  Value<UnlockStatus> status,
});

class $$UnlockSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $UnlockSessionsTable> {
  $$UnlockSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get requiredCards => $composableBuilder(
      column: $table.requiredCards, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedCards => $composableBuilder(
      column: $table.completedCards,
      builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<UnlockStatus, UnlockStatus, int> get status =>
      $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));
}

class $$UnlockSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $UnlockSessionsTable> {
  $$UnlockSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get requiredCards => $composableBuilder(
      column: $table.requiredCards,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedCards => $composableBuilder(
      column: $table.completedCards,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$UnlockSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UnlockSessionsTable> {
  $$UnlockSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get requiredCards => $composableBuilder(
      column: $table.requiredCards, builder: (column) => column);

  GeneratedColumn<int> get completedCards => $composableBuilder(
      column: $table.completedCards, builder: (column) => column);

  GeneratedColumnWithTypeConverter<UnlockStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$UnlockSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UnlockSessionsTable,
    UnlockSession,
    $$UnlockSessionsTableFilterComposer,
    $$UnlockSessionsTableOrderingComposer,
    $$UnlockSessionsTableAnnotationComposer,
    $$UnlockSessionsTableCreateCompanionBuilder,
    $$UnlockSessionsTableUpdateCompanionBuilder,
    (
      UnlockSession,
      BaseReferences<_$AppDatabase, $UnlockSessionsTable, UnlockSession>
    ),
    UnlockSession,
    PrefetchHooks Function()> {
  $$UnlockSessionsTableTableManager(
      _$AppDatabase db, $UnlockSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnlockSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnlockSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UnlockSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> packageName = const Value.absent(),
            Value<int> startedAt = const Value.absent(),
            Value<int> expiresAt = const Value.absent(),
            Value<int> requiredCards = const Value.absent(),
            Value<int> completedCards = const Value.absent(),
            Value<UnlockStatus> status = const Value.absent(),
          }) =>
              UnlockSessionsCompanion(
            id: id,
            packageName: packageName,
            startedAt: startedAt,
            expiresAt: expiresAt,
            requiredCards: requiredCards,
            completedCards: completedCards,
            status: status,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String packageName,
            Value<int> startedAt = const Value.absent(),
            required int expiresAt,
            required int requiredCards,
            Value<int> completedCards = const Value.absent(),
            Value<UnlockStatus> status = const Value.absent(),
          }) =>
              UnlockSessionsCompanion.insert(
            id: id,
            packageName: packageName,
            startedAt: startedAt,
            expiresAt: expiresAt,
            requiredCards: requiredCards,
            completedCards: completedCards,
            status: status,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UnlockSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UnlockSessionsTable,
    UnlockSession,
    $$UnlockSessionsTableFilterComposer,
    $$UnlockSessionsTableOrderingComposer,
    $$UnlockSessionsTableAnnotationComposer,
    $$UnlockSessionsTableCreateCompanionBuilder,
    $$UnlockSessionsTableUpdateCompanionBuilder,
    (
      UnlockSession,
      BaseReferences<_$AppDatabase, $UnlockSessionsTable, UnlockSession>
    ),
    UnlockSession,
    PrefetchHooks Function()>;
typedef $$DailyStatsTableCreateCompanionBuilder = DailyStatsCompanion Function({
  required String date,
  Value<int> cardsReviewed,
  Value<int> unlocksEarned,
  Value<int> blockedAttempts,
  Value<int> rowid,
});
typedef $$DailyStatsTableUpdateCompanionBuilder = DailyStatsCompanion Function({
  Value<String> date,
  Value<int> cardsReviewed,
  Value<int> unlocksEarned,
  Value<int> blockedAttempts,
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
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyStatsCompanion(
            date: date,
            cardsReviewed: cardsReviewed,
            unlocksEarned: unlocksEarned,
            blockedAttempts: blockedAttempts,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String date,
            Value<int> cardsReviewed = const Value.absent(),
            Value<int> unlocksEarned = const Value.absent(),
            Value<int> blockedAttempts = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyStatsCompanion.insert(
            date: date,
            cardsReviewed: cardsReviewed,
            unlocksEarned: unlocksEarned,
            blockedAttempts: blockedAttempts,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BlockedAppsTableTableManager get blockedApps =>
      $$BlockedAppsTableTableManager(_db, _db.blockedApps);
  $$BlockRulesTableTableManager get blockRules =>
      $$BlockRulesTableTableManager(_db, _db.blockRules);
  $$UnlockSessionsTableTableManager get unlockSessions =>
      $$UnlockSessionsTableTableManager(_db, _db.unlockSessions);
  $$DailyStatsTableTableManager get dailyStats =>
      $$DailyStatsTableTableManager(_db, _db.dailyStats);
}
