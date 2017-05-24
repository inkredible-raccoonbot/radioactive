_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
r = require '../services/rethinkdb'
config = require '../config'

HEALTHCHECK_TIMEOUT = 60000
AUSTIN_TAG = '22CJ9CQC0'


class HealthCtrl
  check: (req, res, next) ->
    Promise.all [
      r.dbList().run().timeout HEALTHCHECK_TIMEOUT
      ClashRoyaleAPIService.getPlayerDataByTag AUSTIN_TAG, {
        priority: 'high'
        skipCache: true
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
      ClashRoyaleAPIService.getPlayerMatchesByTag AUSTIN_TAG, {
        priority: 'high'
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
    ]
    .then ([rethinkdb, playerData, playerMatches]) ->
      result =
        rethinkdb: Boolean rethinkdb
        playerData: playerData?.tag is AUSTIN_TAG
        playerMatches: Boolean playerMatches

      result.healthy = _.every _.values result
      return result
    .then (status) ->
      res.json status
    .catch next

  checkThrow: (req, res, next) ->
    r.dbList().run()
    .then (rethinkdb) ->
      if Boolean rethinkdb
        res.send 'ok'
      else
        throw new Error 'rethink unhealthy'
    .catch ->
      # pod will restart from kubernetes probe
      res.status(400).send 'fail'

module.exports = new HealthCtrl()
