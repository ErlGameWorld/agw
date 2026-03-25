-module(protoMsg).


-compile([nowarn_unused_vars, nowarn_unused_function]).

-export([encodeIol/1, encodeBin/1,  encodeIol/2, subEncode/1, subEncode/2, decode/1,  decodeBin/2, getMsgName/1]).

-define(min8, -128).
-define(max8, 127).
-define(min16, -32768).
-define(max16, 32767).
-define(min32, -2147483648).
-define(max32, 2147483647).
-define(min64, -9223372036854775808).
-define(max64, 9223372036854775807).

-define(minF32, 1.175494351E-38).
-define(maxF32, 3.402823466E+38).
-define(minF64, 2.2250738585072014E-308).
-define(maxF64, 1.7976931348623158E+308).

-define(int8(V), <<V:8>>).
-define(uint8(V), <<V:8>>).
-define(int16(V), <<V:16/big>>).
-define(uint16(V), <<V:16/big>>).
-define(int32(V), <<V:32/big>>).
-define(uint32(V), <<V:32/big>>).
-define(int64(V), <<V:64/big>>).
-define(uint64(V), <<V:64/big>>).
-define(integer(V), (integer(V))).
-define(number(V), (number(V))).
-define(string(V), (string(V))).
-define(float(V), <<V:32/big-float>>).
-define(double(V), <<V:64/big-float>>).
-define(bool(V), (case V of true -> <<1:8>>; _ -> <<0:8>> end)).
-define(record(V), (case V of undefined -> [<<0:8>>]; V -> [<<1:8>>, subEncode(V)] end)).
-define(list_bool(List), [<<(listLen(List)):16/big>>, [?bool(V) || V <- List]]).
-define(list_int8(List), [<<(listLen(List)):16/big>>, [?int8(V) || V <- List]]).
-define(list_uint8(List), [<<(listLen(List)):16/big>>, [?uint8(V) || V <- List]]).
-define(list_int16(List), [<<(listLen(List)):16/big>>, [?int16(V) || V <- List]]).
-define(list_uint16(List), [<<(listLen(List)):16/big>>, [?uint16(V) || V <- List]]).
-define(list_int32(List), [<<(listLen(List)):16/big>>, [?int32(V) || V <- List]]).
-define(list_uint32(List), [<<(listLen(List)):16/big>>, [?uint32(V) || V <- List]]).
-define(list_int64(List), [<<(listLen(List)):16/big>>, [?int64(V) || V <- List]]).
-define(list_uint64(List), [<<(listLen(List)):16/big>>, [?uint64(V) || V <- List]]).
-define(list_float(List), [<<(listLen(List)):16/big>>, [?float(V) || V <- List]]).
-define(list_double(List), [<<(listLen(List)):16/big>>, [?double(V) || V <- List]]).
-define(list_integer(List), [<<(listLen(List)):16/big>>, [integer(V) || V <- List]]).
-define(list_number(List), [<<(listLen(List)):16/big>>, [number(V) || V <- List]]).
-define(list_string(List), [<<(listLen(List)):16/big>>, [string(V) || V <- List]]).
-define(list_record(List), [<<(listLen(List)):16/big>>, [subEncode(V) || V <- List]]).

listLen(List) ->
   Len = length(List),
   case Len > 65535 of
      true ->
         throw({list_too_long, Len, List});
      _ ->
         Len
   end.

-define(BinaryShareSize, 65).
-define(BinaryCopyRatio, 1.2).

integer(V) when is_integer(V) ->
   if
      V >= ?min8 andalso V =< ?max8 ->
         <<8:8, <<V:8>>/binary>>;
      V >= ?min16 andalso V =< ?max16 ->
         <<16:8, <<V:16/big>>/binary>>;
      V >= ?min32 andalso V =< ?max32 ->
         <<32:8, <<V:32/big>>/binary>>;
      V >= ?min64 andalso V =< ?max64 ->
         <<64:8, <<V:64/big>>/binary>>;
      true ->
         throw({exceeded_the_integer, V})
   end;
integer(V) ->
   throw({not_an_integer, V}).

