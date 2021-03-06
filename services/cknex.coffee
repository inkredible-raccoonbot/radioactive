cassanknex = require 'cassanknex'
cassandra = require 'cassandra-driver'
Promise = require 'bluebird'
moment = require 'moment'
_ = require 'lodash'

config = require '../config'

distance = cassandra.types.distance

contactPoints = config.SCYLLA.CONTACT_POINTS

cassanknexInstance = cassanknex
  connection:
    contactPoints: contactPoints
  exec:
    prepare: true
  pooling:
    coreConnectionsPerHost:
      "#{distance.local}": 4
      "#{distance.remote}": 1

# queryCount = 0
# setInterval ->
#   if queryCount
#     console.log 'qps', queryCount
#   queryCount = 0

ready = new Promise (resolve, reject) ->
  cassanknexInstance.on 'ready', (err, res) ->
    console.log 'cassandra', err, res
    if err
      reject err
    else

      resolve res

cknex = ->
  instance = cassanknexInstance('clash_royale')
  instance.run = (options = {}) -> # skinny arrow on purpose
    self = this
    ready.then ->
      new Promise (resolve, reject) ->
        self.exec options, (err, result) ->
          # queryCount += 1
          if err
            reject err
          else if options.returnPageState
            resolve result
          else if options.isSingle
            resolve result.rows?[0]
          else
            resolve result.rows
  instance

cknex.getTimeUuid = (time) ->
  if time
    unless time instanceof Date
      time = moment(time).toDate()
    cassandra.types.TimeUuid.fromDate time
  else
    cassandra.types.TimeUuid.now()

cknex.getTime = (time) ->
  if time
    unless time instanceof Date
      time = moment(time).toDate()
    time
  else
    new Date()

cknex.chunkForBatch = (rows) ->
  # batch accepts max 50kb
  chunks = []
  chunkSize = 0
  chunkIndex = 0
  maxChunkSize = 30 * 1024 # 30kb. for some reason need a big buffer from 50
  _.forEach rows, (row) ->
    prevChunkSize = chunkSize
    chunkSize += JSON.stringify(row).length
    if prevChunkSize and chunkSize > maxChunkSize
      chunkSize = 0
      chunkIndex += 1
      chunks[chunkIndex] = []
    else if chunkIndex is 0
      chunks[chunkIndex] ?= []
    chunks[chunkIndex].push row
  return chunks

# batching shouldn't be used much. 50kb limit and:
# https://docs.datastax.com/en/cql/3.1/cql/cql_using/useBatch.html
cknex.batchRun = (queries) ->
  # queryCount += queries.length
  ready.then ->
    new Promise (resolve, reject) ->
      cassanknexInstance()
      .batch {prepare: true, logged: false}, queries, (err, result) ->
        if err
          reject err
        else
          resolve result

module.exports = cknex
