_ = require 'lodash'
Joi = require 'joi'
router = require 'exoid-router'

UserFollower = require '../models/user_follower'
User = require '../models/user'
EmbedService = require '../services/embed'
PushNotificationService = require '../services/push_notification'
schemas = require '../schemas'

defaultEmbed = []

class UserFollowerCtrl
  getAllFollowingIds: ({userId, embed}, {user}) ->
    userId ?= user.id
    UserFollower.getAllByUserId userId
    .map (userFollower) ->
      userFollower.followingId

  getAllFollowerIds: ({userId, embed}, {user}) ->
    userId ?= user.id
    UserFollower.getAllByFollowerId userId
    .map (userFollower) ->
      userFollower.userId

  followByUserId: ({userId}, {user}) ->
    followingId = userId
    valid = Joi.validate {followingId}, {
      followingId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw {
        status: 400, info: valid.error.message, ignoreLog: true
      }

    UserFollower.create {userId: user.id, followingId: followingId}
    .then ->
      User.getById followingId
      .then (otherUser) ->
        PushNotificationService.send otherUser, {
          title: 'New follower'
          type: PushNotificationService.TYPES.NEW_FRIEND
          url: "https://#{config.SUPERNOVA_HOST}"
          text: "#{User.getDisplayName(user)} added you as a friend"
          data: {path: '/friends'}
        }
      .catch -> null
      # key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING_PLAYERS}:#{user.id}"
      # CacheService.deleteByKey key
      null

  unfollowByUserId: ({userId}, {user}) ->
    followingId = userId
    valid = Joi.validate {followingId}, {
      followingId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw {
        status: 400
        info: valid.error.message
        ignoreLog: true
      }

    UserFollower.deleteByFollowingIdAndUserId followingId, user.id
    # key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING}:#{user.id}"
    # CacheService.deleteByKey key
    # null


module.exports = new UserFollowerCtrl()
