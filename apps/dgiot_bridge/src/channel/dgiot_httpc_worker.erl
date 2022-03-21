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
-module(dgiot_httpc_worker).
-author("johnliu").
-behaviour(gen_server).
-include_lib("dgiot/include/logger.hrl").
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([
    start/1,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {tid, id, page = 1, token, refreshtoken, sleep = 12}).

%%%===================================================================
%%% API
%%%===================================================================
start(Args) ->
    supervisor:start_child(dgiot_httpc, [Args]).

start_link(#{
    <<"channelid">> := ChannelId,
    <<"productid">> := ProductId,
    <<"devaddr">> := DevAddr
} = Args) ->
    DeviceId = dgiot_parse:get_deviceid(ProductId, DevAddr),
    case dgiot_data:lookup({ChannelId, DeviceId, httpc}) of
        {ok, Pid} when is_pid(Pid) ->
            is_process_alive(Pid) andalso gen_server:call(Pid, stop, 5000);
        _Reason ->
            ok
    end,
    Server = list_to_atom(lists:concat([httpc, dgiot_utils:to_list(ChannelId), dgiot_utils:to_list(DeviceId)])),
    gen_server:start_link({local, Server}, ?MODULE, [Args], []).

init([#{
    <<"channelid">> := ChannelId,
    <<"productid">> := ProductId,
    <<"devaddr">> := DevAddr
}]) ->
    DeviceId = dgiot_parse:get_deviceid(ProductId, DevAddr),
    dgiot_data:insert({ChannelId, DeviceId, httpc}, self()),
    erlang:send_after(10000, self(), start),
    {ok, #state{tid = ChannelId, id = DeviceId}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(start, #state{tid = Tid, sleep = Sleep} = State) ->
    Url = "http://127.0.0.1:5080/iotapi/login",
    Headers =  [
        {"accept", "application/json"},
        {"Content-Type", "text/plain"}
    ],
    Content = "text/plain",
    Body = dgiot_json:encode(#{
        <<"password">> => <<"dgiot_dev">>,
        <<"username">> =>  <<"dgiot_dev">>
    }),
    case dgiot_http_client:request(post, {Url, Headers, Content, Body}) of
        {ok,R} ->
            case jsx:is_json(dgiot_utils:to_binary(R)) of
                true ->
                    Bin = dgiot_utils:to_binary(R),
                    io:format("R1 ~p ",[maps:get(<<"username">>, jsx:decode(Bin, [{labels, binary}, return_maps]),<<"">>)]);
                _ ->
                    io:format("R2 ~s ",[R])
            end;
        {error, Reason} ->
            ?LOG(info,"Reason ~p ",[Reason])
    end,
    erlang:send_after(Sleep * 1000, self(), start),
    {noreply, State#state{tid = Tid}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{tid = Tid, id = Id} = _State) ->
    dgiot_data:delete({Tid, Id, httpc}),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
