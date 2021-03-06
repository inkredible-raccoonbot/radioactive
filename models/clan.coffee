_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
GroupClan = require './group_clan'
Group = require './group'
GroupUser = require './group_user'
Conversation = require './conversation'
ClashRoyaleClan = require './clash_royale_clan'
config = require '../config'

STALE_INDEX = 'stale'
CLAN_ID_GAME_ID_INDEX = 'clanIdGameId'

ONE_DAY_S = 3600 * 24
CODE_LENGTH = 6

class ClanModel
  constructor: ->
    @GameClans =
      "#{config.CLASH_ROYALE_ID}": ClashRoyaleClan

  # TODO: remove after ~June 2017?
  # migrate: ({clanId, gameId, groupClanExists}) =>
  #   console.log 'migrate'
  #   prefix = CacheService.PREFIXES.CLAN_MIGRATE
  #   key = "#{prefix}:#{clanId}"
  #   CacheService.runOnce key, =>
  #     r.db('radioactive').table('clans')
  #     .get "#{gameId}:#{clanId}"
  #     .run()
  #     .then (oldClan) =>
  #       if oldClan?.id
  #         groupClan = {
  #           id: oldClan.id
  #           creatorId: oldClan.creatorId
  #           code: oldClan.code
  #           groupId: oldClan.groupId
  #           gameId: oldClan.gameId
  #           clanId: oldClan.clanId
  #           password: oldClan.password
  #           playerIds: _.map oldClan.players, 'playerId'
  #         }
  #
  #         console.log 'create', groupClanExists
  #         Promise.all [
  #           unless groupClanExists
  #             GroupClan.create groupClan
  #           @GameClans[gameId].create _.defaults {id: oldClan.clanId}, oldClan
  #         ]

  getByClanIdAndGameId: (clanId, gameId, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      getGroupClan = ->
        GroupClan.getByClanIdAndGameId clanId, gameId
      Promise.all [
        if preferCache
          CacheService.preferCache cacheKey, getGroupClan, {ignoreNull: true}
        else
          getGroupClan()

        @GameClans[gameId].getById clanId
      ]
      .then ([groupClan, gameClan]) ->
        if groupClan and gameClan
          _.merge groupClan, gameClan

    if preferCache
      prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: ONE_DAY_S, ignoreNull: true
      }
    else
      get()

  upsertByClanIdAndGameId: (clanId, gameId, diff) =>
    prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_ID
    cacheKey = "#{prefix}:#{clanId}:#{gameId}"
    CacheService.preferCache cacheKey, ->
      GroupClan.create {clanId, gameId}
    , {ignoreNull: true}
    .then =>
      @GameClans[gameId].upsertById clanId, diff

    # .tap ->
    #   key = CacheService.PREFIXES.CLAN_PLAYERS + ':' + clanId
    #   CacheService.deleteByKey key

  createGroup: ({userId, creatorId, name, clanId, password}) ->
    Group.create {
      name: name
      creatorId: creatorId
      mode: 'private'
      gameIds: [config.CLASH_ROYALE_ID]
      clanIds: [clanId]
    }
    .tap (group) ->
      Promise.all [
        GroupUser.create {groupId: group.id, userId: userId}
        Conversation.create {
          groupId: group.id
          name: 'general'
          type: 'channel'
        }
      ]
    .tap (group) ->
      GroupClan.updateByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        password: password, groupId: group.id
      }

  sanitizePublic: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameId'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'players'
      'group'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

  sanitize: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameId'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'password'
      'players'
      'group'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

module.exports = new ClanModel()