number(V) ->
   if
      erlang:is_integer(V) ->
         if
            V >= ?min8 andalso V =< ?max8 ->
               <<8:8, <<V:8>>/binary>>;
            V >= ?min16 andalso V =< ?max16 ->
               <<16:8, <<V:16/big>>/binary>>;
            V >= ?min32 andalso V =< ?max32 ->
               <<32:8, <<V:32/big>>/binary>>;
            V >= ?min64 andalso V =< ?max64 ->
               <<64:8, <<V:64/big>>/binary>>;
            true ->
               throw({exceeded_the_integer, V})
         end;
      erlang:is_float(V) ->
         if
            V >= ?minF32 andalso V =< ?maxF32 ->
               <<33:8, <<V:32/big-float>>/binary>>;
            V >= ?minF64 andalso V =< ?maxF64 ->
               <<65:8, <<V:64/big-float>>/binary>>;
            true ->
               throw({exceeded_the_float, V})
         end;
      true ->
         throw({is_not_number, V})
   end.

string(Str) when is_binary(Str) ->
   StrLen = byte_size(Str),
   case StrLen > 65535 of
      true ->
         throw({string_too_long, StrLen, Str});
      _ ->
         [<<StrLen:16/big>>, Str]
   end;
string(Str) ->
   case unicode:characters_to_binary(Str, utf8) of
      {error, Encoded, _Rest} ->
         throw({invalid_utf8_string, Str, Encoded});
      {incomplete, Encoded, _Rest} ->
         throw({incomplete_utf8_string, Str, Encoded});
      Str2 ->
         StrLen = byte_size(Str2),
         case StrLen > 65535 of
            true ->
               throw({string_too_long, StrLen, Str});
            _ ->
               [<<StrLen:16/big>>, Str2]
         end
   end.

decode(Bin) ->
   <<MsgId:16/big, MsgBin/binary>> = Bin,
   decodeBin(MsgId, MsgBin).

deIntegerList(0, MsgBin, RetList) ->
   {lists:reverse(RetList), MsgBin};
deIntegerList(N, MsgBin, RetList) ->
   <<IntBits:8, Int:IntBits/big-signed, LeftBin/binary>> = MsgBin,
   deIntegerList(N - 1, LeftBin, [Int | RetList]).

deNumberList(0, MsgBin, RetList) ->
   {lists:reverse(RetList), MsgBin};
deNumberList(N, MsgBin, RetList) ->
   <<NumBits:8, NumBin/binary>> = MsgBin,
   case NumBits of
      33 ->
         <<Float:32/big-float, LeftBin/binary>> = NumBin,
         deNumberList(N - 1, LeftBin, [Float | RetList]);
      65 ->
         <<Float:64/big-float, LeftBin/binary>> = NumBin,
         deNumberList(N - 1, LeftBin, [Float | RetList]);
      _ ->
         <<Int:NumBits/big-signed, LeftBin/binary>> = NumBin,
         deNumberList(N - 1, LeftBin, [Int | RetList])
   end.

deStringList(0, MsgBin, _RefSize, RetList) ->
   {lists:reverse(RetList), MsgBin};
deStringList(N, MsgBin, RefSize, RetList) ->
   <<Len:16/big, StrBin:Len/binary-unit:8, LeftBin/binary>> = MsgBin,
   case Len < ?BinaryShareSize of
      true ->
         deStringList(N - 1, LeftBin, RefSize, [StrBin | RetList]);
      _ ->
         case RefSize / Len > ?BinaryCopyRatio of
            true ->
               StrBinCopy = binary:copy(StrBin),
               deStringList(N - 1, LeftBin, RefSize, [StrBinCopy | RetList]);
            _ ->
               deStringList(N - 1, LeftBin, RefSize, [StrBin | RetList])
         end
   end.

deRecordList(0, _MsgId, MsgBin, RetList) ->
   {lists:reverse(RetList), MsgBin};
deRecordList(N, MsgId, MsgBin, RetList) ->
   {Tuple, LeftBin} = decodeRec(MsgId, MsgBin),
   deRecordList(N - 1, MsgId, LeftBin, [Tuple | RetList]).

encodeIol(RecMsg) ->
   encodeIol(erlang:element(1, RecMsg), RecMsg).

encodeBin(RecMsg) ->
   erlang:iolist_to_binary(encodeIol(RecMsg)).

subEncode(RecMsg) ->
   subEncode(erlang:element(1, RecMsg), RecMsg).

