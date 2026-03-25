-ifndef(__common_h__).
-define(__common_h__, true).

-include_lib("eLog.hrl").

%% IF-DO表达式
-define(If(IFTure, DoThat), (IFTure) andalso (DoThat)).

%% 三目元算符
-define(Case(Cond, Then, That), case Cond of true -> Then; _ -> That end).
-define(Case(Expr, Expect, Then, ExprRet, That), case Expr of Expect -> Then; ExprRet -> That end).

-define(Debug(Format), ?lgDebug(Format)).
-define(Debug(Format, Args), ?lgDebug(Format, Args)).
-define(Debug(Cond, Format, Args), ?If(Cond, ?lgDebug(Format, Args))).

-define(Info(Format), ?lgInfo(Format)).
-define(Info(Format, Args), ?lgInfo(Format, Args)).

-define(Notice(Format), ?lgNotice(Format)).
-define(Notice(Format, Args), ?lgNotice(Format, Args)).

-define(Warn(Format), ?lgWarning(Format)).
-define(Warn(Format, Args), ?lgWarning(Format, Args)).

-define(Error(Format), ?lgError(Format)).
-define(Error(Format, Args), ?lgError(Format, Args)).

-define(Cri(Format), ?lgCritical(Format)).
-define(Cri(Format, Args), ?lgCritical(Format, Args)).

%% 获取堆栈
-define(GSS(Strace),
	try throw(0)
	catch _:_:Strace ->
		Strace
	end).

%% 获取堆栈字符串
-define(PStr(Tag, Strace),
	try
		throw(0)
	catch _:_:Strace ->
		eFmt:format("~p:~s", [Tag, utParseStack:parseStack(Strace)])
	end).
-define(Stacktrace(Stacktrace), ?lgError(eLog:parseStack(Stacktrace))).
-define(Stacktrace(Class, Reason, Stacktrace), ?lgError(eLog:parseStack(Class, Reason, Stacktrace))).


-endif.
