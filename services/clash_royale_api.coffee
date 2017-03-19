Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

UserGameData = require '../models/user_game_data'
Group = require '../models/group'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
UserGameData = require '../models/user_game_data'
EmailService = require './email'
CacheService = require './cache'
GameRecord = require '../models/game_record'
Match = require '../models/clash_royale_match'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
STALE_TIME_MS = 3600 * 12 # 12hr
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

class ClashAPIService
  getPlayerDataByTag: (tag) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}"
    request "#{config.CR_API_URL}/players/#{tag}", {json: true}
    .then (responses) ->
      responses?[0]

  getPlayerMatchesByTag: (tag) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}/games"
    request "#{config.CR_API_URL}/players/#{tag}/games", {json: true}
    .then (responses) ->
      responses?[0]

  getClanDataByTag: (tag) ->
    request "#{config.CR_API_URL}/clans/#{tag}", {json: true}

  getMatchPlayerData: ({player, deck}) ->
    {
      deckId: deck.id
      crowns: player.crowns
      playerName: player.playerName
      playerTag: player.playerTag
      clanName: player.clanName
      clanTag: player.clanTag
      trophies: player.trophies
    }

  # matches from API, tag, userId for adding new user to matches
  # userGameData so we can only pull in matches since last update
  processMatches: ({matches, tag, userGameData}) =>
    # only grab matches since the last update time
    matches = _.filter matches, ({time}) ->
      if userGameData.data.lastMatchTime
        lastMatchTime = new Date userGameData.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      new Date(time).getTime() > (new Date(lastMatchTime).getTime() + 15)
    matches = _.orderBy matches, ['time'], ['asc']

    console.log matches.length

    # store diffs in here so we can update once after all the matches are
    # processed, instead of once per match
    playerDiffs = {}

    Promise.map matches, (match) ->
      matchId = "cr-#{match.id}"
      Match.getById matchId, {preferCache: true}
      .then (existingMatch) ->
        if existingMatch then null else match
    .then _.filter
    .each (match) =>
      matchId = "cr-#{match.id}"

      player1Tag = match.player1.playerTag
      player2Tag = match.player2.playerTag

      # prefer from cached diff obj
      # (that has been modified for stats, winStreak, etc...)
      player1UserGameData = playerDiffs[player1Tag]
      player1UserGameData ?= UserGameData.getByPlayerIdAndGameId(
        player1Tag, GAME_ID
      )
      # prefer from cached diff obj
      player2UserGameData = playerDiffs[player2Tag]
      player2UserGameData ?= UserGameData.getByPlayerIdAndGameId(
        player2Tag, GAME_ID
      )

      type = match.type

      Promise.all [
        # grab decks
        ClashRoyaleDeck.getByCardKeys match.player1.cardKeys, {
          preferCache: true
        }
        ClashRoyaleDeck.getByCardKeys match.player2.cardKeys, {
          preferCache: true
        }

        Promise.resolve player1UserGameData
        Promise.resolve player2UserGameData
      ]
      .then ([deck1, deck2, player1UserGameData, player2UserGameData]) =>
        player1UserIds = player1UserGameData.userIds
        player2UserIds = player2UserGameData.userIds

        player1Stats = player1UserGameData?.data?.stats?[type]
        player2Stats = player2UserGameData?.data?.stats?[type]

        player1Diff = {
          currentWinStreak: player1Stats?.currentWinStreak or 0
          currentLossStreak: player1Stats?.currentLossStreak or 0
          maxWinStreak: player1Stats?.maxWinStreak or 0
          maxLossStreak: player1Stats?.maxLossStreak or 0
          crownsEarned: player1Stats?.crownsEarned or 0
          crownsLost: player1Stats?.crownsLost or 0
          wins: player1Stats?.wins or 0
          losses: player1Stats?.losses or 0
          draws: player1Stats?.draws or 0
        }
        player2Diff = {
          currentWinStreak: player2Stats?.currentWinStreak or 0
          currentLossStreak: player2Stats?.currentLossStreak or 0
          maxWinStreak: player2Stats?.maxWinStreak or 0
          maxLossStreak: player2Stats?.maxLossStreak or 0
          crownsEarned: player2Stats?.crownsEarned or 0
          crownsLost: player2Stats?.crownsLost or 0
          wins: player2Stats?.wins or 0
          losses: player2Stats?.losses or 0
          draws: player2Stats?.draws or 0
        }

        Promise.all(_.filter(_.map(player1UserIds, (userId) ->
          ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
            deck1.id
            userId
            {
              isFavorited: true
              playerId: player1UserGameData.playerId
            }
          )
        ).concat _.map(player2UserIds, (userId) ->
          ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
            deck2.id
            userId
            {
              isFavorited: true
              playerId: player2UserGameData.playerId
            }
          )
        )))
        .then =>
          player1Won = match.player1.crowns > match.player2.crowns
          player2Won = match.player2.crowns > match.player1.crowns

          player1Diff.crownsEarned += match.player1.crowns
          player1Diff.crownsLost += match.player2.crowns

          player2Diff.crownsEarned += match.player2.crowns
          player2Diff.crownsLost += match.player1.crowns

          if player1Won
            winningDeckId = deck1.id
            losingDeckId = deck2.id
            winningDeckCardIds = deck1.cardIds
            losingDeckCardIds = deck2.cardIds
            deck1State = 'win'
            deck2State = 'loss'
            player1Diff.wins += 1
            player1Diff.currentWinStreak += 1
            player1Diff.currentLossStreak = 0
            player2Diff.losses += 1
            player2Diff.currentWinStreak = 0
            player2Diff.currentLossStreak += 1
          else if player2Won
            winningDeckId = deck2.id
            losingDeckId = deck1.id
            winningDeckCardIds = deck2.cardIds
            losingDeckCardIds = deck1.cardIds
            deck1State = 'loss'
            deck2State = 'win'
            player2Diff.wins += 1
            player2Diff.currentWinStreak += 1
            player2Diff.currentLossStreak = 0
            player1Diff.losses += 1
            player1Diff.currentWinStreak = 0
            player1Diff.currentLossStreak += 1
          else
            winningDeckId = null
            losingDeckId = null
            deck1State = 'draw'
            deck2State = 'draw'
            player1Diff.draws += 1
            player1Diff.currentWinStreak = 0
            player1Diff.currentLossStreak = 0
            player2Diff.draws += 1
            player2Diff.currentWinStreak = 0
            player2Diff.currentLossStreak = 0

          # set the global playerDiffs to the local match data

          # player 1
          playerDiffs[player1Tag] ?= player1UserGameData
          playerDiffs[player1Tag].data ?= {stats: {}}
          oldMaxWinStreak = player1Stats?.maxWinStreak or 0
          if player1Diff.currentWinStreak > oldMaxWinStreak
            player1Diff.maxWinStreak = player1Diff.currentWinStreak
          oldMaxLossStreak = player1Stats?.maxLossStreak or 0
          if player1Diff.currentLossStreak > oldMaxLossStreak
            player1Diff.maxLossStreak = player1Diff.currentLossStreak
          playerDiffs[player1Tag].data.stats[type] = player1Diff

          # player 2
          playerDiffs[player2Tag] ?= player2UserGameData
          oldMaxWinStreak = player2Stats?.maxWinStreak or 0
          if player2Diff.currentWinStreak > oldMaxWinStreak
            player2Diff.maxWinStreak = player2Diff.currentWinStreak
          oldMaxLossStreak = player2Stats?.maxLossStreak or 0
          if player2Diff.currentLossStreak > oldMaxLossStreak
            player2Diff.maxLossStreak = player2Diff.currentLossStreak
          playerDiffs[player2Tag].data ?= {stats: {}}
          playerDiffs[player2Tag].data.stats[type] = player2Diff

          # for records (graph)
          scaledTime = GameRecord.getScaledTimeByTimeScale(
            'minute', moment(match.time)
          )

          Promise.all(_.filter(_.map(player1UserIds, (userId) ->
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to user decks
            ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
              deck1.id, userId, deck1State
            )
          ).concat _.map(player2UserIds, (userId) ->
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to user decks
            ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
              deck2.id, userId, deck2State
            )
          ).concat [
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to deck
            ClashRoyaleDeck.incrementById(deck1.id, deck1State)
            ClashRoyaleDeck.incrementById(deck2.id, deck2State)
          ]
          .concat if type is 'ladder'
            # graphs p1
            _.map(player1UserIds, (userId) ->
              GameRecord.create {
                userId: userId
                playerId: player1Tag
                gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                scaledTime
                value: match.player1.trophies
              }
            )
          .concat if type is 'ladder'
            # graphs p2
            _.map(player2UserIds, (userId) ->
              GameRecord.create {
                userId: userId
                playerId: player2Tag
                gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                scaledTime
                value: match.player2.trophies
              }
            )
          ).concat [
            prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID
            key = "#{prefix}:#{matchId}"
            CacheService.deleteByKey key
            Match.create {
              id: matchId
              arena: match.arena
              league: match.league
              matchId: match.id
              type: match.type
              player1Id: match.player1.playerTag
              player2Id: match.player2.playerTag
              # player1UserIds: player1UserIds
              # player2UserIds: player2UserIds
              winningDeckId: winningDeckId
              losingDeckId: losingDeckId
              winningCardIds: winningDeckCardIds
              losingCardIds: losingDeckCardIds
              player1Data: @getMatchPlayerData {
                player: match.player1, deck: deck1
              }
              player2Data: @getMatchPlayerData {
                player: match.player2, deck: deck2
              }
              time: new Date(match.time)
            }
          ])

          .catch (err) ->
            console.log 'err', err
    .then ->
      {playerDiffs}

  # current deck being used
  storeCurrentDeck: ({playerData, userId}) ->
    ClashRoyaleDeck.getByCardKeys _.map(playerData.currentDeck, 'key'), {
      preferCache: true
    }
    .then (deck) ->
      ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
        deck.id
        userId
        {isFavorited: true, isCurrentDeck: true}
      )

  # morph api format to our format
  getUserGameDataFromPlayerData: ({playerData}) ->
    {
      currentDeck: playerData.currentDeck
      trophies: playerData.trophies
      name: playerData.name
      clan: if playerData.clan
      then { \
        tag: playerData.clan.tag, \
        name: playerData.clan.name
      }
      else null
      level: playerData.level
      arena: playerData.arena
      league: playerData.league
      stats: _.merge playerData.stats, {
        games: playerData.games
        tournamentGames: playerData.tournamentGames
        wins: playerData.wins
        losses: playerData.losses
        currentStreak: playerData.currentStreak
      }
    }

  updatePlayerMatches: ({matches, tag}) =>
    trophies = if matches[0].player1.playerTag is tag \
               then matches[0].player1.trophies
               else matches[0].player2.trophies
    diff = {
      data:
        lastMatchTime: new Date(matches[0].time)
        trophies: trophies
      lastUpdateTime: new Date()
    }
    # get before update so we have accurate lastMatchTime
    UserGameData.getByPlayerIdAndGameId tag, GAME_ID
    .then (userGameData) =>
      Promise.all [
        UserGameData.upsertByPlayerIdAndGameId tag, GAME_ID, diff
        @processMatches {tag, matches, userGameData}
      ]
    .then ([userDataUpsert, {playerDiffs}]) ->
      console.log 'got', playerDiffs
      Promise.all _.map playerDiffs, (diff, playerId) ->
        UserGameData.upsertByPlayerIdAndGameId playerId, GAME_ID, diff

  updatePlayerData: ({userId, playerData, tag}) =>
    console.log 'update player data', tag
    unless tag
      return

    diff = {
      lastUpdateTime: new Date()
      playerId: tag
      data: @getUserGameDataFromPlayerData {playerData}
    }

    UserGameData.upsertByPlayerIdAndGameId tag, GAME_ID, diff, {userId}
    .then =>
      if userId # TODO: update for all userIds of playerTag/playerId
        @storeCurrentDeck {playerData, userId: userId}

  # half-hour cron
  process: ->
    console.log 'go'
    start = Date.now()
    UserGameData.getStaleByGameId GAME_ID, {
      staleTimeMs: 0# FIXME STALE_TIME_MS
    }
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      # TODO: problem with this is if job errors, that user never gets
      # updated ever again
      # UserGameData.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
      #   isQueued: true
      # }
      playerIdChunks = _.chunk playerIds, BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}/games", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
        }
    # .then ->
    #   Group.getStale {gameId: id, staleTimeMs: STALE_TIME_MS}
    #   .then (groups) =>
    #     Promise.each groups, @processClan

    .then ->
      timeToComplete = Date.now() - start
      if timeToComplete >= MAX_TIME_TO_COMPLETE_MS
        EmailService.send {
          to: EmailService.EMAILS.OPS
          subject: 'Clash API too slow'
          text: "Took longer than #{MAX_TIME_TO_COMPLETE_MS}ms"
        }

module.exports = new ClashAPIService()
