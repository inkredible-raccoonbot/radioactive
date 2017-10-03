_ = require 'lodash'

ClashRoyalePlayerBase = require './clash_royale_player_base'
config = require '../config'

class ClashRoyalePlayerDailyModel extends ClashRoyalePlayerBase
  TABLE_NAME: 'players_daily_by_id'

module.exports = new ClashRoyalePlayerDailyModel()
