-ifndef(__error_code_h__).
-define(__error_code_h__, true).

-define(OK, 0).                                        %% 成功

-define(ERR_SYSTEM_ERROR, 1).                           %% 系统错误
-define(ERR_LOGIN_FAILED, 2).                           %% 登录失败
-define(ERR_PLAYER_NOT_FOUND, 3).                       %% 玩家不存在
-define(ERR_PLAYER_ALREADY_EXISTS, 4).                  %% 玩家已存在
-define(ERR_GATEWAY_TIMEOUT, 5).                        %% 网关超时
-define(ERR_INVALID_REQUEST, 6).                        %% 无效请求
-define(ERR_NOT_IN_GAME, 7).                            %% 不在游戏中
-define(ERR_GAME_FULL, 8).                              %% 游戏已满
-define(ERR_INVALID_OPERATION, 9).                      %% 无效操作
-define(ERR_PACKET_TOO_FAST, 10).                       %% 发包过快

-endif.