subEncode(playerInfo, {_, V1, V2, V3, V4, V5, V6}) ->
	[?int32(V1), ?string(V2), ?int32(V3), ?int32(V4), ?int32(V5), ?int32(V6)];
subEncode(roomInfo, {_, V1, V2, V3, V4}) ->
	[?string(V1), ?string(V2), ?int32(V3), ?int32(V4)];
subEncode(card, {_, V1, V2}) ->
	[?int32(V1), ?int32(V2)];
subEncode(scoreInfo, {_, V1, V2, V3, V4}) ->
	[?int32(V1), ?string(V2), ?int32(V3), ?string(V4)];
subEncode(_, _) ->
	[].

encodeIol(playerInfo, {_, V1, V2, V3, V4, V5, V6}) ->
	[<<1:16/big-unsigned>>, ?int32(V1), ?string(V2), ?int32(V3), ?int32(V4), ?int32(V5), ?int32(V6)];
encodeIol(roomInfo, {_, V1, V2, V3, V4}) ->
	[<<2:16/big-unsigned>>, ?string(V1), ?string(V2), ?int32(V3), ?int32(V4)];
encodeIol(card, {_, V1, V2}) ->
	[<<3:16/big-unsigned>>, ?int32(V1), ?int32(V2)];
encodeIol(scoreInfo, {_, V1, V2, V3, V4}) ->
	[<<4:16/big-unsigned>>, ?int32(V1), ?string(V2), ?int32(V3), ?string(V4)];
encodeIol(sc_error, {_, V1, V2}) ->
	[<<5:16/big-unsigned>>, ?int32(V1), ?string(V2)];
encodeIol(cs_handshake, {_, V1, V2}) ->
	[<<1001:16/big-unsigned>>, ?int32(V1), ?int32(V2)];
encodeIol(sc_handshake, {_, V1}) ->
	[<<1002:16/big-unsigned>>, ?int32(V1)];
encodeIol(cs_heartbeat, {_}) ->
	[<<1003:16/big-unsigned>>];
encodeIol(sc_heartbeat, {_}) ->
	[<<1004:16/big-unsigned>>];
encodeIol(cs_login, {_, V1}) ->
	[<<1005:16/big-unsigned>>, ?string(V1)];
encodeIol(sc_login, {_, V1, V2, V3}) ->
	[<<1006:16/big-unsigned>>, ?int32(V1), ?string(V2), ?record(V3)];
encodeIol(cs_list_rooms, {_}) ->
	[<<2001:16/big-unsigned>>];
encodeIol(sc_list_rooms, {_, V1}) ->
	[<<2002:16/big-unsigned>>, ?list_record(V1)];
encodeIol(cs_create_room, {_, V1}) ->
	[<<2003:16/big-unsigned>>, ?string(V1)];
encodeIol(sc_room_update, {_, V1, V2, V3}) ->
	[<<2004:16/big-unsigned>>, ?string(V1), ?int32(V2), ?list_record(V3)];
encodeIol(cs_join_room, {_, V1}) ->
	[<<2005:16/big-unsigned>>, ?string(V1)];
encodeIol(cs_leave_room, {_, V1}) ->
	[<<2006:16/big-unsigned>>, ?string(V1)];
encodeIol(cs_quick_match, {_}) ->
	[<<2007:16/big-unsigned>>];
encodeIol(cs_add_ai, {_}) ->
	[<<2008:16/big-unsigned>>];
encodeIol(sc_ai_added, {_, V1, V2}) ->
	[<<2009:16/big-unsigned>>, ?string(V1), ?int32(V2)];
encodeIol(cs_game_start, {_}) ->
	[<<2010:16/big-unsigned>>];
encodeIol(sc_game_start, {_, V1, V2}) ->
	[<<2011:16/big-unsigned>>, ?list_record(V1), ?int32(V2)];
encodeIol(cs_bid, {_, V1}) ->
	[<<2012:16/big-unsigned>>, ?int32(V1)];
encodeIol(sc_bid_made, {_, V1, V2}) ->
	[<<2013:16/big-unsigned>>, ?int32(V1), ?int32(V2)];
encodeIol(sc_turn_to_bid, {_, V1, V2}) ->
	[<<2014:16/big-unsigned>>, ?int32(V1), ?list_int32(V2)];
