_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

defaultChatMessage = (chatMessage) ->
  unless chatMessage?
    return null

  _.defaults chatMessage, {
    id: uuid.v4()
    userId: null
    conversationId: null
    time: new Date()
    body: ''
  }

CHAT_MESSAGES_TABLE = 'chat_messages'
TIME_INDEX = 'time'
CONVERSATION_ID_INDEX = 'conversationId'
CONVERSATION_ID_TIME_INDEX = 'conversationIdTime'
MAX_MESSAGES = 40
FIVE_MINUTES_SECONDS = 60 * 5
TWELVE_HOURS_SECONDS = 3600 * 12
SEVEN_DAYS_SECONDS = 3600 * 24 * 7
TWO_SECONDS = 2

class ChatMessageModel
  RETHINK_TABLES: [
    {
      name: CHAT_MESSAGES_TABLE
      indexes: [
        {name: TIME_INDEX}
        {name: CONVERSATION_ID_INDEX}
        {name: CONVERSATION_ID_TIME_INDEX, fn: (row) ->
          [row('conversationId'), row('time')]}
      ]
    }
  ]

  default: defaultChatMessage

  create: (chatMessage) ->
    chatMessage = defaultChatMessage chatMessage

    r.table CHAT_MESSAGES_TABLE
    .insert chatMessage
    .run()
    .then ->
      chatMessage

  # TODO: look into perf of this...
  getAllByConversationId: (conversationId, {isStreamed}) ->
    r.table CHAT_MESSAGES_TABLE
    .between [conversationId], [conversationId + 'z'], {
      index: CONVERSATION_ID_TIME_INDEX
    }
    .orderBy {index: r.desc(CONVERSATION_ID_TIME_INDEX)}
    # NOTE: a limit on the actual query we subscribe to causes
    # all inserts to show as 'change's since it's change the top 30 (limit)
    .limit MAX_MESSAGES
    .run()
    .then (messages) ->
      startTime = _.last(messages)?.time or new Date()
      endTime = moment(startTime).add(1, 'year').toDate()
      q = r.table CHAT_MESSAGES_TABLE
      .between(
        [conversationId, startTime]
        [conversationId, endTime]
        {index: CONVERSATION_ID_TIME_INDEX}
      )

      if isStreamed
        q = q.changes {
          includeInitial: true
          includeTypes: true
          includeStates: true
          squash: true
        }

      q.run()

  getById: (id) ->
    r.table CHAT_MESSAGES_TABLE
    .get id
    .run()
    .then defaultChatMessage

  deleteById: (id) ->
    r.table CHAT_MESSAGES_TABLE
    .get id
    .delete()
    .run()

  getLastByConversationId: (conversationId) ->
    r.table CHAT_MESSAGES_TABLE
    .between [conversationId], [conversationId + 'z'], {
      index: CONVERSATION_ID_TIME_INDEX
    }
    .orderBy {index: r.desc(CONVERSATION_ID_TIME_INDEX)}
    .nth 0
    .default null
    .run()
    .then defaultChatMessage

  updateById: (id, diff) ->
    r.table CHAT_MESSAGES_TABLE
    .get id
    .update diff
    .run()

  deleteOld: ->
    Promise.all [
      r.table CHAT_MESSAGES_TABLE
      .between 0, r.now().sub(TWELVE_HOURS_SECONDS), {index: TIME_INDEX}
      .filter(
        r.row('channelId').default(null).eq(null)
      )
      .delete()

      r.table CHAT_MESSAGES_TABLE
      .between 0, r.now().sub(SEVEN_DAYS_SECONDS), {index: TIME_INDEX}
      .delete()
    ]


module.exports = new ChatMessageModel()
