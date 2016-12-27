#!/bin/bash
BUNDLE_GEMFILE="$(dirname $0)"/Gemfile bundle exec "$(dirname $0)"/puppetdb.rb $@
