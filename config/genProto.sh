#!/bin/bash
cd "$(dirname "$0")"
escript config/genProto proto erl include src/proto ts cli/src/network/proto "$@"
