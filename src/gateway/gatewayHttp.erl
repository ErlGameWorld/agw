-module(gatewayHttp).

-include_lib("eWSrv/include/wsCom.hrl").
-include("common.hrl").
-include("game.hrl").
-include("server.hrl").

-export([
	handle/3
]).

handle('GET', <<"/health">>, _Req) ->
	{200, [{<<"Content-Type">>, <<"application/json">>}], <<"{\"status\":\"ok\"}">>};

handle('GET', <<"/status">>, _Req) ->
	Body = json:encode(#{
		status => ok,
		node => node(),
		time => utTime:now()
	}),
	{200, [{<<"Content-Type">>, <<"application/json">>}], Body};

handle('GET', <<"/ping">>, _Req) ->
	{200, [{<<"Content-Type">>, <<"text/plain">>}], <<"pong">>};

% 静态文件处理函数
handle('GET', <<"/">>, _WsReq) ->
	% 构建静态文件路径
	FilePath = filename:join([code:priv_dir(agw), <<"static">>, <<"index.html">>]),
	% 检查文件是否存在
	case readIndex(FilePath) of
		{ok, FileContent} ->
			InjectedContent = injectWsIpPort(FileContent),
			ContentType = contentType(FilePath),
			Headers = [{<<"Content-Type">>, ContentType}],
			{200, Headers, InjectedContent};
		{error, Error} ->
			{400, [{<<"Content-Type">>, <<"application/json">>}], json:encode(#{<<"error">> => Error})}
	end;
handle('GET', <<"/assets/", LBin/binary>>, _WsReq) ->
	% 检查是否为静态文件路径（支持/assets/路径和常见静态文件扩展名）
	FilePath = filename:join([code:priv_dir(agw), <<"static/assets">>, LBin]),
	% 检查文件是否存在
	case readAssets(FilePath) of
		{ok, FileContent} ->
			ContentType = contentType(FilePath),
			Headers = [{<<"Content-Type">>, ContentType}],
			{200, Headers, FileContent};
		{error, Error} ->
			{400, [{<<"Content-Type">>, <<"application/json">>}], json:encode(#{<<"error">> => Error})}
	end;

handle(_Method, _Path, _Req) ->
	{404, [{<<"Content-Type">>, <<"text/plain">>}], <<"Not Found">>}.

readIndex(FilePath) ->
	case ets:lookup(?assetsCache, FilePath) of
		[] ->
			case file:read_file(FilePath, [raw]) of
				{ok, FileContent} ->
					LFileContent = injectWsIpPort(FileContent),
					ets:insert(?assetsCache, {FilePath, LFileContent}),
					{ok, LFileContent};
				{error, Error} ->
					{error, Error}
			end;
		[{_FilePath, FileContent}] ->
			{ok, FileContent}
	end.

readAssets(FilePath) ->
	case ets:lookup(?assetsCache, FilePath) of
		[] ->
			case file:read_file(FilePath, [raw]) of
				{ok, FileContent} ->
					ets:insert(?assetsCache, {FilePath, FileContent}),
					{ok, FileContent};
				{error, Error} ->
					{error, Error}
			end;
		[{_FilePath, FileContent}] ->
			{ok, FileContent}
	end.

injectWsIpPort(IndexHtml) ->
	Script = runtimeWsIpPort(),
	case binary:match(IndexHtml, <<"</head>">>) of
		nomatch ->
			<<IndexHtml/binary, Script/binary>>;
		_ ->
			binary:replace(IndexHtml, <<"</head>">>, <<Script/binary, "</head>">>)
	end.

runtimeWsIpPort() ->
	<<"<script>window.__AGW_CONFIG__={wsHost:'", (utTypeCast:toBinary(?devopsCfg:getV(host)))/binary, "',wsPort:", (integer_to_binary(?devopsCfg:getV(ws_port)))/binary, "};</script>">>.

% 获取文件Content-Type
contentType(FilePath) ->
	case filename:extension(FilePath) of
		<<".html">> -> <<"text/html">>;
		<<".css">> -> <<"text/css">>;
		<<".js">> -> <<"text/javascript">>;
		<<".mjs">> -> <<"text/javascript">>;
		<<".png">> -> <<"image/png">>;
		<<".jpg">> -> <<"image/jpeg">>;
		<<".jpeg">> -> <<"image/jpeg">>;
		<<".gif">> -> <<"image/gif">>;
		<<".ico">> -> <<"image/x-icon">>;
		<<".json">> -> <<"application/json">>;
		<<".svg">> -> <<"image/svg+xml">>;
		<<".wasm">> -> <<"application/wasm">>;
		_ -> <<"application/octet-stream">>
	end.
