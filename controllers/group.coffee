_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
UserData = require '../models/user_data'
Group = require '../models/group'
GroupUser = require '../models/group_user'
Clan = require '../models/clan'
Game = require '../models/game'
Conversation = require '../models/conversation'
GroupRecordType = require '../models/group_record_type'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.GROUP.USERS
  EmbedService.TYPES.GROUP.CONVERSATIONS
  EmbedService.TYPES.GROUP.STAR
]
userDataEmbed = [
  EmbedService.TYPES.USER.DATA
]
defaultGroupRecordTypes = [
  {name: 'Donations', timeScale: 'week'}
  {name: 'Crowns', timeScale: 'week'}
]

FIVE_MINUTES_SECONDS = 60 * 5

class GroupCtrl
  create: ({name, description, badgeId, background, mode, clanId}, {user}) ->
    creatorId = user.id

    # Game.getByKey 'clashRoyale'
    Promise.resolve {id: config.CLASH_ROYALE_ID}
    .then ({id}) ->
      Group.create {
        name, description, badgeId, background, creatorId, mode
        gameIds: [id]
        gameData:
          "#{id}":
            clanId: clanId
      }
    .tap ({id}) ->
      Promise.all [
        Group.addUser id, user.id
        Conversation.create {
          groupId: id
          name: 'general'
          type: 'channel'
        }
        Promise.map defaultGroupRecordTypes, ({name, timeScale}) ->
          GroupRecordType.create {
            name: name
            timeScale: timeScale
            groupId: id
            creatorId: user.id
          }
      ]

  updateById: ({id, name, description, badgeId, background, mode}, {user}) ->
    Group.hasPermissionByIdAndUserId id, user.id, {level: 'admin'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw {status: 400, info: 'You don\'t have permission'}

      Group.updateById id, {name, description, badgeId, background, mode}

  # FIXME: need to add some notion of invitedIds for group_users
  # inviteById: ({id, userIds}, {user}) ->
  #   groupId = id
  #
  #   unless groupId
  #     router.throw {status: 404, info: 'Group not found'}
  #
  #   Promise.all [
  #     Group.getById groupId
  #     Promise.map userIds, User.getById
  #   ]
  #   .then ([group, toUsers]) ->
  #     unless group
  #       router.throw {status: 404, info: 'Group not found'}
  #     if _.isEmpty toUsers
  #       router.throw {status: 404, info: 'User not found'}
  #
  #     hasPermission = Group.hasPermission group, user
  #     unless hasPermission
  #       router.throw {status: 400, info: 'You don\'t have permission'}
  #
  #     Promise.map toUsers, EmbedService.embed userDataEmbed
  #     .map (toUser) ->
  #       senderName = User.getDisplayName user
  #       groupInvitedIds = toUser.data.groupInvitedIds or []
  #       unreadGroupInvites = toUser.data.unreadGroupInvites or 0
  #       UserData.upsertByUserId toUser.id, {
  #         groupInvitedIds: _.uniq groupInvitedIds.concat [id]
  #         unreadGroupInvites: unreadGroupInvites + 1
  #       }
  #       PushNotificationService.send toUser, {
  #         title: 'New group invite'
  #         text: "#{senderName} invited you to the group, #{group.name}"
  #         type: PushNotificationService.TYPES.GROUP
  #         url: "https://#{config.CLIENT_HOST}"
  #         data:
  #           path: "/group/#{group.id}"
  #       }
  #
  #     Group.updateById groupId,
  #       invitedIds: _.uniq group.invitedIds.concat(userIds)

  leaveById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Promise.all [
      EmbedService.embed {embed: userDataEmbed}, user
      Group.getById groupId
    ]
    .then ([user, group]) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      Promise.all [
        UserData.upsertByUserId user.id, {
          groupIds: _.filter user.data.groupIds, (id) -> groupId isnt id
        }
        Group.removeUser groupId, userId
      ]

  joinById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Promise.all [
      EmbedService.embed {embed: userDataEmbed}, user
      Group.getById groupId
    ]
    .then ([user, group]) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      if group.mode is 'private' and group.invitedIds.indexOf(userId) is -1
        router.throw {status: 401, info: 'Not invited'}

      name = User.getDisplayName user

      if group.type isnt 'public'
        PushNotificationService.sendToGroup(group, {
          title: 'New group member'
          text: "#{name} joined your group."
          type: PushNotificationService.TYPES.CREW
          url: "https://#{config.CLIENT_HOST}"
          path: "/group/#{group.id}/chat"
        }, {skipMe: true, meUserId: user.id}).catch -> null

      groupIds = user.data.groupIds or []
      Promise.all [
        UserData.upsertByUserId user.id, {
          groupIds: _.uniq groupIds.concat [groupId]
          invitedIds: _.filter user.data.invitedIds, (id) -> id isnt groupId
        }
        Group.addUser groupId, userId
        # Group.updateById groupId,
        #   userIds: _.uniq group.userIds.concat([userId])
        #   invitedIds: _.filter group.invitedIds, (id) -> id isnt userId
      ]

  getAll: ({filter, language}, {user}) ->
    key = CacheService.PREFIXES.GROUP_GET_ALL + ':' + [
      user.id, filter, language
    ].join(':')
    category = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY + ':' + user.id

    CacheService.preferCache key, ->
      (if filter is 'mine'
        GroupUser.getAllByUserId user.id
        .map ({groupId}) -> groupId
        .then (groupIds) ->
          Group.getAllByIds groupIds
      else
        Group.getAll {filter, language}
      )
      .then (groups) ->
        if filter is 'public' and _.isEmpty groups
          Group.getAll {filter}
        else
          groups
      .map EmbedService.embed {embed: defaultEmbed}
      .map (group) ->
        if not _.isEmpty group.clanIds
          group.clan = Clan.getByClanIdAndGameId(
            group.clanIds[0], config.CLASH_ROYALE_ID
          )

        Promise.props group

      .map Group.sanitize null
    , {
      expireSeconds: FIVE_MINUTES_SECONDS
      category: category
    }

  getById: ({id}, {user}) ->
    Group.getById id
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Group.sanitize null

module.exports = new GroupCtrl()
