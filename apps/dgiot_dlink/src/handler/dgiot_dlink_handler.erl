%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 DGIOT Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(dgiot_dlink_handler).
-author("johnliu").
-behavior(dgiot_rest).
-dgiot_rest(all).
-include_lib("dgiot/include/logger.hrl").

%% API
-export([swagger_dlink/0]).
-export([handle/4]).
%%-export([do_request/4]).

%% API描述
%% 支持二种方式导入
%% 示例:
%% 1. Metadata为map表示的JSON,
%%    dgiot_http_server:bind(<<"/dlink">>, ?MODULE, [], Metadata)
%% 2. 从模块的priv/swagger/下导入
%%    dgiot_http_server:bind(<<"/swagger_dlink.json">>, ?MODULE, [], priv)
swagger_dlink() ->
    [
        dgiot_http_server:bind(<<"/swagger_dlink.json">>, ?MODULE, [], priv)
    ].

%%%===================================================================
%%% 请求处理
%%%  如果登录, Context 内有 <<"user">>, version
%%%===================================================================

-spec handle(OperationID :: atom(), Args :: map(), Context :: map(), Req :: dgiot_req:req()) ->
    {Status :: dgiot_req:http_status(), Body :: map()} |
    {Status :: dgiot_req:http_status(), Headers :: map(), Body :: map()} |
    {Status :: dgiot_req:http_status(), Headers :: map(), Body :: map(), Req :: dgiot_req:req()}.

handle(OperationID, Args, Context, Req) ->
   io:format("~s ~p OperationID: ~p  ~n", [?FILE, ?LINE, OperationID]),
    Headers = #{},
    case catch do_request(OperationID, Args, Context, Req) of
        {ErrType, Reason} when ErrType == 'EXIT'; ErrType == error ->
            Err = case is_binary(Reason) of
                      true -> Reason;
                      false -> dgiot_utils:format("~p", [Reason])
                  end,
            {500, Headers, #{<<"error">> => Err}};
        ok ->
            {200, Headers, #{}, Req};
        {ok, Res} ->
            {200, Headers, Res, Req};
        {Status, Res} ->
            {Status, Headers, Res, Req};
        {Status, NewHeaders, Res} ->
            {Status, maps:merge(Headers, NewHeaders), Res, Req};
        {Status, NewHeaders, Res, NewReq} ->
            {Status, maps:merge(Headers, NewHeaders), Res, NewReq}
    end.


%%%===================================================================
%%% 内部函数 Version:API版本
%%%===================================================================
%% Proctol 概要: 获取Dlink协议列表
%% OperationId:protocol
%% 请求:GET /iotapi/protocol
do_request(get_protocol, _Body, _Context, _Req) ->
    Protocols =
        case dgiot_data:get(get_protocol) of
            not_find ->
                P = dgiot_dlink:get_all_protocol(),
                dgiot_data:insert(get_protocol, P);
            P ->
                P
        end,
    {200, Protocols};

%% Proctol 概要: 获取Dlink json信息
%% OperationId:dlinkjson
%% 请求:GET /iotapi/dlinkjson
do_request(get_dlinkjson, #{<<"type">> := <<"swaggerTree">>}, _Context, _Req) ->
    {ok, Swagger} = dgiot_swagger:tree(),
    {file, Here} = code:is_loaded(?MODULE),
    Dir = filename:dirname(filename:dirname(Here)),
    FileName = <<"swagger.json">>,
    SwaggerFile = dgiot_httpc:url_join([Dir, "/priv/json/", dgiot_utils:to_list(FileName)]),
    case dgiot_data:get(swaggerTree) of
        not_find ->
            file:write_file(SwaggerFile, jsx:encode(Swagger)),
            dgiot_data:insert(swaggerTree, <<"swaggerTree">>);
        _ ->
            pass
    end,
    SwaggerTree = dgiot_dlink:get_json(<<"swaggerTree">>),
    {200, SwaggerTree};

do_request(get_dlinkjson, #{<<"type">> := <<"Table">>}, _Context, _Req) ->
    {ok, Tables} = dgiot_parse:get_schemas(),
    {200, Tables};

do_request(get_dlinkjson, #{<<"type">> := Type}, _Context, _Req) ->
    DlinkJson = dgiot_dlink:get_json(Type),
    {200, DlinkJson};



do_request(delete_topic, #{<<"topic">> := Topic}=_Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
%%    取消订阅
    [_Head, _User, Key | _] = re:split(Topic, "/"),
    TopicKey = <<"dg_user_", Key/binary>>,
%%    io:format("~s ~p TopicKey ~p   Topic ~p SessionToken ~p ~n", [?FILE, ?LINE, TopicKey,Topic, SessionToken]),
    dgiot_mqtt:unsubscribe(SessionToken, Topic), case dgiot_data:get({page_router_key, SessionToken, TopicKey}) of
                                                     Topic ->
                                                         dgiot_mqtt:unsubscribe(SessionToken, Topic),
                                                         dgiot_data:delete({page_router_key, SessionToken, TopicKey});
                                                     _ ->
                                                         pass
                                                 end,
    {200, #{<<"message">> => <<"取消订阅成功"/utf8>>}};


do_request(get_topic, #{<<"topic">> := Topic}=_Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
%%    查询
%%    io:format("~s ~p Topic ~p SessionToken ~p   ~n", [?FILE, ?LINE, Topic, SessionToken]),
    [_Head, _User, Key | _] = re:split(Topic, "/"),
    TopicKey = <<"dg_user_", Key/binary>>,
    SubTopic = dgiot_data:get({page_router_key, SessionToken, TopicKey}),

    {200, #{<<"message">> => SubTopic}};

do_request(post_topic, #{<<"topic">> := Topic} = _Args, #{<<"sessionToken">> := SessionToken} = _Context, _Req) ->
    io:format("~s ~p Topic ~p SessionToken ~p   ~n", [?FILE, ?LINE, Topic, SessionToken]),
%%    订阅topic
    [_Head, _User, Key | _] = re:split(Topic, "/"),
    TopicKey = <<"dg_user_", Key/binary>>,
%%    io:format("~s ~p Topic ~p SessionToken ~p  TopicKey ~p ~n", [?FILE, ?LINE, Topic, SessionToken,TopicKey]),
    case dgiot_data:get({page_router_key, SessionToken, TopicKey}) of
        not_find ->
            dgiot_mqtt:subscribe(SessionToken, Topic),
%%            io:format("~s ~p TopicKey ~p MS ~p ~n", [?FILE, ?LINE, TopicKey,MS]),
            dgiot_data:insert({page_router_key, SessionToken, TopicKey}, Topic);
        OldTopic ->
            dgiot_mqtt:unsubscribe(SessionToken, OldTopic),
            io:format("~s ~p OldTopic ~p ~n",[?FILE,?LINE,OldTopic]),
            timer:sleep(1),
            dgiot_mqtt:subscribe(SessionToken, Topic),
%%            io:format("~s ~p TopicKey ~p MSo ~p ~n", [?FILE, ?LINE, TopicKey,MSo]),
            dgiot_data:insert({page_router_key, SessionToken, TopicKey}, Topic)

    end,
    {200, #{<<"message">> => <<"订阅成功"/utf8>>, <<"Topic">> => Topic, <<"TopicKey">> => TopicKey}};

do_request(_OperationId, _Args, _Context, _Req) ->
    {error, <<"Not Allowed.">>}.


