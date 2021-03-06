Redis = require 'ioredis'
_ = require 'lodash'

config = require '../config'

# if config.REDIS.NODES.length is 1
client = new Redis {
  port: config.REDIS.PORT
  host: config.REDIS.RADIOACTIVE_HOST
}
# else
#   client = new Redis.Cluster _.filter(config.REDIS.NODES), {
#     scaleReads: 'all'
#   }

events = ['connect', 'ready', 'error', 'close', 'reconnecting', 'end']
_.map events, (event) ->
  client.on event, ->
    console.log "redislog #{event}"

module.exports = client
