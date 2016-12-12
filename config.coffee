_ = require 'lodash'
assertNoneMissing = require 'assert-none-missing'

env = process.env

REDIS_PORT = if env.IS_STAGING is '1' then 6378 else 6379

config =
  VERBOSE: if env.VERBOSE then env.VERBOSE is '1' else true
  PORT: env.RADIOACTIVE_PORT or 50000
  ENV: env.NODE_ENV
  JWT_ES256_PRIVATE_KEY: env.JWT_ES256_PRIVATE_KEY
  JWT_ES256_PUBLIC_KEY: env.JWT_ES256_PUBLIC_KEY
  JWT_ISSUER: 'exoid'
  # FIXME FIXME
  APN_CERT: env.RADIOACTIVE_APN_CERT
  APN_KEY: env.RADIOACTIVE_APN_KEY
  APN_PASSPHRASE: env.RADIOACTIVE_APN_PASSPHRASE
  GOOGLE_PRIVATE_KEY_JSON: env.GOOGLE_PRIVATE_KEY_JSON
  GOOGLE_API_KEY: env.GOOGLE_API_KEY
  CARD_CODE_MAX_LENGTH: 9999999999
  PCG_SEED: env.RADIOACTIVE_PCG_SEED
  PT_UTC_OFFSET: -8
  IOS_BUNDLE_ID: 'com.clay.redtritium'
  GOOGLE:
    CLIENT_ID: env.GOOGLE_CLIENT_ID
    CLIENT_SECRET: env.GOOGLE_CLIENT_SECRET
    REFRESH_TOKEN: env.GOOGLE_REFRESH_TOKEN
    REDIRECT_URL: 'urn:ietf:wg:oauth:2.0:oob'
  GMAIL:
    USER: env.GMAIL_USER
    PASS: env.GMAIL_PASS
  RETHINK:
    DB: env.RETHINK_DB or 'radioactive'
    HOST: env.RETHINK_HOST or 'localhost'
  REDIS:
    PREFIX: 'radioactive'
    PORT: REDIS_PORT
    NODES: if env.REDIS_CLUSTER_HOSTS \
           then _.map env.REDIS_CLUSTER_HOSTS.split(','), (host) -> {host, port: REDIS_PORT}
           else [env.REDIS_HOST]
  CDN_HOST: env.CDN_HOST
  AWS:
    REGION: 'us-west-2'
    CDN_BUCKET: env.AWS_CDN_BUCKET
    ACCESS_KEY_ID: env.AWS_ACCESS_KEY_ID
    SECRET_ACCESS_KEY: env.AWS_SECRET_ACCESS_KEY
  ENVS:
    DEV: 'development'
    PROD: 'production'
    TEST: 'test'

assertNoneMissing config

module.exports = config