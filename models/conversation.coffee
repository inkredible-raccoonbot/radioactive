_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
Group = require './group'

CONVERSATIONS_TABLE = 'conversations'
USER_IDS_INDEX = 'userIds'
GROUP_ID_INDEX = 'groupId'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

defaultConversation = (conversation) ->
  unless conversation?
    return null

  _.defaults conversation, {
    id: uuid.v4()
    userIds: []
    groupId: null
    userData: {}
    lastUpdateTime: new Date()
  }

class ConversationModel
  RETHINK_TABLES: [
    {
      name: CONVERSATIONS_TABLE
      options: {}
      indexes: [
        {name: USER_IDS_INDEX, options: {multi: true}}
        {name: GROUP_ID_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (conversation) ->
    conversation = defaultConversation conversation

    if conversation.groupId
      conversation.id =
        'c-' + conversation.groupId + (conversation.channelId or '')

    # replace will create 1 unique row for conversation.id
    r.table CONVERSATIONS_TABLE
    .get conversation.id
    .replace conversation
    .run()
    .then ->
      conversation

  getById: (id) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .run()
    .then defaultConversation

  getByGroupId: (groupId) ->
    r.table CONVERSATIONS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultConversation

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10

    r.table CONVERSATIONS_TABLE
    .getAll userId, {index: USER_IDS_INDEX}
    .orderBy r.desc(LAST_UPDATE_TIME_INDEX)
    .limit limit
    .run()
    .map defaultConversation

  getByUserIds: (checkUserIds, {limit} = {}) ->
    q = r.table CONVERSATIONS_TABLE
    .getAll checkUserIds[0], {index: USER_IDS_INDEX}
    .filter (conversation) ->
      r.expr(checkUserIds).filter (userId) ->
        conversation('userIds').contains(userId)
      .count()
      .eq(conversation('userIds').count())

    .nth 0
    .default null
    .run()
    .then defaultConversation

  hasPermission: (conversation, userId) ->
    if conversation.groupId
      Group.getById conversation.groupId
      .then (group) ->
        group and group.userIds.indexOf(userId) isnt -1
    else
      Promise.resolve userId and conversation.userIds.indexOf(userId) isnt -1

  markRead: ({id, userIds}, userId) =>
    @updateById id, {
      userData:
        "#{userId}": {isRead: true}
    }

  updateById: (id, diff) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, conversation) ->
    _.pick conversation, [
      'id'
      'userIds'
      'userData'
      'users'
      'groupId'
      'lastUpdateTime'
      'lastMessage'
      'embedded'
    ]

module.exports = new ConversationModel()
