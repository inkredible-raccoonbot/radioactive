_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

GameRecordType = require '../models/game_record_type'
User = require '../models/user'
EmbedService = require '../services/embed'
config = require '../config'

allowedClientEmbeds = ['meValues']

class GameRecordTypeCtrl

  getAllByUserIdAndGameId: ({userId, gameId, embed}, {user}) ->
    embed ?= []
    embed = _.filter embed, (item) ->
      allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.GAME_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

    User.getById userId
    .then (user) ->
      unless user
        router.throw {status: 400, info: 'user not found'}
      # GameRecordType.getAllByGameId gameId
      Promise.resolve([
        {
          id: config.CLASH_ROYALE_TROPHIES_RECORD_ID
          name: 'Trophies'
          timeScale: 'minutes'
          gameId: config.CLASH_ROYALE_ID
        }
      ])
      .map EmbedService.embed {embed, user}

module.exports = new GameRecordTypeCtrl()