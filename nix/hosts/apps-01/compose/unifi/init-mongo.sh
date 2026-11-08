#!/bin/bash
# The image's own docs' init script (linuxserver/docker-unifi-network-application),
# reading everything from the unifi-db container's environment, so no secret is in this
# file. Run once by the mongo entrypoint, on an empty /data/db. Replaces prod's
# templated init-mongo.js, which created the user in the `unifi` database instead of
# `admin`.
mongosh <<EOF
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.createUser({
  user: "${MONGO_USER}",
  pwd: "${MONGO_PASS}",
  roles: [
    { db: "${MONGO_DBNAME}", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_audit", role: "dbOwner" },
    // A restore imports the .unf into this scratch database first, then swaps it in.
    { db: "${MONGO_DBNAME}_restore", role: "dbOwner" }
  ]
})
EOF
