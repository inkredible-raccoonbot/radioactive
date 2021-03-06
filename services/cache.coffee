Redlock = require 'redlock'
Promise = require 'bluebird'

RedisService = require './redis'
config = require '../config'

DEFAULT_CACHE_EXPIRE_SECONDS = 3600 * 24 * 30 # 30 days
DEFAULT_LOCK_EXPIRE_SECONDS = 3600 * 24 * 40000 # 100+ years
DEFAULT_REDLOCK_EXPIRE_SECONDS = 30
ONE_HOUR_SECONDS = 3600

PREFIXES =
  CHAT_USER: 'chat:user3'
  THREAD_USER: 'thread:user1'
  THREAD: 'thread:id'
  THREAD_DECK: 'thread:deck9'
  THREAD_COMMENTS: 'thread:comments2'
  THREAD_COMMENT_COUNT: 'thread:comment_count'
  THREADS: 'threads2'
  CONVERSATION_ID: 'conversation:id'
  USER_FOLLOWER_COUNT: 'user:follower_count'
  USER_DATA: 'user_data:id'
  USER_DATA_CONVERSATION_USERS: 'user_data:conversation_users'
  USER_DATA_FOLLOWERS: 'user_data:followers'
  USER_DATA_FOLLOWING: 'user_data:following'
  USER_DATA_FOLLOWING_PLAYERS: 'user_data:following:players'
  USER_DATA_BLOCKED_USERS: 'user_data:blocked_users'
  USER_DATA_CLASH_ROYALE_DECK_IDS: 'user_data:clash_royale_deck_ids6'
  USER_DAILY_DATA_PUSH: 'user_daily_data:push5'
  CLASH_ROYALE_MATCHES_ID: 'clash_royale_matches:id52'
  CLASH_ROYALE_MATCHES_ID_EXISTS: 'clash_royale_matches:id:exists1'
  CLASH_ROYALE_INVALID_TAG: 'clash_royale:invalid_tag'
  CLASH_ROYALE_CARD: 'clash_royale_card2'
  CLASH_ROYALE_CARD_ALL: 'clash_royale_card:all1'
  CLASH_ROYALE_CARD_KEY: 'clash_royale_card_key3'
  CLASH_ROYALE_CARD_RANK: 'clash_royal_card:rank'
  CLASH_ROYALE_DECK_RANK: 'clash_royal_deck:rank'
  CLASH_ROYALE_DECK_CARD_KEYS: 'clash_royal_deck:card_keys12'
  CLASH_ROYALE_PLAYER_DECK_DECK: 'clash_royale_player_deck:deck8'
  CLASH_ROYALE_PLAYER_DECK_DECK_ID_USER_ID:
    'clash_royale_player_deck:deck_id:user_id1'
  CLASH_ROYALE_PLAYER_DECK_DECK_ID_PLAYER_ID:
    'clash_royale_player_deck:deck_id:player_id2'
  CLASH_ROYALE_PLAYER_DECK_PLAYER_ID:
    'clash_royale_player_deck:player_id2'
  CLASH_ROYALE_API_GET_PLAYER_ID: 'clash_royale_api:get_tag'
  GROUP_ID: 'group:id1'
  GROUP_GET_ALL: 'group:getAll'
  GROUP_GET_ALL_CATEGORY: 'group:getAll:category'
  GROUP_STAR: 'group:star'
  USERNAME_SEARCH: 'username:search1'
  RATE_LIMIT_CHAT_MESSAGES_TEXT: 'rate_limit:chat_messages:text'
  RATE_LIMIT_CHAT_MESSAGES_MEDIA: 'rate_limit:chat_messages:media'
  PLAYER_SEARCH: 'player:search8'
  PLAYER_VERIFIED_USER: 'player:verified_user4'
  PLAYER_USER_ID_GAME_ID: 'player:user_id_game_id1'
  PLAYER_USER_IDS: 'player:user_ids2'
  CLAN_CLASH_ROYALE_ID: 'clan:clash_royale_id3'
  PLAYER_CLASH_ROYALE_ID: 'player:clash_royale_id'
  PLAYER_MIGRATE: 'player:migrate07'
  REFRESH_PLAYER_ID_LOCK: 'player:refresh_lock'
  USER_DECKS_MIGRATE: 'user_decks:migrate16'
  USER_RECORDS_MIGRATE: 'user_records:migrate11'
  USER_PLAYER_USER_ID_GAME_ID: 'user_player:user_id_game_id5'
  GROUP_CLAN_CLAN_ID_GAME_ID: 'group_clan:clan_id_game_id8'
  CLAN_CLAN_ID_GAME_ID: 'clan:clan_id_game_id10'
  CLAN_MIGRATE: 'clan:migrate9'
  CLAN_PLAYERS: 'clan:players1'
  BAN_IP: 'ban:ip'
  BAN_USER_ID: 'ban:user_id1'
  HONEY_POT_BAN_IP: 'honey_pot:ban_ip5'

