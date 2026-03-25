-ifndef(__protoMsg_h__).
-define(__protoMsg_h__, true).

-type int8() :: -128..127.
-type int16() :: -32768..32767.
-type int32() :: -2147483648..2147483647.
-type int64() :: -9223372036854775808..9223372036854775807.
-type uint8() :: 0..255.
-type uint16() :: 0..65535.
-type uint32() :: 0..4294967295.
-type uint64() :: 0..18446744073709551615.
-type double() :: float().



-record(playerInfo, {
	index = 0 :: int32()
	, name = "" :: string()
	, score = 0 :: int32()
	, wins = 0 :: int32()
	, losses = 0 :: int32()
	, status = 0 :: int32()
}).
-record(roomInfo, {
	roomId = "" :: string()
	, name = "" :: string()
	, playerCount = 0 :: int32()
	, status = 0 :: int32()
}).
-record(card, {
	suit = 0 :: int32()
	, value = 0 :: int32()
}).
-record(scoreInfo, {
	index = 0 :: int32()
	, name = "" :: string()
	, score = 0 :: int32()
	, result = "" :: string()
}).
-record(sc_error, {
	code = 0 :: int32()
	, msg = "" :: string()
}).
-record(cs_handshake, {
	encrypt1 = 0 :: int32()
	, encrypt2 = 0 :: int32()
}).
-record(sc_handshake, {
	result = 0 :: int32()
}).
-record(cs_heartbeat, {
	}).
-record(sc_heartbeat, {
	}).
-record(cs_login, {
	name = "" :: string()
}).
-record(sc_login, {
	result = 0 :: int32()
	, playerId = "" :: string()
	, player = undefined :: #playerInfo{}
}).
-record(cs_list_rooms, {
	}).
-record(sc_list_rooms, {
	rooms = [] :: [#roomInfo{}]
}).
-record(cs_create_room, {
	name = "" :: string()
}).
-record(sc_room_update, {
	roomId = "" :: string()
	, status = 0 :: int32()
	, players = [] :: [#playerInfo{}]
}).
-record(cs_join_room, {
	roomId = "" :: string()
}).
-record(cs_leave_room, {
	roomId = "" :: string()
}).
-record(cs_quick_match, {
	}).
-record(cs_add_ai, {
	}).
-record(sc_ai_added, {
	name = "" :: string()
	, index = 0 :: int32()
}).
-record(cs_game_start, {
	}).
-record(sc_game_start, {
	cards = [] :: [#card{}]
	, firstBidder = 0 :: int32()
}).
-record(cs_bid, {
	score = 0 :: int32()
}).
-record(sc_bid_made, {
	playerIdx = 0 :: int32()
	, score = 0 :: int32()
}).
-record(sc_turn_to_bid, {
	nextTurn = 0 :: int32()
	, currentBids = [] :: [int32()]
}).
-record(cs_play, {
	cards = [] :: [#card{}]
}).
-record(sc_player_played, {
	playerIdx = 0 :: int32()
	, cards = [] :: [#card{}]
}).
-record(cs_pass, {
	}).
-record(sc_player_passed, {
	playerIdx = 0 :: int32()
}).
-record(cs_play_hint, {
	}).
-record(sc_play_hint, {
	cards = [] :: [#card{}]
}).
-record(sc_turn_to_play, {
	nextTurn = 0 :: int32()
	, lastPlay = [] :: [#card{}]
}).
-record(sc_landlord_selected, {
	landlordIdx = 0 :: int32()
	, landlordCards = [] :: [#card{}]
	, baseScore = 0 :: int32()
}).
-record(sc_game_over, {
	winnerIdx = 0 :: int32()
	, scores = [] :: [#scoreInfo{}]
}).
-record(cs_ready, {
	ready = 0 :: int32()
}).
-record(sc_player_ready, {
	playerIdx = 0 :: int32()
	, ready = 0 :: int32()
	, allReady = 0 :: int32()
}).

-endif.