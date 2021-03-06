_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Conversation = require '../models/conversation'
Group = require '../models/group'
Event = require '../models/event'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CONVERSATION.USERS]
lastMessageEmbed = [
  EmbedService.TYPES.CONVERSATION.LAST_MESSAGE
  EmbedService.TYPES.CONVERSATION.USERS
]

class ConversationCtrl
  create: ({userIds, groupId, name, description}, {user}) ->
    userIds ?= []
    userIds = _.uniq userIds.concat [user.id]

    name = name and _.kebabCase(name.toLowerCase()).replace(/[^0-9a-z-]/gi, '')

    if groupId
      conversation = Conversation.getByGroupIdAndName groupId, name
      hasPermission = Group.hasPermissionByIdAndUser groupId, user, {
        level: 'admin'
      }
      .then (hasPermission) ->
        unless hasPermission
          router.throw {status: 400, info: 'You don\'t have permission'}
        hasPermission
    else
      conversation = Conversation.getByUserIds userIds
      hasPermission = Promise.resolve true

    Promise.all [conversation, hasPermission]
    .then ([conversation, hasPermission]) ->
      return conversation or Conversation.create {
        userIds
        groupId
        name
        description
        type: if groupId then 'channel' else 'pm'
        # TODO: different way to track if read (groups get too large)
        # should store lastReadTime on user for each group
        userData: unless groupId
          _.zipObject userIds, _.map (userId) ->
            {
              isRead: userId is user.id
            }
      }

  updateById: ({id, name, description}, {user}) ->
    name = name and _.kebabCase(name.toLowerCase()).replace(/[^0-9a-z-]/gi, '')

    Conversation.getById id
    .tap (conversation) ->
      Group.hasPermissionByIdAndUser conversation.groupId, user, {
        level: 'admin'
      }
      .then (hasPermission) ->
        unless hasPermission
          router.throw {status: 400, info: 'You don\'t have permission'}
    .then ->
      Conversation.updateById id, {name, description}

  getAll: ({}, {user}) ->
    Conversation.getAllByUserId user.id
    .map EmbedService.embed {embed: lastMessageEmbed}
    .map Conversation.sanitize null

  getById: ({id}, {user}) ->
    Conversation.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .tap (conversation) ->
      if conversation.groupId
        # FIXME FIXME: channel perms
        Group.hasPermissionByIdAndUser conversation.groupId, user
        .then (hasPermission) ->
          unless hasPermission
            router.throw status: 400, info: 'no permission'
      else if conversation.eventId
        Event.hasPermissionByIdAndUser conversation.eventId, user
        .then (hasPermission) ->
          unless hasPermission
            router.throw status: 400, info: 'no permission'
      else if conversation.userIds.indexOf(user.id) is -1
        router.throw status: 400, info: 'no permission'

      # TODO: different way to track if read (groups get too large)
      # should store lastReadTime on user for each group
      unless conversation.groupId
        Conversation.markRead conversation, user.id
    .then Conversation.sanitize null


module.exports = new ConversationCtrl()