class CacheService
  KEYS:
    ADDON_GET_ALL: 'addon:get_all'
    AUTO_REFRESH_SUCCESS_COUNT: 'auto_refresh:success_count'
    BROADCAST_FAILSAFE: 'broadcast:failsafe'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royal_deck:queued_increments:win1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_deck:queued_increments:loss1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_deck:queued_increments:draw1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royale_player_deck:queued_increments:win1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_player_deck:queued_increments:loss1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_player_deck:queued_increments:draw1'
    CLASH_ROYALE_CARDS: 'clash_royale:cards1'
    PLAYERS_TOP: 'player:top1'
    KUE_WATCH_STUCK: 'kue:watch_stuck'
  LOCK_PREFIXES:
    KUE_PROCESS: 'kue:process'
    BROADCAST: 'broadcast'
  LOCKS: {}
  PREFIXES: PREFIXES

  constructor: ->
    @redlock = new Redlock [RedisService], {
      driftFactor: 0.01
      retryCount: 0
      # retryDelay:  200
    }

  arrayAppend: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.rpush key, value #JSON.stringify value

  arrayGet: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.lrange key, 0, -1

  set: (key, value, {expireSeconds} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.set key, JSON.stringify value
    .then ->
      if expireSeconds
        RedisService.expire key, expireSeconds

  get: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.get key
    .then (value) ->
      try
        JSON.parse value
      catch err
        value

  getCursor: (cursor) =>
    key = "#{PREFIXES.CURSOR}:#{cursor}"
    @get key

  setCursor: (cursor, value) =>
    key = "#{PREFIXES.CURSOR}:#{cursor}"
    @set key, value, {expireSeconds: ONE_HOUR_SECONDS}

  # for locking
  runOnce: (key, fn, {expireSeconds, lockedFn} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_LOCK_EXPIRE_SECONDS
    # TODO: use redlock
    setVal = '1'
    RedisService.set key, setVal, 'NX', 'EX', expireSeconds
    .then (value) ->
      if value isnt null
        fn()
      else
        lockedFn?()


  lock: (key, fn, {expireSeconds, unlockWhenCompleted} = {}) =>
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_REDLOCK_EXPIRE_SECONDS
    @redlock.lock key, expireSeconds * 1000
    .then (lock) ->
      fn(lock)?.tap? ->
        if unlockWhenCompleted
          lock.unlock()
    .catch (err) ->
      # console.log 'redlock err', err
      null

  preferCache: (key, fn, {expireSeconds, ignoreNull, category} = {}) =>
    rawKey = key
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_CACHE_EXPIRE_SECONDS

    if category
      categoryKey = 'category:' + category
      @arrayGet categoryKey
      .then (categoryKeys) =>
        if categoryKeys.indexOf(key) is -1
          @arrayAppend categoryKey, rawKey

    RedisService.get key
    .then (value) ->
      if value?
        try
          return JSON.parse value
        catch err
          console.log 'error parsing', key, value
          return null

      fn().then (value) ->
        if (value isnt null and value isnt undefined) or not ignoreNull
          RedisService.set key, JSON.stringify value
          .then ->
            RedisService.expire key, expireSeconds

        return value

  deleteByCategory: (category) =>
    categoryKey = 'category:' + category
    @arrayGet categoryKey
    .then (categoryKeys) =>
      Promise.map categoryKeys, @deleteByKey
    .then =>
      @deleteByKey categoryKey

  deleteByKey: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.del key

module.exports = new CacheService()
