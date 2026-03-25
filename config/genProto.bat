@echo off
cd /d "%~dp0"
escript.exe config\genProto proto erl include src/proto ts cli/src/network/proto %*