encodeIol(cs_play, {_, V1}) ->
	[<<2015:16/big-unsigned>>, ?list_record(V1)];
encodeIol(sc_player_played, {_, V1, V2}) ->
	[<<2016:16/big-unsigned>>, ?int32(V1), ?list_record(V2)];
encodeIol(cs_pass, {_}) ->
	[<<2017:16/big-unsigned>>];
encodeIol(sc_player_passed, {_, V1}) ->
	[<<2018:16/big-unsigned>>, ?int32(V1)];
encodeIol(cs_play_hint, {_}) ->
	[<<2019:16/big-unsigned>>];
encodeIol(sc_play_hint, {_, V1}) ->
	[<<2020:16/big-unsigned>>, ?list_record(V1)];
encodeIol(sc_turn_to_play, {_, V1, V2}) ->
	[<<2021:16/big-unsigned>>, ?int32(V1), ?list_record(V2)];
encodeIol(sc_landlord_selected, {_, V1, V2, V3}) ->
	[<<2022:16/big-unsigned>>, ?int32(V1), ?list_record(V2), ?int32(V3)];
encodeIol(sc_game_over, {_, V1, V2}) ->
	[<<2023:16/big-unsigned>>, ?int32(V1), ?list_record(V2)];
encodeIol(cs_ready, {_, V1}) ->
	[<<2024:16/big-unsigned>>, ?int32(V1)];
encodeIol(sc_player_ready, {_, V1, V2, V3}) ->
	[<<2025:16/big-unsigned>>, ?int32(V1), ?int32(V2), ?int32(V3)];
encodeIol(_, _) ->
	[].

