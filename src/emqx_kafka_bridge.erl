%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Modified by Ramez Hanna <rhanna@iotblue.net>
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

-module(emqx_kafka_bridge).

-include("emqx_kafka_bridge.hrl").

-include_lib("emqx/include/emqx.hrl").

%%-include_lib("emqx/include/emqx_mqtt.hrl").


-import(string,[concat/2]).
-import(lists,[nth/2]). 

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/4, on_client_disconnected/3]).

% -export([on_client_subscribe/4, on_client_unsubscribe/4]).

% -export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).


%% Called when the plugin application start
load(Env) ->
	ekaf_init([Env]),
    emqx:hook('client.connected', fun ?MODULE:on_client_connected/4, [Env]),
    emqx:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqx:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqx:hook('message.delivered', fun ?MODULE:on_message_delivered/3, [Env]),
    emqx:hook('message.acked', fun ?MODULE:on_message_acked/3, [Env]).

on_client_connected(#{client_id := ClientId, username := Username}, ConnAck, ConnAttrs, _Env) ->
    % io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck]),
    % produce_kafka_payload(mochijson2:encode([
    %     {type, <<"event">>},
    %     {status, <<"connected">>},
    %     {deviceId, ClientId}
    % ])),
    % produce_kafka_payload(<<"event">>, Client),
    {ok, Event} = format_event(connected, ClientId, Username),
    produce_kafka_payload(Event),
    ok.

on_client_disconnected(#{client_id := ClientId, username := Username}, Reason, _Env) ->
    % io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]),
    % Message = mochijson2:encode([
    %     {type, },
    %     {status, <<"disconnected">>},
    %     {deviceId, ClientId}
    % ]),
    % produce_kafka_payload(<<"event">>, _Client),
    {ok, Event} = format_event(disconnected, ClientId, Username),
    produce_kafka_payload(Event),	
    ok.

%% transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message, _Env) ->
    % io:format("publish message : ~s~n", [emqttd_message:format(Message)]),
    {ok, Payload} = format_payload(Message),
    produce_kafka_payload(Payload),	
    {ok, Message}.

on_message_delivered(#{client_id := ClientId}, Message, _Env) ->
    % io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

on_message_acked(#{client_id := ClientId}, Message, _Env) ->
    % io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

ekaf_init(_Env) ->
    {ok, BrokerValues} = application:get_env(emq_kafka_bridge, broker),
    KafkaHost = proplists:get_value(host, BrokerValues),
    KafkaPort = proplists:get_value(port, BrokerValues),
    KafkaPartitionStrategy= proplists:get_value(partitionstrategy, BrokerValues),
    KafkaPartitionWorkers= proplists:get_value(partitionworkers, BrokerValues),
    application:set_env(ekaf, ekaf_bootstrap_broker,  {KafkaHost, list_to_integer(KafkaPort)}),
    application:set_env(ekaf, ekaf_partition_strategy, KafkaPartitionStrategy),
    application:set_env(ekaf, ekaf_per_partition_workers, KafkaPartitionWorkers),
    application:set_env(ekaf, ekaf_buffer_ttl, 10),
    application:set_env(ekaf, ekaf_max_downtime_buffer_size, 5),
    % {ok, _} = application:ensure_all_started(kafkamocker),
    {ok, _} = application:ensure_all_started(gproc),
    % {ok, _} = application:ensure_all_started(ranch),    
    {ok, _} = application:ensure_all_started(ekaf).

format_event(Action, ClientId, Username) ->
    Event = [{action, Action},
                {device_id, ClientId},
                {username, Username}],
    {ok, Event}.

format_payload(Message) ->
    {ClientId, Username} = format_from(Message#message.from),
    Payload = [{action, message_publish},
                  {device_id, ClientId},
                  {username, Username},
                  {topic, Message#message.topic},
                  {payload, Message#message.payload},
                  {ts, emqx_time:now_secs(Message#message.timestamp)}],
    {ok, Payload}.

format_from({ClientId, Username}) ->
    {ClientId, Username};
format_from(From) when is_atom(From) ->
    {a2b(From), a2b(From)};
format_from(_) ->
    {<<>>, <<>>}.

a2b(A) -> erlang:atom_to_binary(A, utf8).

%% Called when the plugin application stop
unload() ->
    emqx:unhook('client.connected', fun ?MODULE:on_client_connected/4),
    emqx:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    % emqx:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    % emqx:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    % emqx:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    % emqx:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqx:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqx:unhook('message.delivered', fun ?MODULE:on_message_delivered/3),
    emqx:unhook('message.acked', fun ?MODULE:on_message_acked/3).

produce_kafka_payload(Message) ->
    Topic = <<"Processing">>,
    Payload = iolist_to_binary(mochijson2:encode(Message)),
    ekaf:produce_async_batched(Topic, Payload).
    % ekaf:produce_async(Topic, Payload).
	% io:format("send to kafka payload topic: ~s, data: ~s~n", [Topic, Payload]),
	% {ok, KafkaValue} = application:get_env(emq_kafka_bridge, broker),
	% Topic = proplists:get_value(payloadtopic, KafkaValue),
    % lager:debug("send to kafka payload topic: ~s, data: ~s~n", [Topic, Message]),
    
