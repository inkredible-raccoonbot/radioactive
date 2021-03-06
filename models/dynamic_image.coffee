_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

USER_ID_IMAGE_KEY_INDEX = 'userIdGameId'

defaultDynamicImages = (playersDaily) ->
  unless playersDaily?
    return null

  _.defaults playersDaily, {
    id: uuid.v4()
    imageKey: null
    userId: null
    data: {}
  }

DYNAMIC_IMAGES_TABLE = 'dynamic_images'

class DynamicImagesModel
  RETHINK_TABLES: [
    {
      name: DYNAMIC_IMAGES_TABLE
      indexes: [
        {name: USER_ID_IMAGE_KEY_INDEX, fn: (row) ->
          [row('userId'), row('imageKey')]}
      ]
    }
  ]

  getByUserIdAndImageKey: (userId, imageKey) ->
    r.table DYNAMIC_IMAGES_TABLE
    .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultDynamicImages
    .then (playersDaily) ->
      _.defaults {userId}, playersDaily

  upsertByUserIdAndImageKey: (userId, imageKey, diff) ->
    r.table DYNAMIC_IMAGES_TABLE
    .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
    .nth 0
    .default null
    .do (playersDaily) ->
      r.branch(
        playersDaily.eq null

        r.table DYNAMIC_IMAGES_TABLE
        .insert defaultDynamicImages _.defaults _.clone(diff), {
          userId
          imageKey
        }

        r.table DYNAMIC_IMAGES_TABLE
        .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

module.exports = new DynamicImagesModel()