decodeRec(1, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, V4:32/big-signed, V5:32/big-signed, V6:32/big-signed, LeftBin3/binary>> = LeftBin2,
	MsgRec = {playerInfo, V1, V2, V3, V4, V5, V6},
	{MsgRec, LeftBin3};
decodeRec(2, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	<<Len2:16/big-unsigned, TemStrV2:Len2/binary, LeftBin2/binary>> = LeftBin1,
	case Len2 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len2 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, V4:32/big-signed, LeftBin3/binary>> = LeftBin2,
	MsgRec = {roomInfo, V1, V2, V3, V4},
	{MsgRec, LeftBin3};
decodeRec(3, LeftBin0) ->
	<<V1:32/big-signed, V2:32/big-signed, LeftBin1/binary>> = LeftBin0,
	MsgRec = {card, V1, V2},
	{MsgRec, LeftBin1};
decodeRec(4, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, LeftBin3/binary>> = LeftBin2,
	<<Len2:16/big-unsigned, TemStrV4:Len2/binary, LeftBin4/binary>> = LeftBin3,
	case Len2 < ?BinaryShareSize of
		true ->
			V4 = TemStrV4;
		_ ->
			case RefSize / Len2 > ?BinaryCopyRatio of
				true ->
					V4 = binary:copy(TemStrV4);
				_ ->
					V4 = TemStrV4
			end
	end,
	MsgRec = {scoreInfo, V1, V2, V3, V4},
	{MsgRec, LeftBin4};
decodeRec(_, _) ->
	{{}, <<>>}.

decodeBin(1, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, V4:32/big-signed, V5:32/big-signed, V6:32/big-signed, LeftBin3/binary>> = LeftBin2,
	{commonHer, {playerInfo, V1, V2, V3, V4, V5, V6}};
decodeBin(2, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	<<Len2:16/big-unsigned, TemStrV2:Len2/binary, LeftBin2/binary>> = LeftBin1,
	case Len2 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len2 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, V4:32/big-signed, LeftBin3/binary>> = LeftBin2,
	{commonHer, {roomInfo, V1, V2, V3, V4}};
decodeBin(3, LeftBin0) ->
	<<V1:32/big-signed, V2:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{commonHer, {card, V1, V2}};
decodeBin(4, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<V3:32/big-signed, LeftBin3/binary>> = LeftBin2,
	<<Len2:16/big-unsigned, TemStrV4:Len2/binary, LeftBin4/binary>> = LeftBin3,
	case Len2 < ?BinaryShareSize of
		true ->
			V4 = TemStrV4;
		_ ->
			case RefSize / Len2 > ?BinaryCopyRatio of
				true ->
					V4 = binary:copy(TemStrV4);
				_ ->
					V4 = TemStrV4
			end
	end,
	{commonHer, {scoreInfo, V1, V2, V3, V4}};
decodeBin(5, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	{commonHer, {sc_error, V1, V2}};
decodeBin(1001, LeftBin0) ->
	<<V1:32/big-signed, V2:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{loginHer, {cs_handshake, V1, V2}};
decodeBin(1002, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{loginHer, {sc_handshake, V1}};
decodeBin(1003, LeftBin0) ->
	{loginHer, {cs_heartbeat}};
decodeBin(1004, LeftBin0) ->
	{loginHer, {sc_heartbeat}};
decodeBin(1005, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	{loginHer, {cs_login, V1}};
decodeBin(1006, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV2:Len1/binary, LeftBin2/binary>> = LeftBin1,
	case Len1 < ?BinaryShareSize of
		true ->
			V2 = TemStrV2;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V2 = binary:copy(TemStrV2);
				_ ->
					V2 = TemStrV2
			end
	end,
	<<IsUndef1:8/big-unsigned, LeftBin3/binary>> = LeftBin2,
	case IsUndef1 of
		0 ->
			V3 = undefined,
			LeftBin4 = LeftBin3 ;
		_ ->
			{V3, LeftBin4} = decodeRec(1, LeftBin3)
	end,
	{loginHer, {sc_login, V1, V2, V3}};
decodeBin(2001, LeftBin0) ->
	{roleHer, {cs_list_rooms}};
decodeBin(2002, LeftBin0) ->
	<<Len1:16/big-unsigned, LeftBin1/binary>> = LeftBin0,
	{V1, LeftBin2} = deRecordList(Len1, 2, LeftBin1, []),
	{roleHer, {sc_list_rooms, V1}};
decodeBin(2003, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	{roleHer, {cs_create_room, V1}};
decodeBin(2004, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	<<V2:32/big-signed, LeftBin2/binary>> = LeftBin1,
	<<Len2:16/big-unsigned, LeftBin3/binary>> = LeftBin2,
	{V3, LeftBin4} = deRecordList(Len2, 1, LeftBin3, []),
	{roleHer, {sc_room_update, V1, V2, V3}};
decodeBin(2005, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	{roleHer, {cs_join_room, V1}};
decodeBin(2006, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	{roleHer, {cs_leave_room, V1}};
decodeBin(2007, LeftBin0) ->
	{roleHer, {cs_quick_match}};
decodeBin(2008, LeftBin0) ->
	{roleHer, {cs_add_ai}};
decodeBin(2009, LeftBin0) ->
	RefSize = binary:referenced_byte_size(LeftBin0),
	<<Len1:16/big-unsigned, TemStrV1:Len1/binary, LeftBin1/binary>> = LeftBin0,
	case Len1 < ?BinaryShareSize of
		true ->
			V1 = TemStrV1;
		_ ->
			case RefSize / Len1 > ?BinaryCopyRatio of
				true ->
					V1 = binary:copy(TemStrV1);
				_ ->
					V1 = TemStrV1
			end
	end,
	<<V2:32/big-signed, LeftBin2/binary>> = LeftBin1,
	{roleHer, {sc_ai_added, V1, V2}};
decodeBin(2010, LeftBin0) ->
	{roleHer, {cs_game_start}};
decodeBin(2011, LeftBin0) ->
	<<Len1:16/big-unsigned, LeftBin1/binary>> = LeftBin0,
	{V1, LeftBin2} = deRecordList(Len1, 3, LeftBin1, []),
	<<V2:32/big-signed, LeftBin3/binary>> = LeftBin2,
	{roleHer, {sc_game_start, V1, V2}};
decodeBin(2012, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{roleHer, {cs_bid, V1}};
decodeBin(2013, LeftBin0) ->
	<<V1:32/big-signed, V2:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{roleHer, {sc_bid_made, V1, V2}};
decodeBin(2014, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	<<Len1:16/big-unsigned, LeftBin2/binary>> = LeftBin1,
	<<ListBin1:Len1/big-binary-unit:32, LeftBin3/binary>> = LeftBin2,
	V2 = [TemV || <<TemV:32/big-signed>> <= ListBin1],
	{roleHer, {sc_turn_to_bid, V1, V2}};
decodeBin(2015, LeftBin0) ->
	<<Len1:16/big-unsigned, LeftBin1/binary>> = LeftBin0,
	{V1, LeftBin2} = deRecordList(Len1, 3, LeftBin1, []),
	{roleHer, {cs_play, V1}};
decodeBin(2016, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	<<Len1:16/big-unsigned, LeftBin2/binary>> = LeftBin1,
	{V2, LeftBin3} = deRecordList(Len1, 3, LeftBin2, []),
	{roleHer, {sc_player_played, V1, V2}};
decodeBin(2017, LeftBin0) ->
	{roleHer, {cs_pass}};
decodeBin(2018, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{roleHer, {sc_player_passed, V1}};
decodeBin(2019, LeftBin0) ->
	{roleHer, {cs_play_hint}};
decodeBin(2020, LeftBin0) ->
	<<Len1:16/big-unsigned, LeftBin1/binary>> = LeftBin0,
	{V1, LeftBin2} = deRecordList(Len1, 3, LeftBin1, []),
	{roleHer, {sc_play_hint, V1}};
decodeBin(2021, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	<<Len1:16/big-unsigned, LeftBin2/binary>> = LeftBin1,
	{V2, LeftBin3} = deRecordList(Len1, 3, LeftBin2, []),
	{roleHer, {sc_turn_to_play, V1, V2}};
decodeBin(2022, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	<<Len1:16/big-unsigned, LeftBin2/binary>> = LeftBin1,
	{V2, LeftBin3} = deRecordList(Len1, 3, LeftBin2, []),
	<<V3:32/big-signed, LeftBin4/binary>> = LeftBin3,
	{roleHer, {sc_landlord_selected, V1, V2, V3}};
decodeBin(2023, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	<<Len1:16/big-unsigned, LeftBin2/binary>> = LeftBin1,
	{V2, LeftBin3} = deRecordList(Len1, 4, LeftBin2, []),
	{roleHer, {sc_game_over, V1, V2}};
decodeBin(2024, LeftBin0) ->
	<<V1:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{roleHer, {cs_ready, V1}};
decodeBin(2025, LeftBin0) ->
	<<V1:32/big-signed, V2:32/big-signed, V3:32/big-signed, LeftBin1/binary>> = LeftBin0,
	{roleHer, {sc_player_ready, V1, V2, V3}};
decodeBin(_, _) ->
	{undefinedHer, {}}.

getMsgName(1)-> playerInfo;
getMsgName(2)-> roomInfo;
getMsgName(3)-> card;
getMsgName(4)-> scoreInfo;
getMsgName(5)-> sc_error;
getMsgName(1001)-> cs_handshake;
getMsgName(1002)-> sc_handshake;
getMsgName(1003)-> cs_heartbeat;
getMsgName(1004)-> sc_heartbeat;
getMsgName(1005)-> cs_login;
getMsgName(1006)-> sc_login;
getMsgName(2001)-> cs_list_rooms;
getMsgName(2002)-> sc_list_rooms;
getMsgName(2003)-> cs_create_room;
getMsgName(2004)-> sc_room_update;
getMsgName(2005)-> cs_join_room;
getMsgName(2006)-> cs_leave_room;
getMsgName(2007)-> cs_quick_match;
getMsgName(2008)-> cs_add_ai;
getMsgName(2009)-> sc_ai_added;
getMsgName(2010)-> cs_game_start;
getMsgName(2011)-> sc_game_start;
getMsgName(2012)-> cs_bid;
getMsgName(2013)-> sc_bid_made;
getMsgName(2014)-> sc_turn_to_bid;
getMsgName(2015)-> cs_play;
getMsgName(2016)-> sc_player_played;
getMsgName(2017)-> cs_pass;
getMsgName(2018)-> sc_player_passed;
getMsgName(2019)-> cs_play_hint;
getMsgName(2020)-> sc_play_hint;
getMsgName(2021)-> sc_turn_to_play;
getMsgName(2022)-> sc_landlord_selected;
getMsgName(2023)-> sc_game_over;
getMsgName(2024)-> cs_ready;
getMsgName(2025)-> sc_player_ready;
getMsgName(_) -> undefiend.

